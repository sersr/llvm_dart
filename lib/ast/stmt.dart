import 'dart:ffi';

import 'package:nop/nop.dart';

import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'expr.dart';
import 'llvm/build_context_mixin.dart';
import 'llvm/coms.dart';
import 'llvm/variables.dart';
import 'memory.dart';

class LetStmt extends Stmt {
  LetStmt(this.isFinal, this.ident, this.nameIdent, this.rExpr, this.ty);
  final Identifier ident;
  final Identifier nameIdent;
  final Expr? rExpr;
  final PathTy? ty;
  final bool isFinal;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    rExpr?.incLevel(count);
  }

  @override
  Stmt clone() {
    return LetStmt(isFinal, ident, nameIdent, rExpr?.clone(), ty);
  }

  @override
  String toString() {
    final tyy = ty == null ? '' : ' : $ty';
    final rE = rExpr == null ? '' : ' = $rExpr';

    return '${pad}let $nameIdent$tyy$rE';
  }

  @override
  void build(FnBuildMixin context, bool isRet) {
    final realTy = ty?.grt(context);
    Ty? baseTy = realTy;

    if (isRet) {
      baseTy = context.getLastFnContext()!.currentFn!.getRetTy(context);
      if (baseTy.isTy(LiteralKind.kVoid.ty)) {
        baseTy = null;
      }
    }
    final val = switch (rExpr) {
      RetExprMixin expr => expr.build(context, baseTy: baseTy, isRet: false),
      var expr => expr?.build(context, baseTy: realTy),
    };

    final tty = val?.ty;
    final variable = val?.variable;
    if (tty == null || variable == null) return;

    if (isRet) {
      if (rExpr is RetExprMixin) {
        context.setName(variable.getBaseValue(context), nameIdent.src);
      }

      context.ret(variable, isLastStmt: true);

      return;
    }

    /// 先判断是否是 struct ret
    var letVariable = context.sretFromVariable(nameIdent, variable) ?? variable;

    if (letVariable is LLVMLitVariable) {
      assert(tty is BuiltInTy);

      if (isFinal && !context.root.isDebug) {
        context.pushVariable(letVariable.newIdent(nameIdent));
        return;
      }

      final alloca = letVariable.createAlloca(context, nameIdent, tty);
      assert(alloca.ident == nameIdent);

      context.pushVariable(alloca);
      return;
    }

    if (isFinal && !context.root.isDebug) {
      context.pushVariable(letVariable.newIdent(nameIdent));
      return;
    }

    final newVal = letVariable.ty.llty.createAlloca(context, nameIdent);

    newVal.storeVariable(context, variable, isNew: true);

    context.pushVariable(newVal);
  }

  @override
  List<Object?> get props => [ident, nameIdent, ty, rExpr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final v = rExpr?.analysis(context);

    if (v == null) return;
    final value = v.copy(ty: realTy, ident: nameIdent);
    context.pushVariable(value);
  }
}

class LetSwapStmt extends Stmt {
  LetSwapStmt(this.leftExprs, this.rightExprs);
  final List<Expr> leftExprs;
  final List<Expr> rightExprs;

  @override
  void analysis(AnalysisContext context) {
    final rightVals = rightExprs.map((e) => e.analysis(context)).toList();
    final leftVals = leftExprs.map((e) => e.analysis(context)).toList();
    var length = leftVals.length;
    if (length != rightVals.length) {
      Log.e('mismatch in the number of variables');
      return;
    }

    for (var i = 0; i < length; i++) {
      final lhs = leftVals[i];
      final rhs = rightVals[i];
      if (lhs == null || rhs == null) {
        Log.e('let error.');
        return;
      }
      context.pushVariable(lhs.copy(ident: rhs.ident));
      context.pushVariable(rhs.copy(ident: lhs.ident));
    }
  }

