import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../memory.dart';
import '../tys.dart';
import 'build_context_mixin.dart';
import 'build_methods.dart';
import 'intrinsics.dart';
import 'variables.dart';

export 'build_context_mixin.dart';

final class Configs {
  Configs({
    required this.isGnu,
    required this.isMsvc,
    required this.abi,
    required this.targetTriple,
    required this.isDebug,
  });

  final bool isGnu;
  final bool isMsvc;
  final Abi abi;
  final String targetTriple;
  final bool isDebug;
  bool get isWin => abi.isWindows;

  @override
  String toString() {
    return '''target: $targetTriple
abi: $abi, isWin: ${abi.isWindows}
isMsvc: $isMsvc
isGnu: $isGnu
isDebug: $isDebug''';
  }
}

class RootBuildContext with Tys<Variable>, LLVMTypeMixin, Consts {
  RootBuildContext({
    this.name = 'root',
    required this.configs,
  });

  bool _initContext = false;
  void init() {
    assert(!_initContext);
    _initContext = true;
    llvmContext = llvm.LLVMContextCreate();
    module = llvm.LLVMModuleCreateWithNameInContext(name.toChar(), llvmContext);
    tm = llvm.createTarget(module, configs.targetTriple.toChar());

    void add(int lv, String name, int size) {
      llvm.LLVMAddFlag(module, lv, name.toChar(), size);
    }

    if (configs.isWin && configs.isMsvc) {
      add(2, "CodeView", 1);
      // add(8, "PIC Level", 2);
      // add(8, "PIE Level", 2);
    } else {
      add(8, "Dwarf Version", 2);
    }

    add(2, "Debug Info Version", 3);
  }

  final Configs configs;

  @override
  late final GlobalContext global;

  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMTargetMachineRef tm;

  final String name;

  Abi get abi => configs.abi;
  bool get isDebug => configs.isDebug;

  final maps = <String, FunctionDeclare>{};

  final _globalStrings = <String, LLVMValueRef>{};
  LLVMValueRef globalStringPut(String key, LLVMValueRef Function() data) {
    return _globalStrings.putIfAbsent(key, data);
  }

  void dispose() {
    llvm.LLVMDisposeModule(module);
    llvm.LLVMDisposeTargetMachine(tm);
    llvm.LLVMContextDispose(llvmContext);
    llvmMalloc.releaseAll();
  }

  @override
  String get currentPath => throw UnimplementedError();

  final _structTypes = <ListKey, LLVMTypeRef>{};

  @override
  LLVMTypeRef typeStruct(List<LLVMTypeRef> types, String? ident,
      {List<Ty> tys = const []}) {
    if (ident == null) {
      return llvm.LLVMStructTypeInContext(
          llvmContext, types.toNative(), types.length, LLVMFalse);
    }

    final key = ListKey([types, ident]);

    return _structTypes.putIfAbsent(key, () {
      final struct =
          llvm.LLVMStructCreateNamed(llvmContext, 'struct_$ident'.toChar());
      llvm.LLVMStructSetBody(struct, types.toNative(), types.length, LLVMFalse);
      return struct;
    });
  }

  final _closureBase = <LLVMValueRef, Variable>{};

