import 'package:llvm_dart/ast/context.dart';
import 'package:nop/nop.dart';

import 'ast.dart';

class LetStmt extends Stmt {
  LetStmt(this.ident, this.nameIdent, this.rExpr, this.ty);
  final Identifier ident;
  final Identifier nameIdent;
  final Expr? rExpr;
  final Ty? ty;

  @override
  String toString() {
    final tyy = ty == null ? '' : ' : $ty';
    final rE = rExpr == null ? '' : ' = $rExpr';

    return '${pad}let $nameIdent$tyy$rE';
  }

  @override
  void build(BuildContext context) {
    Variable? val;
    if (rExpr != null) {
      val = rExpr!.build(context);
    }
    if (ty != null && val != null && ty != val.ty) {
      // error
      return;
    }
    final t = ty ?? val?.ty;
    if (val != null) {
      final v = context.buildAlloca(val, ty: t);
      context.pushVariable(nameIdent, v);
    } else if (t != null) {
      final v = context.buildAllocaNull(t);
      context.pushVariable(nameIdent, v);
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
  final Ty? ty;
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
    if (e == null) return;
    if (ty != null && e.ty != ty) {
      Log.e('$ty = ${e.ty}');
      return;
    }
    final y = ty ?? e.ty;
    final v = context.buildVariable(y, variable.src);
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
  void build(BuildContext context) {
    // TODO: implement build
  }

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
  void build(BuildContext context) {
    // TODO: implement build
  }

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
  void build(BuildContext context) {
    // TODO: implement build
  }

  @override
  List<Object?> get props => [ty];
}
