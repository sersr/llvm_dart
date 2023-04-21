import 'dart:ffi';

import 'package:collection/collection.dart';
import 'package:llvm_dart/ast/analysis_context.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/stmt.dart';
import 'package:llvm_dart/ast/tys.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'build_methods.dart';
import 'intrinsics.dart';
import 'memory.dart';
import 'variables.dart';

class LLVMRawValue {
  LLVMRawValue(this._raw);
  final String _raw;

  String get raw => _raw.replaceAll('_', '');

  Pointer<Char> toChar() {
    return raw.toChar();
  }

  double get value {
    return double.parse(raw);
  }

  int get iValue {
    return int.parse(raw);
  }
}

class LLVMBasicBlock {
  LLVMBasicBlock(this.bb, this.context, this.inserted);
  final LLVMBasicBlockRef bb;
  final BuildContext context;
  String? label;
  LLVMBasicBlock? parent;
  bool inserted = false;
}

class BuildContext
    with BuildMethods, Tys<BuildContext, Variable>, Consts, OverflowMath, Cast {
  BuildContext._(BuildContext this.parent) {
    kModule = parent!.kModule;
    _init();
  }
  BuildContext._clone(BuildContext this.parent) {
    kModule = parent!.kModule;
    module = parent!.module;
    llvmContext = parent!.llvmContext;
    fpm = parent!.fpm;
    builder = parent!.builder;
    fn = parent!.fn;
  }

  BuildContext.root([String name = 'root']) : parent = null {
    kModule = llvm.createKModule(name.toChar());
    _init();
  }

  @override
  final BuildContext? parent;
  final List<BuildContext> children = [];

  void _init() {
    module = llvm.getModule(kModule);
    llvmContext = llvm.getLLVMContext(kModule);
    fpm = llvm.getFPM(kModule);
    builder = llvm.LLVMCreateBuilderInContext(llvmContext);
  }

  late final KModuleRef kModule;
  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMBuilderRef builder;

  late final LLVMPassManagerRef fpm;

  late LLVMConstVariable fn;

  @override
  LLVMValueRef get fnValue => fn.value;

  void dispose() {
    llvm.LLVMDisposeBuilder(builder);
    for (var child in children) {
      child.dispose();
    }
    if (parent == null) {
      llvm.destory(kModule);
    }
  }

  BuildContext? getFnContext(Identifier ident) {
    final list = fns[ident];
    if (list != null) {
      return this;
    }
    return parent?.getFnContext(ident);
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

  LLVMBasicBlock createAndInsertBB(LLVMConstVariable val,
      {String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, val.value, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, true);
  }

  LLVMBasicBlock createBB({String name = 'entry'}) {
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, false);
  }

  void appendBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    bb.inserted = true;
  }

  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    _breaked = false;
    bb.inserted = true;
  }

  StoreVariable? _sret;
  StoreVariable? get sret => _sret;

  void _build(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final params = decl.params;
    var self = 0;

    var retTy = fnty.fnSign.fnDecl.returnTy.getRty(this);
    if (fnty.llvmType.isSret(this) && retTy is StructTy) {
      final first = llvm.LLVMGetParam(fn, self);
      final alloca = LLVMRefAllocaVariable.from(first, retTy, this);
      alloca.isTemp = false;
      self += 1;
      // final rawIdent = fnty.sretVariables.last;
      // final ident = Identifier('', rawIdent.start, rawIdent.end);
      // setName(first, ident.src);
      _sret = alloca;
    }

    if (fnty is ImplFn) {
      final p = fnty.ty;
      final selfParam = llvm.LLVMGetParam(fn, self);
      final ident = Identifier.builtIn('self');
      final alloca = RefTy(p).llvmType.createAlloca(this, ident);
      alloca.store(this, selfParam);
      setName(alloca.alloca, 'self');
      alloca.isTemp = false;
      pushVariable(ident, alloca);
      self += 1;
    }

    for (var i = 0; i < params.length; i++) {
      final p = params[i];

      final fnParam = llvm.LLVMGetParam(fn, i + self);
      var realTy = p.ty.grt(this);
      if (realTy is FnTy) {
        final extra = map[p.ident];
        if (extra != null) {
          realTy = realTy.clone(extra);
        }
      } else {
        realTy = p.ty.kind.resolveTy(realTy);
      }

      resolveParam(realTy, fnParam, p.ident, fnty.extern);
    }

    var index = params.length - 1 + self;

    void fnCatchVariable(AnalysisVariable variable, int index) {
      final value = llvm.LLVMGetParam(fn, index);
      final ident = variable.ident;
      final val = getVariable(ident);

      if (val == null) {
        return;
      }

      final alloca = LLVMRefAllocaVariable.from(value, val.ty, this);
      alloca.isTemp = false;
      setName(alloca.alloca, ident.src);
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

  void resolveParam(
      Ty ty, LLVMValueRef fnParam, Identifier ident, bool extern) {
    StoreVariable alloca;
    if (ty is StructTy) {
      alloca = ty.llvmType.createAllocaFromParam(this, fnParam, ident, extern);
    } else {
      alloca = ty.llvmType.createAlloca(this, ident);
      alloca.store(this, fnParam);
    }

    alloca.isTemp = false;
    pushVariable(ident, alloca);
  }

  LLVMConstVariable buildFnBB(Fn fn,
      [Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>> map = const {}]) {
    final fv = fn.llvmType.createFunction(this, extra);
    final block = fn.block?.clone();
    final isDecl = block == null;

    if (isDecl) return fv;
    final bbContext = createChildContext();
    bbContext.fn = fv;
    bbContext.isFnBBContext = true;
    bbContext.createAndInsertBB(fv);
    bbContext._build(fv.value, fn.fnSign.fnDecl, fn, extra, map: map);
    block.build(bbContext);

    bool hasRet = false;
    bool voidRet({bool back = false}) {
      if (hasRet) return true;
      final decl = fn.fnSign.fnDecl;
      final rty = decl.returnTy.grt(this);
      if (rty is BuiltInTy) {
        final lit = rty.ty;
        if (lit != LitKind.kVoid) {
          if (back) return false;
          // error
        }
        bbContext.ret(null);
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
            final val = expr.build(bbContext)?.variable;
            if (val == null) {
              // error
            }

            bbContext.ret(val);
          }
        }
      }
    }
    voidRet();
    // mem2reg pass
    if (mem2reg) llvm.LLVMRunFunctionPassManager(fpm, fv.value);
    return fv;
  }

  static bool mem2reg = false;

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = createChildContext();
    child.fn = fn;
    return child.createBB(name: name);
  }

  bool _returned = false;
  void ret(Variable? val) {
    if (_returned) {
      // error
      return;
    }
    _returned = true;
    if (val == null) {
      llvm.LLVMBuildRetVoid(builder);
    } else {
      final sret = getLastFnContext()?._sret;
      final (sretV, _) = sretVariable(null, val);

      if (sret == null) {
        final v = val.load(this);
        llvm.LLVMBuildRet(builder, v);
      } else {
        if (sretV == null) {
          final v = val.load(this);
          sret.store(this, v);
        }
        llvm.LLVMBuildRetVoid(builder);
      }
    }
  }

  /// [return]:
  /// true  => alloca != null
  /// false => alloca == null
  /// null  => variable is! LLVMAllocaDelayVariable
  ///
  /// (sret,  variable)
  (Variable?, StoreVariable?) sretVariable(
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
      variable.create(alloca);
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
        llvm.LLVMBuildCondBr(
            loopBB.context.builder, variable.load(this), bb.bb, loopAfter.bb);
        insertPointBB(bb);
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

  LLVMTempVariable? createIfBlock(IfExprBlock ifb) {
    final v = buildIfExprBlock(ifb);
    if (v == null) return null;
    return null;
    // return LLVMTempVariable(v,v.ty);
  }

  LLVMValueRef? buildIfExprBlock(IfExprBlock ifEB) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = buildSubBB(name: 'then');
    final elseBB = buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
    LLVMBasicBlock? afterBB;

    final con = ifEB.expr.build(this)?.variable;
    if (con == null) return null;

    appendBB(then);
    if (onlyIf) {
      afterBB = buildSubBB(name: 'after');
      llvm.LLVMBuildCondBr(builder, con.load(this), then.bb, afterBB.bb);
    } else {
      llvm.LLVMBuildCondBr(builder, con.load(this), then.bb, elseBB.bb);
    }
    ifEB.block.build(then.context);

    if (elseifBlock != null) {
      appendBB(elseBB);
      elseBB.context.buildIfExprBlock(elseifBlock);
    } else if (elseBlock != null) {
      appendBB(elseBB);
      ifEB.elseBlock?.build(elseBB.context);
    }

    if (elseBB.context.canBr || then.context.canBr) {
      afterBB ??= buildSubBB(name: 'after');
      elseBB.context.br(afterBB.context);
      then.context.br(afterBB.context);
      insertPointBB(afterBB);
    } else {
      _returned = true;
    }

    // final ty = llvm.LLVMInt32Type();
    // final tNull = llvm.LLVMConstNull(ty);
    // final phi = llvm.LLVMBuildPhi(builder, ty, unname);
    // final listT = [tNull, tNull].toNative();
    // final bbs = [then.bb, elseBB.bb].toNative();
    // llvm.LLVMAddIncoming(phi, listT.cast(), bbs.cast(), 2);
    return null;
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

  void contine() {
    if (!canBr) return;

    _breaked = true;

    llvm.LLVMBuildBr(builder, getLoopBB(null).parent!.bb);
  }

  void painc() {
    llvm.LLVMBuildUnreachable(builder);
  }

  LLVMValueRef createAlloca(LLVMTypeRef type, {String? name}) {
    return alloctor(type, name ?? '_');
  }

  LLVMValueRef createMalloc(LLVMTypeRef type, {String? name}) {
    final n = name ?? '_';
    return llvm.LLVMBuildMalloc(builder, type, n.toChar());
  }

  LLVMTempOpVariable math(
      Variable lhs,
      Variable? Function(BuildContext context) rhsBuilder,
      OpKind op,
      bool isFloat,
      {bool signed = true}) {
    final l = lhs.load(this);

    if (op == OpKind.And || op == OpKind.Or) {
      final after = buildSubBB(name: 'op_after');
      final opBB = buildSubBB(name: 'op_bb');
      final allocaValue = createAlloca(i1, name: 'op');
      final variable = LLVMAllocaVariable(BuiltInTy.kBool, allocaValue, i1);

      variable.store(this, l);
      appendBB(opBB);

      if (op == OpKind.And) {
        llvm.LLVMBuildCondBr(builder, l, opBB.bb, after.bb);
      } else {
        llvm.LLVMBuildCondBr(builder, l, after.bb, opBB.bb);
      }
      final c = opBB.context;
      final r = rhsBuilder(c)?.load(c);
      if (r == null) {
        // error
      }

      variable.store(c, r!);
      c.br(after.context);
      insertPointBB(after);
      final ac = after.context;
      final con = variable.load(ac);
      return LLVMTempOpVariable(BuiltInTy.kBool, false, false, con);
    }
    final r = rhsBuilder(this)?.load(this);
    if (r == null) {
      // error
      return LLVMTempOpVariable(lhs.ty, isFloat, signed, l);
    }
    LLVMValueRef Function(LLVMBuilderRef b, LLVMValueRef l, LLVMValueRef r,
        Pointer<Char> name)? llfn;

    if (isFloat) {
      final id = op.getFCmpId(signed);
      if (id != null) {
        final v = llvm.LLVMBuildFCmp(builder, id, l, r, unname);
        return LLVMTempOpVariable(BuiltInTy.kBool, isFloat, signed, v);
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
        return LLVMTempOpVariable(lhs.ty, isFloat, signed, value);
      }
    }

    final cmpId = op.getICmpId(signed);
    if (cmpId != null) {
      final v = llvm.LLVMBuildICmp(builder, cmpId, l, r, unname);
      return LLVMTempOpVariable(BuiltInTy.kBool, isFloat, signed, v);
    }

    LLVMValueRef? value;

    LLVMIntrisics? k;
    final ty = lhs.ty;
    switch (op) {
      case OpKind.Add:
        k = LLVMIntrisics.getAdd(ty, signed);
        break;
      case OpKind.Sub:
        if (!signed) {
          value = llvm.LLVMBuildSub(builder, l, r, unname);
        } else {
          k = LLVMIntrisics.getSub(ty, signed);
        }
        break;
      case OpKind.Mul:
        k = LLVMIntrisics.getMul(ty, signed);
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
      llvm.LLVMBuildCondBr(builder, mathValue.condition, after.bb, panicBB.bb);
      panicBB.context.painc();
      insertPointBB(after);
      return LLVMTempOpVariable(ty, isFloat, signed, mathValue.value);
    }
    if (llfn != null) {
      value = llfn(builder, l, r, unname);
    }

    return LLVMTempOpVariable(ty, isFloat, signed, value ?? l);
  }
}