  Variable createClosureBase(
      FnBuildMixin context, FnCatch fnCatch, FnClosure ty, Variable fn) {
    final fnValue = fn.getBaseValue(context);

    return _closureBase.putIfAbsent(fnValue, () {
      final index = _closureBase.length;
      final closureName = 'dyn_closure_$index'.ident;
      final bodyName = 'dyn_body____$index'.ident;
      return LLVMAllocaProxyVariable(context, (variable, isProxy) {
        final variables = fnCatch.getVariables();
        final closureType = ty.llty.closureTypeOf(context, variables);
        final alloca = context.alloctor(closureType, ty: ty, name: bodyName);

        final ref = RefTy(LiteralKind.kVoid.ty);

        /// store body.fn
        final fnAddr = llvm.LLVMBuildStructGEP2(
            context.builder, closureType, alloca, 0, unname);
        final fnField = LLVMAllocaVariable(
            fnAddr, ref, ref.typeOf(context), Identifier.none);
        fnField.store(context, fnValue);

        /// 保存所有捕获变量
        for (var i = 0; i < variables.length; i++) {
          final value = llvm.LLVMBuildStructGEP2(
              context.builder, closureType, alloca, i + 1, unname);
          final field = LLVMAllocaVariable(
              value, ref, ref.typeOf(context), Identifier.none);

          final val = variables[i];
          field.store(context, val.getBaseValue(context));
        }

        /// 新建一个函数实例，通用函数，闭包函数由此函数转发
        final closureFn = createClosure(ty, fnCatch, context);

        /// dyn: { ptr: first, ptr: sec }
        final closureAlloca =
            variable ?? ty.llty.createAlloca(context, closureName);
        final type = closureAlloca.type;
        final addr = closureAlloca.alloca;

        /// 第一个是转发函数地址
        final first = llvm.LLVMBuildStructGEP2(
            context.builder, type, addr, 0, '_first'.toChar());

        final firstVal = LLVMAllocaVariable(
            first, ref, ref.typeOf(context), Identifier.none);
        firstVal.store(context, closureFn.load(context));

        /// 闭包函数本体，包括函数地址，捕获变量
        final second = llvm.LLVMBuildStructGEP2(
            context.builder, type, addr, 1, '_second'.toChar());

        final secVal = LLVMAllocaVariable(
            second, ref, ref.typeOf(context), Identifier.none);
        secVal.store(context, alloca);
      }, ty, ty.typeOf(context), closureName);
    });
  }

  final _globalClosures = <ListKey, Variable>{};
  Variable createClosure(FnClosure fn, FnCatch fnCatch, FnBuildMixin context) {
    final fnType = fn.llty.createFnType(context);
    final closureType = fnCatch.llty.createFnType(context);

    final key = ListKey([fnType, closureType]);
    final value = _globalClosures[key];
    if (value != null) return value;

    final ident = '_closure_ ${fn.ident.path}';
    final v = llvm.LLVMAddFunction(module, ident.toChar(), fnType);
    llvm.LLVMSetLinkage(v, LLVMLinkage.LLVMInternalLinkage);
    llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);

    context.setFnLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
    context.setFnLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
    context.setFnLLVMAttr(v, -1, LLVMAttr.NoInline); // Function

    final newFnValue = LLVMConstVariable(v, fn, fn.ident);
    _globalClosures[key] = newFnValue;

    final closureContext = context.createChildContext();
    final bb =
        llvm.LLVMAppendBasicBlockInContext(llvmContext, v, 'entry'.toChar());
    llvm.LLVMPositionBuilderAtEnd(closureContext.builder, bb);

    final first = llvm.LLVMGetParam(v, 0);
    var index = 1;

    final args = <LLVMValueRef>[];
    for (var f in fn.fields) {
      final field = llvm.LLVMGetParam(v, index);
      args.add(field);
      setName(field, f.ident.src);
      index += 1;
    }

    final addr = fn.llty.load(closureContext, first, fnCatch, args);
    final retType = fn.getRetTy(context);
    final isSret = retType.llty.getBytes(context) > 8;

    final ret = llvm.LLVMBuildCall2(closureContext.builder, closureType, addr,
        args.toNative(), args.length, unname);

