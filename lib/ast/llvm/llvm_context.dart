import 'dart:io';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../expr.dart';
import '../memory.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'coms.dart';
import 'intrinsics.dart';
import 'variables.dart';

class LLVMBasicBlock {
  LLVMBasicBlock(this.bb, this.context, this.inserted);
  final LLVMBasicBlockRef bb;
  final BuildContext context;
  String? label;
  LLVMBasicBlock? parent;
  bool inserted = false;
}

class RootBuildContext with Tys<Variable>, LLVMTypeMixin, Consts {
  RootBuildContext(
      {this.abi = Abi.arm64, String name = 'root', String? targetTriple}) {
    llvmContext = llvm.LLVMContextCreate();
    module = llvm.LLVMModuleCreateWithNameInContext(name.toChar(), llvmContext);
    if (targetTriple != null) {
      tm = llvm.createTarget(module, targetTriple.toChar());
    } else {
      final tt = llvm.LLVMGetDefaultTargetTriple();
      tm = llvm.createTarget(module, tt);
      llvm.LLVMDisposeMessage(tt);
    }

    final info = "Debug Info Version";

    void add(int lv, String name, int size) {
      final (namePointer, nameLength) = name.toNativeUtf8WithLength();
      llvm.LLVMAddModuleFlag(module, lv, namePointer, nameLength,
          llvm.LLVMValueAsMetadata(constI32(size)));
    }

    if (Platform.isWindows) {
      add(1, "CodeView", 1);
    } else {
      final version = "Dwarf Version";
      add(6, version, 2);
    }

    add(1, info, 3);
  }

  @override
  Tys<LifeCycleVariable> defaultImport(String path) {
    throw UnimplementedError();
  }

  @override
  late final GlobalContext importHandler;

  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMTargetMachineRef tm;
  final Abi abi;

  final maps = <String, FunctionDeclare>{};

  final _globalStrings = <String, LLVMValueRef>{};
  LLVMValueRef globalStringPut(String key, LLVMValueRef Function() data) {
    return _globalStrings.putIfAbsent(key, data);
  }

  void dispose() {
    llvm.LLVMDisposeModule(module);
    llvm.LLVMDisposeTargetMachine(tm);
    llvm.LLVMContextDispose(llvmContext);
  }
}