  @override
  void build(FnBuildMixin context, bool isRet) {
    final rightVals = rightExprs.map((e) {
      var e2 = e;
      final val = e2.build(context)?.variable;
      return (val, val?.load(context));
    }).toList();

    final leftVals = leftExprs.map((e) => e.build(context)).toList();

    var length = leftVals.length;
    if (length != rightVals.length) {
      Log.e('mismatch in the number of variables');
      return;
    }

    for (var i = 0; i < length; i++) {
      final lhs = leftVals[i]?.variable;
      final (rhs, rValue) = rightVals[i];

      if (lhs is! StoreVariable || rhs == null || rValue == null) {
        Log.e('let error.');
        return;
      }

      final ignore = lhs.ty is RefTy || rhs.ty is RefTy;

      if (!ignore) {
        ImplStackTy.replaceStack(context, lhs, rhs);
      }

      lhs.store(context, rValue);

      if (!ignore) {
        ImplStackTy.updateStack(context, lhs);
      }
    }
  }

  @override
  LetSwapStmt clone() {
    return LetSwapStmt(leftExprs.clone(), rightExprs.clone());
  }

  @override
  late List<Object?> props = [leftExprs, rightExprs];
  @override
  String toString() {
    return '${pad}let ${leftExprs.letSwap} = ${rightExprs.letSwap}';
  }
}

extension on List {
  String get letSwap {
    if (isEmpty) return '';
    return join(', ');
  }
}

class ExprStmt extends Stmt {
  ExprStmt(this.expr);
  final Expr expr;
  @override
  Stmt clone() {
    return ExprStmt(expr.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    expr.incLevel(count);
  }

  @override
  String toString() {
    if (expr is FnExpr) return '$expr';
    return '$pad$expr';
  }

  @override
  void build(FnBuildMixin context, bool isRet) {
    Ty? baseTy;

    if (isRet) {
      baseTy = context.getLastFnContext()!.currentFn!.getRetTy(context);
      if (baseTy.isTy(LiteralKind.kVoid.ty)) {
        baseTy = null;
      }
    }

    final temp = switch (expr) {
      RetExprMixin e => e.build(context, baseTy: baseTy, isRet: isRet),
      var e => e.build(context, baseTy: baseTy),
    };

    final val = temp?.variable;

    if (isRet) {
      if (expr is RetExprMixin) val?.getBaseValue(context);
      context.ret(val, isLastStmt: true);
      return;
    }

    /// init
    if (val is LLVMAllocaProxyVariable) {
      /// 无须分配空间
      val.initProxy(cancel: true);
    } else {
      val?.getBaseValue(context);
    }
  }

  @override
  List<Object?> get props => [expr];

  @override
  void analysis(AnalysisContext context) {
    expr.analysis(context);
  }
}

class RetStmt extends Stmt {
  RetStmt(this.expr, this.ident);
  final Expr? expr;
  final Identifier ident;

  @override
  void build(FnBuildMixin context, bool isRet) {
    Ty? baseTy = context.getLastFnContext()!.currentFn!.getRetTy(context);
    if (baseTy.isTy(LiteralKind.kVoid.ty)) {
      baseTy = null;
    }

    final e = expr?.build(context, baseTy: baseTy);

    context.ret(e?.variable, isLastStmt: isRet);
  }

  @override
  List<Object?> get props => [expr, ident];
  @override
  RetStmt clone() {
    return RetStmt(expr?.clone(), ident);
  }

  @override
  void analysis(AnalysisContext context) {
    if (expr == null) return;

    analysisAll(context, expr!, ident);
  }

  static AnalysisVariable? analysisAll(AnalysisContext context, Expr expr,
      [Identifier? currentIdent]) {
    final val = expr.analysis(context);
    final current = context.getLastFnContext();

    void check(AnalysisVariable? val) {
      if (val != null && current != null) {
        final valLife = val.lifecycle.fnContext;
        if (valLife != null) {
          if (val.kind.isRef) {
            if (val.lifecycle.isInner && current.isChildOrCurrent(valLife)) {
              final ident = currentIdent ?? val.lifeIdent ?? val.ident;
              Log.e('lifecycle Error: (${context.currentPath}'
                  ':${ident.offset.pathStyle})\n${ident.light}');
            }
          }
        }
      }

      if (val != null) {
        final vals = current?.currentFn?.returnVariables;
        if (vals != null) {
          final all = val.allParent;
          all.insert(0, val);

          // 判断是否同源， 用于`sret`, struct ret
          //
          // let y = Foo { 1, 2}
          // if condition {
          //  return y;
          // } else {
          //  let x = y;
          //  return x; // 与 `y` 同源
          // }
          for (var val in all) {
            final ident = val.ident.toRawIdent;
            vals.add(ident);
          }
        }
      }
    }

    if (val is AnalysisListVariable) {
      for (var v in val.vals) {
        check(v);
      }
      return val.vals.first;
    }

    check(val);
    return val;
  }

