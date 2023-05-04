import 'package:nop/nop.dart';

import '../llvm_core.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'context.dart';
import 'expr.dart';
import 'llvm/variables.dart';

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
  void build(BuildContext context) {
    final realTy = ty?.grt(context);
    ExprTempValue? val = LiteralExpr.run(() {
      return rExpr?.build(context);
    }, realTy);

    final tty = realTy ?? val?.ty;
    if (tty != null) {
      final variable = val?.variable;
      if (variable is LLVMLitVariable) {
        if (tty is BuiltInTy) {
          final alloca = variable.createAlloca(context, tty);
          alloca.isTemp = false;
          alloca.ident = nameIdent;
          context.setName(alloca.alloca, nameIdent.src);
          context.pushVariable(nameIdent, alloca);
          return;
        }
        // error
      }

      StoreVariable? alloca;
      final (_, delayAlloca) = context.sretVariable(nameIdent, variable);
      if (delayAlloca != null) {
        alloca = delayAlloca;
        delayAlloca.ident = nameIdent;
      }

      if (variable is StoreVariable && variable.isTemp) {
        variable.isTemp = false;
        variable.ident = nameIdent;
        context.setName(variable.alloca, nameIdent.src);
        context.pushVariable(nameIdent, variable);
        return;
        // } else if (variable is LLVMAllocaVariable && variable.ty is StructTy) {
        //   alloca = tty.llvmType.createAlloca(context, nameIdent);
        //   final rValue = variable.load(context);
        //   alloca.store(context, rValue);
      }

      if (alloca == null) {
        bool wrapRef = variable?.isRef == true;
        if (wrapRef) {
          alloca = RefTy(tty)
              .llvmType
              .createAlloca(context, nameIdent, isPointer: false);
        } else {
          alloca = tty.llvmType.createAlloca(context, nameIdent);
        }

        LLVMValueRef? rValue;
        if (variable != null) {
          if (wrapRef) {
            rValue = variable.getBaseValue(context);
          } else {
            rValue = variable.load(context);
          }
        }
        if (rValue != null) {
          alloca.store(context, rValue);
        }
      }
      alloca.isTemp = false;
      context.pushVariable(nameIdent, alloca);
    }
  }

  @override
  List<Object?> get props => [ident, nameIdent, ty, rExpr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final v = LiteralExpr.run(() {
      return rExpr?.analysis(context);
    }, realTy);

    if (v == null) return;

    context.pushVariable(nameIdent, v.copy(ty: realTy, ident: nameIdent));
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
  void build(BuildContext context) {
    expr.build(context);
  }

  @override
  List<Object?> get props => [expr];

  @override
  void analysis(AnalysisContext context) {
    expr.analysis(context);
  }
}

class StaticStmt extends Stmt {
  StaticStmt(this.ident, this.variable, this.expr, this.ty);
  @override
  Stmt clone() {
    return StaticStmt(ident, variable, expr.clone(), ty);
  }

  final Identifier variable;
  final PathTy? ty;
  final Identifier ident;
  final Expr expr;

  @override
  String toString() {
    final y = ty == null ? '' : ' : $ty';
    return '${pad}static $variable$y = $expr';
  }

  @override
  void build(BuildContext context) {
    final realTy = ty?.grt(context);
    final e = LiteralExpr.run(() => expr.build(context), realTy);

    final rty = realTy ?? e?.ty;
    if (e == null) return;
    if (rty != null && e.ty != rty) {
      Log.e('$ty = ${e.ty}');
      return;
    }
    final y = rty ?? e.ty;
    final v = y.llvmType.createAlloca(context, ident);
    context.pushVariable(variable, v);
  }

  @override
  List<Object?> get props => [ident, variable, ty, expr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final val = LiteralExpr.run(() => expr.analysis(context), realTy);
    final vTy = realTy ?? val?.ty;
    if (vTy == null || val == null) return;
    context.pushVariable(ident, val.copy(ty: vTy, ident: ident));
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
  void build(BuildContext context) {}

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {}
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
  void build(BuildContext context) {
    ty.build(context);
  }

  @override
  String toString() {
    return '$ty';
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
  void build(BuildContext context) {
    ty.build(context);
  }

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }
}