class BuildContext
    with
        Tys<Variable>,
        LLVMTypeMixin,
        BuildMethods,
        Consts,
        DebugMixin,
        StoreLoadMixin,
        OverflowMath,
        Cast {
  BuildContext._baseChild(BuildContext this.parent) : root = parent.root {
    init(parent!);
  }

  BuildContext._compileRun(BuildContext this.parent) : root = parent.root;

  BuildContext.root(this.root) : parent = null;

  final BuildContext? parent;
  @override
  final RootBuildContext root;

  Abi get abi => root.abi;

  @override
  late LLVMBuilderRef builder = llvm.LLVMCreateBuilderInContext(llvmContext);

  @override
  String? get currentPath => super.currentPath ??= parent?.currentPath;

  @override
  GlobalContext get importHandler => root.importHandler;

  void log(int level) {
    print('${' ' * level}$currentPath');
    level += 2;
    for (var child in children) {
      child.log(level);
    }
  }

  @override
  BuildContext? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  @override
  void pushAllTy(Map<Object, Ty> all) {
    super.pushAllTy(all);
    for (var item in all.values) {
      item.currentContext = this;
    }
  }

  /// override: Tys
  @override
  VA? getKVImpl<K, VA>(
      K k, Map<K, List<VA>> Function(Tys<LifeCycleVariable> c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return super.getKVImpl(k, map, handler: handler, test: test) ??
        parent?.getKVImpl(k, map, handler: handler, test: test);
  }

  @override
  Variable? getVariableImpl(Identifier ident) {
    return super.getVariableImpl(ident) ?? parent?.getVariableImpl(ident);
  }

  @override
  BuildContext defaultImport(String path) {
    final child = BuildContext.root(root);
    child.currentPath = path;
    children.add(child);
    if (dBuilder != null) {
      child.debugInit();
    }
    return child;
  }

  final List<BuildContext> children = [];

  void dispose() {
    _dispose();
    llvmMalloc.releaseAll();
  }

  void _dispose() {
    llvm.LLVMDisposeBuilder(builder);
    for (var child in children) {
      child._dispose();
    }
  }

  BuildContext _createChildContext() {
    final child = BuildContext._baseChild(this);
    children.add(child);
    return child;
  }

  StoreVariable? _sret;
  StoreVariable? get sret => _sret;

  LLVMMetadataRef? _fnScope;

  @override
  LLVMMetadataRef get scope => _fnScope ?? parent?.scope ?? unit;

  late final LLVMConstVariable _fn;

  @override
  LLVMValueRef get fnValue => _fn.value;

  LLVMConstVariable buildFnBB(Fn fn,
      [Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>> map = const {},
      void Function(BuildContext context)? onCreated]) {
    final fv = AbiFn.createFunction(this, fn, extra, (fv) {
      final block = fn.block?.clone();
      if (block == null) return;

      final fnContext = fn.currentContext!._createChildContext();
      fnContext._fn = fv;
      fnContext._fnScope = llvm.LLVMGetSubprogram(fv.value);
      fnContext.isFnBBContext = true;
      fnContext.instertFnEntryBB();
      onCreated?.call(fnContext);
      fnContext.initFnParamsStart(fv.value, fn.fnSign.fnDecl, fn, extra,
          map: map);
      block.build(fnContext, free: false);

      final retTy = fn.getRetTy(fnContext);
      if (retTy == BuiltInTy.kVoid) {
        fnContext.ret(null);
      } else {
        block.ret(fnContext);
      }
    });
    return fv;
  }

  /// 同一个文件支持跳转
  bool compileRunMode(Fn fn) => currentPath == fn.currentContext!.currentPath;

  void _compileFn(BuildContext parent, BuildContext debug) {
    llvm.LLVMDisposeBuilder(builder);
    builder = parent.builder;
    _fn = parent._fn;
    assert(dBuilder == null);

    // 一个函数只能和一个文件绑定，在同一个文件中，可以取巧，使用同一个file scope
    if (parent.currentPath == debug.currentPath) {
      init(parent);
      _fnScope = parent.scope;
    }
    isFnBBContext = true;
  }

  LLVMBasicBlock? _runBbAfter;
  Variable? _compileRetValue;
  Fn? runFn;
  Variable? compileRun(Fn fn, BuildContext context, List<Variable> params) {
    final block = fn.block?.clone();
    if (block == null) {
      Log.e('block == null');
      return null;
    }

    final fnContext = BuildContext._compileRun(fn.currentContext!);

    fnContext._compileFn(context, fn.currentContext!);

    fnContext.runFn = fn;

    for (var p in params) {
      fnContext.pushVariable(p);
    }

    fn.pushTyGenerics(fnContext);

    block.build(fnContext, free: false);

    final retTy = fn.getRetTy(fnContext);
    if (retTy == BuiltInTy.kVoid) {
      fnContext.ret(null);
    } else {
      block.ret(fnContext);
    }
    if (fnContext._runBbAfter != null) {
      fnContext.insertPointBB(fnContext._runBbAfter!);
    }
    return fnContext._compileRetValue;
  }

  RawIdent? _sertOwner;

  /// todo:
  StoreVariable? sretFromVariable(Identifier? nameIdent, Variable variable) {
    return _sretFromVariable(this, nameIdent, variable);
  }

  static StoreVariable? _sretFromVariable(
      BuildContext context, Identifier? nameIdent, Variable variable) {
    final fnContext = context.getLastFnContext()!;
    final fnty = fnContext._fn.ty as Fn;
    StoreVariable? fnSret;
    fnSret = fnContext.sret;
    if (fnSret == null) return null;

    nameIdent ??= variable.ident;
    final owner = nameIdent.toRawIdent;
    if (!fnty.returnVariables.contains(owner)) {
      return null;
    }

    if (fnContext._sertOwner == null &&
        variable is LLVMAllocaDelayVariable &&
        !variable.created) {
      variable.initProxy(context, fnSret);
      fnContext._sertOwner = owner;
      return variable;
    } else {
      fnSret.storeVariable(context, variable);
      return fnSret;
    }
  }

  /// todo:
  void autoAddFreeHeap(Variable variable) {
    if (ImplStackTy.isStackCom(this, variable)) {
      _stackComVariables.add(variable);
    }
  }

  void autoAddStackCom(Variable variable) {
    if (ImplStackTy.isStackCom(this, variable)) {
      _stackComVariables.add(variable);
      var ty = variable.ty;
      if (ty is RefTy) {
        ty = ty.baseTy;
      }
      variable = variable.defaultDeref(this, variable.ident);

      if (ty is StructTy) {
        for (var field in ty.fields) {
          final val = ty.llty.getField(variable, this, field.ident);
          if (val != null) autoAddStackCom(val);
        }
      }
    }
  }

  final _stackComVariables = <Variable>{};

  /// {
  ///   // 当前代码块如果有返回语句，需要释放一些资源
  ///
  /// }
  bool _freeDone = false;
  void freeHeap() {
    if (_freeDone) return;
    _freeDone = true;

    for (var variable in _stackComVariables) {
      ImplStackTy.removeStack(this, variable);
    }
  }

  /// com
  void gg(Ty ty) {
    getImplWithIdent(ty, Identifier.builtIn('Dot'));
  }

  void removeFreeVariable(Variable variable) {
    if (!_stackComVariables.remove(variable)) {
      addStackCom(variable);
    }
  }

  void addStackCom(Variable variable) {
    ImplStackTy.addStack(this, variable);
  }

  /// math
  Variable math(Variable lhs, Variable? rhs, OpKind op, Identifier opId) {
    return OverflowMath.math(this, lhs, rhs, op, opId);
  }

  bool _breaked = false;
  bool _returned = false;

  void ret(Variable? val) {
    if (!canBr) {
      // error
      return;
    }
    _returned = true;

    final fn = getLastFnContext()!;
    if (fn.runFn != null) {
      fn._compileRetValue = val;
      var block = fn._runBbAfter;
      if (this != fn) {
        block = fn.buildSubBB(name: '_new_ret');
        fn._runBbAfter = block;
      }

      if (block != null) _br(block.context);
      return;
    }

    dropAll();

    final retOffset = val?.offset ?? Offset.zero;

    if (val != null) {
      ImplStackTy.addStack(this, val);
    }

    freeHeap();

    diSetCurrentLoc(retOffset);

    /// return void
    if (val == null) {
      llvm.LLVMBuildRetVoid(builder);
      return;
    }

    final sret = fn._sret;

    /// return variable
    if (sret == null) {
      final fnty = fn._fn.ty as Fn;
      final v = AbiFn.fnRet(this, fnty, val);
      // diSetCurrentLoc(retOffset);
      llvm.LLVMBuildRet(builder, v);
      return;
    }

    /// struct ret
    if (val is LLVMAllocaDelayVariable && !val.created) {
      val.initProxy(this, sret);
    } else {
      sret.storeVariable(this, val);
    }

    diSetCurrentLoc(retOffset);
    llvm.LLVMBuildRetVoid(builder);
  }

  void instertFnEntryBB({String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, getLastFnContext()!.fnValue, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
  }

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = _createChildContext();
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());

    llvm.LLVMPositionBuilderAtEnd(child.builder, bb);
    return LLVMBasicBlock(bb, child, false);
  }

  void appendBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(getLastFnContext()!.fnValue, bb.bb);
    bb.inserted = true;
  }

  // 切换到另一个 BasicBlock
  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    appendBB(bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    _breaked = false;
  }

  /// 流程控制，loop/if/match

  final loopBBs = <LLVMBasicBlock>[];

  LLVMBasicBlock getLoopBB(String? label) {
    if (label == null) {
      return _getLast();
    }
    var bb = _getLable(label);
    bb ??= _getLast();

    return bb;
  }

  LLVMBasicBlock _getLast() {
    if (loopBBs.isEmpty) {
      return parent!._getLast();
    }
    return loopBBs.last;
  }

  LLVMBasicBlock? _getLable(String label) {
    var bb = loopBBs.lastWhereOrNull((element) => element.label == label);
    if (bb == null) {
      return parent?._getLable(label);
    }
    return bb;
  }

  void forLoop(Block block, String? label, Expr? expr) {
    final loopBB = buildSubBB(name: 'loop');
    final loopAfter = buildSubBB(name: 'loop_after');
    loopAfter.label = label;
    loopAfter.parent = loopBB;
    loopBBs.add(loopAfter);
    br(loopBB.context);
    insertPointBB(loopBB);

    if (expr != null) {
      final v = expr.build(loopBB.context);
      final variable = v?.variable;
      if (variable != null) {
        final bb = buildSubBB(name: 'loop_body');
        final v = variable.load(loopBB.context);
        loopBB.context.expect(v);
        llvm.LLVMBuildCondBr(loopBB.context.builder, v, bb.bb, loopAfter.bb);
        appendBB(bb);
        block.build(bb.context);
        bb.context.br(this);
      }
    } else {
      block.build(loopBB.context);
      loopBB.context.br(this);
    }
    insertPointBB(loopAfter);
    loopBBs.remove(loopAfter);
  }

  bool get canBr => !_returned && !_breaked;

  void br(BuildContext to) {
    if (!canBr) return;
    _br(to);
  }

  void _br(BuildContext to) {
    _breaked = true;
    llvm.LLVMBuildBr(builder, llvm.LLVMGetInsertBlock(to.builder));
  }

  void setBr() {
    _breaked = true;
  }

  void brLoop() {
    if (!canBr) return;

    _breaked = true;

    llvm.LLVMBuildBr(builder, getLoopBB(null).bb);
  }

  void brContinue() {
    if (!canBr) return;

    _breaked = true;

    llvm.LLVMBuildBr(builder, getLoopBB(null).parent!.bb);
  }

  /// drop
  final _freeVal = <Variable>[];

  @override
  void addFree(Variable val) {
    _freeVal.add(val);
  }

  @override
  void dropAll() {
    for (var val in _freeVal) {
      final ty = val.ty;
      final ident = Identifier.builtIn('drop');
      final impl = getImplForStruct(ty, ident);
      final fn = impl?.getFn(ident)?.copyFrom(ty);
      final fnv = fn?.build();
      if (fn == null || fnv == null) continue;
      LLVMValueRef v;

      // fixme: remove
      if (val.ty is BuiltInTy) {
        v = val.load(this);
      } else {
        v = val.getBaseValue(this);
      }
      final type = fn.llty.createFnType(this);
      llvm.LLVMBuildCall2(
          builder, type, fnv.getBaseValue(this), [v].toNative(), 1, unname);
    }
  }

  void initFnParamsStart(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final sret = AbiFn.initFnParams(this, fn, decl, fnty, extra, map: map);
    _sret = sret;
  }

  void initFnParams(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final params = decl.params;
    var index = 0;

    if (fnty is ImplFn) {
      final p = fnty.ty;
      final selfParam = llvm.LLVMGetParam(fn, index);
      final ident = Identifier.self;

      // 只读引用
      final alloca = LLVMAllocaVariable(selfParam, p, p.typeOf(this), ident);
      setName(alloca.alloca, ident.src);
      alloca.isTemp = false;
      alloca.isRef = true;
      pushVariable(alloca);
      index += 1;
    }

    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      final fnParam = llvm.LLVMGetParam(fn, index);
      var realTy = fnty.getRty(this, p);
      if (realTy is FnTy) {
        final extra = map[p.ident];
        if (extra != null) {
          realTy = realTy.clone(extra);
        }
      }

      resolveParam(realTy, fnParam, p.ident);
      index += 1;
    }

    void fnCatchVariable(AnalysisVariable variable, int index) {
      final value = llvm.LLVMGetParam(fn, index);
      final ident = variable.ident;
      final val = getVariable(ident);

      if (val == null) {
        return;
      }

      final ty = val.ty;
      final type = ty.typeOf(this);
      final alloca = LLVMAllocaVariable(value, ty, type, ident);
      alloca.isTemp = false;

      setName(value, ident.src);
      pushVariable(alloca);
    }

    for (var variable in fnty.variables) {
      index += 1;
      fnCatchVariable(variable, index);
    }

    if (extra != null) {
      for (var variable in extra) {
        index += 1;
        fnCatchVariable(variable, index);
      }
    }
  }

  void resolveParam(Ty ty, LLVMValueRef fnParam, Identifier ident) {
    final alloca = ty.llty.createAlloca(this, ident, fnParam);
    alloca.initProxy(this);
    alloca.isTemp = false;
    pushVariable(alloca);
  }
}