  @override
  String toString() {
    return 'return $expr [Ret]';
  }
}

class StaticStmt extends Stmt {
  StaticStmt(this.ident, this.expr, this.ty, this.isConst);
  final bool isConst;
  @override
  Stmt clone() {
    return StaticStmt(ident, expr.clone(), ty, isConst);
  }

  final Identifier ident;
  final PathTy? ty;
  final Expr expr;

  @override
  String toString() {
    final y = ty == null ? '' : ' : $ty';
    return '${pad}static $ident$y = $expr';
  }

  bool _run = false;
  @override
  void build(FnBuildMixin context, bool isRet) {
    if (_run) return;
    final realTy = ty?.grtOrT(context);
    if (ty != null && realTy == null) return;

    final e = expr.build(context, baseTy: realTy);

    final rty = realTy ?? e?.ty;
    final val = e?.variable;
    if (e == null || val == null) return;

    final y = rty ?? e.ty;
    final type = y.typeOf(context);

    context.diSetCurrentLoc(ident.offset);

    LLVMValueRef llValue;
    Variable v;
    final data = val.getBaseValue(context);

    llValue = llvm.LLVMAddGlobal(context.module, type, ident.src.toChar());

    v = LLVMAllocaVariable(llValue, y, type, ident);
    llvm.LLVMSetLinkage(llValue, LLVMLinkage.LLVMInternalLinkage);
    llvm.LLVMSetGlobalConstant(llValue, isConst.llvmBool);

    llvm.LLVMSetInitializer(llValue, data);
    llvm.LLVMSetAlignment(llValue, context.getAlignSize(y));

    final diBuilder = context.dBuilder;
    if (diBuilder != null) {
      final file = llvm.LLVMDIScopeGetFile(context.scope);
      final diType = y.llty.createDIType(context);
      final name = ident.src;
      final (namePointer, nameLength) = name.toNativeUtf8WithLength();

      final expr = llvm.LLVMDIBuilderCreateExpression(diBuilder, nullptr, 0);
      final align = context.getAlignSize(y);
      final globalExpr = llvm.LLVMDIBuilderCreateGlobalVariableExpression(
          context.dBuilder!,
          context.scope,
          namePointer,
          nameLength,
          namePointer,
          nameLength,
          file,
          ident.offset.row,
          diType,
          LLVMTrue,
          expr,
          nullptr,
          align);

      llvm.LLVMGlobalSetMetadata(
          llValue, llvm.LLVMGetMDKindID("dbg".toChar(), 3), globalExpr);
    }

    context.pushVariable(v);
    _run = true;
  }

  @override
  List<Object?> get props => [ident, ty, expr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final val = expr.analysis(context);
    final vTy = realTy ?? val?.ty;
    if (vTy == null || val == null) return;
    context.pushVariable(val.copy(ty: vTy, ident: ident, isGlobal: true));
  }
}

class TyStmt extends Stmt {
  TyStmt(this.ty);
  final Ty ty;
  @override
  Stmt clone() {
    return TyStmt(ty);
  }

  @override
  void build(FnBuildMixin context, bool isRet) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }

  @override
  String toString() {
    return '$pad$ty';
  }

  @override
  List<Object?> get props => [ty];
}

class StructStmt extends Stmt {
  StructStmt(this.ty);
  @override
  Stmt clone() {
    return StructStmt(ty);
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final StructTy ty;

  @override
  void build(FnBuildMixin context, bool isRet) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  String toString() {
    return '$pad$ty';
  }

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }
}

class EnumStmt extends Stmt {
  EnumStmt(this.ty);
  @override
  Stmt clone() {
    return EnumStmt(ty);
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final EnumTy ty;

  @override
  void build(FnBuildMixin context, bool isRet) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }
}
