import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:nop/nop.dart';

import 'ast.dart';
import 'variables.dart';

class LetStmt extends Stmt {
  LetStmt(this.ident, this.nameIdent, this.rExpr, this.ty);
  final Identifier ident;
  final Identifier nameIdent;
  final Expr? rExpr;
  final PathTy? ty;

  @override
  String toString() {
    final tyy = ty == null ? '' : ' : $ty';
    final rE = rExpr == null ? '' : ' = $rExpr';

    return '${pad}let $nameIdent$tyy$rE';
  }

  @override
  void build(BuildContext context) {
    ExprTempValue? val = rExpr?.build(context);
    final realTy = ty?.grt(context);

    final tty = realTy ?? val?.ty;
    if (tty != null) {
      final variable = val?.variable;
      if (realTy != null && variable is LLVMLitVariable) {
        if (tty is BuiltInTy) {
          final alloca = tty.llvmType.createAlloca(context, nameIdent);
          final rValue = variable.load(context, ty: tty);
          alloca.store(context, rValue);

          context.pushVariable(nameIdent, alloca);
          return;
        }
        // error
      }
      if (variable is StoreVariable && variable.isTemp) {
        variable.isTemp = false;
        context.setName(variable.alloca, nameIdent.src);
        context.pushVariable(nameIdent, variable);
        return;
      }
      if (variable != null) {
        final rValue = variable.load(context);
        if (variable is LLVMRefAllocaVariable) {
          final s = LLVMRefAllocaVariable.create(context, variable.parent);
          s.store(context, rValue);
          context.setName(s.alloca, nameIdent.src);
          // context.setName(variable.alloca, nameIdent.src);
          context.pushVariable(nameIdent, s);
        } else {
          final alloca = tty.llvmType.createAlloca(context, nameIdent);
          alloca.store(context, rValue);

          context.pushVariable(nameIdent, alloca);
        }
      }
    }
  }

  @override
  List<Object?> get props => [ident, nameIdent, ty, rExpr];
}

class ExprStmt extends Stmt {
  ExprStmt(this.expr);
  final Expr expr;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    expr.incLevel(count);
  }

  @override
  String toString() {
    return '$pad$expr';
  }

  @override
  void build(BuildContext context) {
    expr.build(context);
  }

  @override
  List<Object?> get props => [expr];
}

class StaticStmt extends Stmt {
  StaticStmt(this.ident, this.variable, this.expr, this.ty);

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
    final e = expr.build(context);
    final rty = ty?.grt(context);
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
}

class TyStmt extends Stmt {
  TyStmt(this.ty);
  final Ty ty;

  @override
  void build(BuildContext context) {}

  @override
  List<Object?> get props => [ty];
}

class FnStmt extends Stmt {
  FnStmt(this.fn) {
    fn.incLevel();
  }
  final Fn fn;

  @override
  String toString() {
    return '$pad$fn';
  }

  @override
  void build(BuildContext context) {}

  @override
  List<Object?> get props => [fn];
}

class StructStmt extends Stmt {
  StructStmt(this.ty);
  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final StructTy ty;

  @override
  void build(BuildContext context) {}

  @override
  List<Object?> get props => [ty];
}

class EnumStmt extends Stmt {
  EnumStmt(this.ty);
  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final EnumTy ty;

  @override
  void build(BuildContext context) {}

  @override
  List<Object?> get props => [ty];
}