    if (!isSret && !retType.isTy(LiteralKind.kVoid.ty)) {
      llvm.LLVMBuildRet(closureContext.builder, ret);
    } else {
      llvm.LLVMBuildRetVoid(closureContext.builder);
    }
    return newFnValue;
  }

  final _fnTypes = <ListKey, LLVMTypeRef>{};

  @override
  LLVMTypeRef typeFn(List<LLVMTypeRef> params, LLVMTypeRef ret, bool isVar) {
    final key = ListKey([params, ret, isVar]);
    return _fnTypes.putIfAbsent(
        key,
        () => llvm.LLVMFunctionType(
            ret, params.toNative(), params.length, isVar.llvmBool));
  }

  late final typeList = [i8, i16, i32, i64, i128];

  MathValue oMath(LLVMValueRef lhs, LLVMValueRef rhs, LLVMIntrisics fn,
      BuildMethods context) {
    final ty = typeList[fn.index % 5];
    final structTy = typeStruct([ty, i1], null);
    final inFn = maps.putIfAbsent(fn.name, () {
      return FunctionDeclare([ty, ty], fn.name, structTy);
    });
    final f = inFn.build(context);

    final result = llvm.LLVMBuildCall2(
        context.builder, inFn.type, f, [lhs, rhs].toNative(), 2, unname);
    final l1 = llvm.LLVMBuildExtractValue(
        context.builder, result, 0, '_result_0'.toChar());
    final l2 = llvm.LLVMBuildExtractValue(
        context.builder, result, 1, '_result_1'.toChar());
    return MathValue(l1, l2);
  }
}

class BuildContextImpl extends BuildContext
    with FreeMixin, FlowMixin, FnContextMixin, SretMixin, FnBuildMixin
    implements LogPretty {
  BuildContextImpl._baseChild(BuildContextImpl this.parent, this.currentPath)
      : root = parent.root {
    init(parent!);
  }

  BuildContextImpl._compileRun(BuildContextImpl this.parent, this.currentPath)
      : root = parent.root;

  BuildContextImpl.root(this.root, this.currentPath) : parent = null;

  @override
  final BuildContextImpl? parent;
  @override
  final RootBuildContext root;

  @override
  Abi get abi => root.abi;

  @override
  final String currentPath;

  @override
  GlobalContext get global => root.global;

  LLVMBuilderRef? _builder;
  @override
  LLVMBuilderRef get builder =>
      _builder ??= llvm.LLVMCreateBuilderInContext(llvmContext);

  @override
  void copyBuilderFrom(BuildContext other) {
    if (_builder != null) {
      llvm.LLVMDisposeBuilder(_builder!);
    }
    _ignoreDisposeBuilder = true;
    _builder = other.builder;
  }

  bool _ignoreDisposeBuilder = false;

  final List<BuildContextImpl> _children = [];

  @override
  BuildContextImpl createChildContext() {
    final child = BuildContextImpl._baseChild(this, currentPath);
    _children.add(child);
    return child;
  }

  @override
  BuildContextImpl createNewRunContext() {
    return BuildContextImpl._compileRun(this, currentPath);
  }

  @override
  BuildContextImpl? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  void log(int level) {
    print('${' ' * level}$currentPath');
    level += 2;
    for (var child in _children) {
      child.log(level);
    }
  }

  @override
  VA? getKVImpl<VA>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    return super.getKVImpl(map, test: test) ??
        parent?.getKVImpl(map, test: test);
  }

  @override
  void dispose() {
    if (!_ignoreDisposeBuilder) llvm.LLVMDisposeBuilder(builder);
    super.dispose();

    for (var child in _children) {
      child.dispose();
    }
  }

  @override
  void freeHeapParent(FnBuildMixin to, {FnBuildMixin? from}) {
    final fn = from ?? getLastFnContext();
    assert(fn != null, "error: fn == null.");
    if (fn == null || fn == this) return;

    var current = parent;

    while (current != null) {
      current.freeHeapCurrent(to);
      if (current == fn) return;
      current = current.parent;
    }
  }

  bool get _isEmpty =>
      currentStmts.isEmpty && _children.every((element) => element._isEmpty);

  @override
  String toString() {
    return logPretty(0, ignorePath: false).$1.logPretty();
  }

  @override
  (Map, int) logPretty(int level, {bool ignorePath = true}) {
    final children = _children.where((element) => !element._isEmpty).toList();
    if (children.isEmpty && currentStmts.isEmpty) return ({}, level);

    final map = {
      if (currentFn == null && !ignorePath) "path": block?.blockStart.basePath,
      if (currentFn != null) "fn": currentFn?.fnName.path,
      if (currentStmts.isNotEmpty) "stmts": currentStmts,
      if (children.isNotEmpty) "children": children,
    };
    return (map, level);
  }
}
