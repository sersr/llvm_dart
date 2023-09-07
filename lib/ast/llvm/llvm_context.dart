import 'dart:ffi';

import 'package:collection/collection.dart';

import '../../abi/abi_fn.dart';
import '../../fs/fs.dart';
import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../expr.dart';
import '../memory.dart';
import '../stmt.dart';
import '../tys.dart';
import 'build_methods.dart';
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

class RootBuildContext with Tys<Variable> {
  @override
  Tys<LifeCycleVariable> defaultImport() {
    throw UnimplementedError();
  }
}

class BuildContext
    with
        LLVMTypeMixin,
        BuildMethods,
        Tys<Variable>,
        Consts,
        OverflowMath,
        Cast {
  BuildContext._(BuildContext this.parent) : isRoot = false {
    kModule = parent!.kModule;
    _dBuilder = parent!._dBuilder;
    _init();
  }
  BuildContext._clone(BuildContext this.parent) : isRoot = false {
    kModule = parent!.kModule;
    module = parent!.module;
    llvmContext = parent!.llvmContext;
    builder = parent!.builder;
    fn = parent!.fn;
    _unit = parent!._unit;
    _dBuilder = parent!._dBuilder;
  }

  BuildContext._importRoot(BuildContext p)
      : parent = null,
        isRoot = false {
    kModule = p.kModule;
    module = p.module;
    llvmContext = p.llvmContext;
    builder = llvm.LLVMCreateBuilderInContext(llvmContext);
    p.children.add(this);
  }

  @override
  String? get currentPath => super.currentPath ?? parent?.currentPath;

  @override
  GlobalContext get importHandler =>
      parent?.importHandler ?? super.importHandler;
  void log(int level) {
    print('${' ' * level}$currentPath');
    level += 2;
    for (var child in children) {
      child.log(level);
    }
  }

  BuildContext.root([String name = 'root'])
      : parent = null,
        isRoot = true {
    kModule = llvm.createKModule(name.toChar());
    _init();
    _debugInit();
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

  /// ----

  LLVMMetadataRef? _unit;
  @override
  LLVMMetadataRef get unit => _unit ??= parent!.unit;
  LLVMDIBuilderRef? _dBuilder;

  @override
  LLVMDIBuilderRef? get dBuilder => _dBuilder;

  void init([bool isDebug = true]) {
    if (!isDebug) return;
    final info = "Debug Info Version";
    final version = "Dwarf Version";
    final picLevel = "PIC Level";
    final uwtable = 'uwtable';
    final framePointer = 'frame-pointer';

    final infoV = constI32(3);
    final versionV = constI32(4);
    final picLevelV = constI32(2);
    final uwtableV = constI32(1);
    final framePointerV = constI32(1);

    void add(int lv, String name, LLVMValueRef value) {
      llvm.LLVMAddModuleFlag(module, lv, name.toChar(), name.nativeLength,
          llvm.LLVMValueAsMetadata(value));
    }

    add(1, info, infoV);
    add(6, version, versionV);
    add(7, picLevel, picLevelV);
    add(6, uwtable, uwtableV);
    add(6, framePointer, framePointerV);

    _debugInit();
  }

  @override
  void initImportContext(BuildContext child) {
    if (dBuilder == null) return;
    child._debugInit();
  }

  bool _finalized = true;
  void _debugInit() {
    if (this.currentPath == null || !_finalized) return;
    _finalized = false;
    _dBuilder = llvm.LLVMCreateDIBuilder(module);
    final currentPath = this.currentPath!;
    final path = currentDir.childFile(currentPath);
    final dir = path.parent.path;

    _unit = llvm.LLVMCreateCompileUnit(
        _dBuilder!, path.basename.toChar(), dir.toChar());
  }

  void finalize() {
    if (!_finalized && _dBuilder != null) {
      llvm.LLVMDIBuilderFinalize(_dBuilder!);
    }
    for (var child in children) {
      child.finalize();
    }
  }

  @override
  final BuildContext? parent;
  final List<BuildContext> children = [];

  void _init() {
    module = llvm.getModule(kModule);
    llvmContext = llvm.getLLVMContext(kModule);
    builder = llvm.LLVMCreateBuilderInContext(llvmContext);
  }

  late final KModuleRef kModule;
  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMBuilderRef builder;

  late LLVMConstVariable fn;

  @override
  LLVMValueRef get fnValue => fn.value;

  final bool isRoot;
  void dispose() {
    llvm.LLVMDisposeBuilder(builder);
    for (var child in children) {
      child.dispose();
    }
    if (isRoot) {
      llvm.destory(kModule);
    }
  }

  @override
  BuildContext? getLastFnContext() => super.getLastFnContext() as BuildContext?;

  BuildContext createChildContext() {
    final child = BuildContext._(this);
    children.add(child);
    return child;
  }

  BuildContext clone() {
    return BuildContext._clone(this);
  }

  @override
  BuildContext defaultImport() {
    return BuildContext._importRoot(this);
  }

  void instertFnEntryBB({String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, fn.value, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
  }

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = createChildContext();
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());
    child.fn = fn;

    llvm.LLVMPositionBuilderAtEnd(child.builder, bb);
    return LLVMBasicBlock(bb, child, false);
  }

  void appendBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    bb.inserted = true;
  }

  // 切换到另一个 BasicBlock
  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    appendBB(bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    _breaked = false;
  }

  StoreVariable? _sret;
  StoreVariable? get sret => _sret;

  void initFnParamsStart(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final sret = AbiFn.initFnParams(this, fn, decl, fnty, extra, map: map);
    _sret = sret;
  }

  void initFnParams(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    // ignore: invalid_use_of_protected_member
    final params = decl.params;
    var index = 0;

    // var retTy = fnty.getRetTy(this);

    // if (fnty.llvmType.isSret(this) && retTy is StructTy) {
    //   final first = llvm.LLVMGetParam(fn, index);
    //   final alloca = retTy.llvmType.createAlloca(this, Identifier.none, first);
    //   alloca.isTemp = false;
    //   index += 1;
    //   // final rawIdent = fnty.sretVariables.last;
    //   // final ident = Identifier('', rawIdent.start, rawIdent.end);
    //   // setName(first, ident.src);
    //   _sret = alloca;
    // }

    if (fnty is ImplFn) {
      final p = fnty.ty;
      final selfParam = llvm.LLVMGetParam(fn, index);
      final ident = Identifier.builtIn('self');
      // final alloca = RefTy(p).llvmType.createAlloca(this, ident);
      // alloca.store(this, selfParam);

      // 只读引用
      final alloca =
          LLVMAllocaVariable(p, selfParam, p.llvmType.createType(this));
      setName(alloca.alloca, 'self');
      alloca.isTemp = false;
      alloca.isRef = true;
      pushVariable(ident, alloca);
      index += 1;
    }

    for (var i = 0; i < params.length; i++) {
      final p = params[i];

      final fnParam = llvm.LLVMGetParam(fn, i + index);
      var realTy = fnty.getRty(this, p);
      if (realTy is FnTy) {
        final extra = map[p.ident];
        if (extra != null) {
          realTy = realTy.clone(extra);
        }
      }

      resolveParam(realTy, fnParam, p.ident);
    }

    index += params.length - 1;

    void fnCatchVariable(AnalysisVariable variable, int index) {
      final value = llvm.LLVMGetParam(fn, index);
      final ident = variable.ident;
      final val = getVariable(ident);

      if (val == null) {
        return;
      }

      final ty = val.ty;
      // final alloca = LLVMRefAllocaVariable.from(value, ty, this);
      final type = ty.llvmType.createType(this);
      final alloca = LLVMAllocaVariable(ty, value, type);
      alloca.isTemp = false;

      setName(value, ident.src);
      pushVariable(ident, alloca);
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
    Variable alloca;
    if (ty is StructTy) {
      alloca = ty.llvmType.createAllocaFromParam(this, fnParam, ident);
      // } else if (ty is Fn) {
      //   alloca = ty.llvmType.createAllocaParam(this, ident, fnParam);
      // } else if (ty is! RefTy) {
      //   alloca = LLVMConstVariable(fnParam, ty);
      //   setName(fnParam, ident.src);
    } else {
      final a = alloca = ty.llvmType.createAlloca(this, ident, fnParam);
      // final a = alloca = ty.llvmType.createAlloca(this, ident);
      a.create(this);
      setName(a.alloca, ident.src);
      a.isTemp = false;
    }
    if (alloca is StoreVariable) alloca.isTemp = false;
    pushVariable(ident, alloca);
  }

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
      if (val.ty is BuiltInTy) {
        v = val.load(this, Offset.zero);
      } else {
        v = val.getBaseValue(this);
      }
      final type = fn.llvmType.createFnType(this);
      llvm.LLVMBuildCall2(
          builder, type, fnv.getBaseValue(this), [v].toNative(), 1, unname);
    }
  }

  LLVMMetadataRef? _fnScope;

  @override
  LLVMMetadataRef get scope => _fnScope ?? parent?.scope ?? unit;

  LLVMConstVariable buildFnBB(Fn fn,
      [Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>> map = const {},
      void Function(BuildContext context)? onCreated]) {
    final fv = AbiFn.createFunction(this, fn, extra, (fv) {
      final block = fn.block?.clone();
      if (block == null) return;

      final fnContext = createChildContext();
      fnContext.fn = fv;
      fnContext._fnScope = llvm.LLVMGetSubprogram(fv.value);
      fnContext.isFnBBContext = true;
      fnContext.instertFnEntryBB();
      onCreated?.call(fnContext);
      fnContext.initFnParamsStart(fv.value, fn.fnSign.fnDecl, fn, extra,
          map: map);
      block.build(fnContext);

      bool hasRet = false;
      bool voidRet({bool back = false}) {
        if (hasRet) return true;
        final rty = fn.getRetTy(this);
        if (rty is BuiltInTy) {
          final lit = rty.ty;
          if (lit != LitKind.kVoid) {
            if (back) return false;
            // error
          }
          fnContext.ret(null, null);
          hasRet = true;
          return true;
        }
        return false;
      }

      if (block.stmts.isNotEmpty) {
        final lastStmt = block.stmts.last;
        if (lastStmt is ExprStmt) {
          final expr = lastStmt.expr;
          if (expr is! RetExpr) {
            if (!voidRet(back: true)) {
              // 获取缓存的value
              final valTemp = expr.build(fnContext);
              final val = valTemp?.variable;
              if (val == null) {
                // error
              }

              fnContext.ret(val, valTemp?.currentIdent);
            }
          }
        }
      }
      voidRet();
    });
    return fv;
  }

  bool _returned = false;
  void ret(Variable? val, Identifier? ident, [Offset retOffset = Offset.zero]) {
    if (_returned) {
      // error
      return;
    }
    dropAll();
    ident ??= Identifier.none;

    diSetCurrentLoc(ident.offset);

    _returned = true;
    if (val == null) {
      diSetCurrentLoc(retOffset);
      llvm.LLVMBuildRetVoid(builder);
    } else {
      final fn = getLastFnContext();
      final sret = fn?._sret;

      if (sret == null) {
        final v = AbiFn.fnRet(this, fn!.fn.ty as Fn, val, ident.offset);
        diSetCurrentLoc(retOffset);
        llvm.LLVMBuildRet(builder, v);
      } else {
        sretFromVariable(null, val);
        diSetCurrentLoc(retOffset);
        llvm.LLVMBuildRetVoid(builder);
      }
    }
  }

  /// [return]:
  /// (sret,  variable)
  (Variable?, StoreVariable?) sretFromVariable(
      Identifier? nameIdent, Variable? variable) {
    final fnContext = getLastFnContext();
    final fnty = fnContext?.fn.ty as Fn?;
    StoreVariable? alloca;

    if (fnty != null) {
      nameIdent ??= variable?.ident;
      if (nameIdent == null ||
          fnty.sretVariables.contains(nameIdent.toRawIdent)) {
        alloca = fnContext?.sret;
      }
    }

    if (variable is LLVMAllocaDelayVariable) {
      variable.create(this, alloca, nameIdent);
      if (alloca != null) {
        if (nameIdent != null) setName(alloca.alloca, nameIdent.src);
      }

      return (alloca, variable);
    }

    return (alloca, null);
  }

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
        llvm.LLVMBuildCondBr(loopBB.context.builder,
            variable.load(this, Offset.zero), bb.bb, loopAfter.bb);
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

  bool _breaked = false;

  bool get canBr => !_returned && !_breaked;

  void br(BuildContext to) {
    if (!canBr) return;
    _breaked = true;
    llvm.LLVMBuildBr(builder, llvm.LLVMGetInsertBlock(to.builder));
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

  void painc() {
    llvm.LLVMBuildUnreachable(builder);
  }

  Variable math(Variable lhs,
      ExprTempValue? Function(BuildContext context) rhsBuilder, OpKind op,
      {Offset lhsOffset = Offset.zero, Offset opOffset = Offset.zero}) {
    // final lty = lhs.ty;
    // // 提供外部操作符实现接口
    // if (lty is! BuiltInTy) {
    //   if (op == OpKind.Eq || op == OpKind.Ne) {
    //     if (lhs.ty is CTypeTy) {
    //       final l = lhs.load(this, lhsOffset);
    //       final rvTemp = rhsBuilder(this);
    //       final rv = rvTemp?.variable;
    //       final r = rv?.load(this, rvTemp!.currentIdent.offset);
    //       final id = op.getICmpId(false);

    //       if (r != null && id != null) {
    //         diSetCurrentLoc(opOffset);
    //         final v = llvm.LLVMBuildICmp(builder, id, l, r, unname);
    //         return LLVMTempOpVariable(BuiltInTy.kBool, isFloat, signed, v);
    //       }
    //     }
    //   }
    // }

    var isFloat = false;
    var signed = false;
    final ty = lhs.ty;

    if (ty is BuiltInTy && ty.ty.isNum) {
      final kind = ty.ty;
      if (kind.isFp) {
        isFloat = true;
      } else if (kind.isInt) {
        signed = kind.signed;
      }
    }

    final l = lhs.load(this, lhsOffset);

    if (op == OpKind.And || op == OpKind.Or) {
      final after = buildSubBB(name: 'op_after');
      final opBB = buildSubBB(name: 'op_bb');
      final allocaValue = alloctor(i1, name: 'op');
      final variable = LLVMAllocaVariable(BuiltInTy.kBool, allocaValue, i1);

      variable.store(this, l, Offset.zero);
      appendBB(opBB);

      if (op == OpKind.And) {
        llvm.LLVMBuildCondBr(builder, l, opBB.bb, after.bb);
      } else {
        llvm.LLVMBuildCondBr(builder, l, after.bb, opBB.bb);
      }
      final c = opBB.context;
      final temp = rhsBuilder(c);
      final r = temp?.variable?.load(c, temp.currentIdent.offset);
      if (r == null) {
        // error
      }

      variable.store(c, r!, Offset.zero);
      c.br(after.context);
      insertPointBB(after);
      return variable;
    }

    final temp = rhsBuilder(this);
    final r = temp?.variable?.load(this, temp.currentIdent.offset);
    if (r == null) {
      LLVMValueRef? value;

      if (op == OpKind.Eq) {
        value = llvm.LLVMBuildIsNull(builder, l, unname);
      } else {
        assert(op == OpKind.Ne);
        value = llvm.LLVMBuildIsNotNull(builder, l, unname);
      }
      return LLVMConstVariable(value, BuiltInTy.kBool);
    }

    LLVMValueRef Function(LLVMBuilderRef b, LLVMValueRef l, LLVMValueRef r,
        Pointer<Char> name)? llfn;

    diSetCurrentLoc(opOffset);

    if (isFloat) {
      final id = op.getFCmpId(signed);
      if (id != null) {
        final v = llvm.LLVMBuildFCmp(builder, id, l, r, unname);
        return LLVMConstVariable(v, BuiltInTy.kBool);
      }
      LLVMValueRef? value;
      switch (op) {
        case OpKind.Add:
          value = llvm.LLVMBuildFAdd(builder, l, r, unname);
          break;
        case OpKind.Sub:
          value = llvm.LLVMBuildFSub(builder, l, r, unname);
          break;
        case OpKind.Mul:
          value = llvm.LLVMBuildFMul(builder, l, r, unname);
          break;
        case OpKind.Div:
          value = llvm.LLVMBuildFDiv(builder, l, r, unname);
          break;
        case OpKind.Rem:
          value = llvm.LLVMBuildFRem(builder, l, r, unname);
          break;
        case OpKind.BitAnd:
          value = llvm.LLVMBuildAnd(builder, l, r, unname);
          break;
        case OpKind.BitOr:
          value = llvm.LLVMBuildOr(builder, l, r, unname);
          break;
        case OpKind.BitXor:
          value = llvm.LLVMBuildXor(builder, l, r, unname);
          break;
        default:
      }
      if (value != null) {
        return LLVMConstVariable(value, ty);
      }
    }

    final cmpId = op.getICmpId(signed);
    if (cmpId != null) {
      final v = llvm.LLVMBuildICmp(builder, cmpId, l, r, unname);
      return LLVMConstVariable(v, BuiltInTy.kBool);
    }

    LLVMValueRef? value;

    LLVMIntrisics? k;
    switch (op) {
      case OpKind.Add:
        k = LLVMIntrisics.getAdd(ty, signed, this);
        break;
      case OpKind.Sub:
        if (!signed) {
          value = llvm.LLVMBuildSub(builder, l, r, unname);
        } else {
          k = LLVMIntrisics.getSub(ty, signed, this);
        }
        break;
      case OpKind.Mul:
        k = LLVMIntrisics.getMul(ty, signed, this);
        break;
      case OpKind.Div:
        llfn = signed ? llvm.LLVMBuildSDiv : llvm.LLVMBuildUDiv;
        break;
      case OpKind.Rem:
        llfn = signed ? llvm.LLVMBuildSRem : llvm.LLVMBuildURem;
        break;
      case OpKind.BitAnd:
        llfn = llvm.LLVMBuildAnd;
        break;
      case OpKind.BitOr:
        llfn = llvm.LLVMBuildOr;
        break;
      case OpKind.BitXor:
        llfn = llvm.LLVMBuildXor;
        break;
      case OpKind.Shl:
        llfn = llvm.LLVMBuildShl;
        break;
      case OpKind.Shr:
        llfn = signed ? llvm.LLVMBuildAShr : llvm.LLVMBuildLShr;
        break;
      default:
    }

    assert(k == null || llfn == null);

    if (k != null) {
      final mathValue = oMath(l, r, k);
      final after = buildSubBB(name: 'math');
      final panicBB = buildSubBB(name: 'panic');
      appendBB(panicBB);
      llvm.LLVMBuildCondBr(builder, mathValue.condition, panicBB.bb, after.bb);
      panicBB.context.diSetCurrentLoc(opOffset);
      panicBB.context.painc();
      insertPointBB(after);

      return LLVMConstVariable(mathValue.value, ty);
    }
    if (llfn != null) {
      value = llfn(builder, l, r, unname);
    }

    return LLVMConstVariable(value ?? l, ty);
  }
}
