// ignore_for_file: constant_identifier_names

import 'package:collection/collection.dart';

class Ast {}

mixin NamedAstMixin on Ast {
  String get name;
}

abstract class TypeAst extends Ast {}

class VoidTypeAst extends TypeAst {}

class ParamField extends Ast with NamedAstMixin {
  ParamField(this.name, this.type);
  @override
  final String name;
  final TypeAst type;

  @override
  String toString() {
    return '$name: $type';
  }
}

class EnumField extends TypeAst with NamedAstMixin {
  EnumField(this.name, this.fields);
  @override
  final String name;
  final List<ParamField> fields;
}

class EnumAst extends TypeAst with NamedAstMixin {
  EnumAst(this.name, this.fields);
  @override
  final String name;
  final List<EnumField> fields;
}

abstract class TypeBuiltinAst extends TypeAst {}

enum BuiltinType {
  kInt('int'),
  kFloat('float'),
  kDouble('double'),
  kString('string');

  const BuiltinType(this.text);
  final String text;
  static BuiltinType? parse(String text) {
    return BuiltinType.values
        .firstWhereOrNull((element) => element.text == text);
  }
}

class BuiltinTypeAst extends TypeBuiltinAst {
  BuiltinTypeAst(this.type);
  final BuiltinType type;

  static BuiltinTypeAst? parse(String text) {
    final type = BuiltinType.parse(text);
    if (type == null) return null;
    return BuiltinTypeAst(type);
  }

  @override
  String toString() {
    return type.text;
  }
}

class StructField extends Ast with NamedAstMixin {
  StructField(this.name, this.type);
  @override
  final String name;
  final TypeAst type;
  @override
  String toString() {
    return '$name: $type';
  }
}

class StructAst extends TypeAst with NamedAstMixin {
  StructAst(this.name, this.fields);
  @override
  final String name;
  final List<StructField> fields;

  @override
  String toString() {
    return 'Struct: $name {${fields.join(',')}}';
  }
}

class Block extends Stmt {
  Block(this.stmts);
  final List<Stmt> stmts;

  @override
  String toString() {
    return 'Block:{${stmts.join(';')}}';
  }
}

abstract class Stmt {
  TypeAst get returnType => VoidTypeAst();
}

abstract class Expr extends Stmt {}

class IfElseItem {
  IfElseItem(this.expr, this.block);
  final Expr expr;
  final Block block;
}

/// 可以是表达式
class IfElseStmt extends Stmt {
  IfElseStmt(this.ifItem, this.elseItem, this.elseIfItems);
  final IfElseItem ifItem;
  final IfElseItem elseItem;
  final List<IfElseItem> elseIfItems;
}

enum AssignOperand {
  eqSub('-='),
  eqMut('*='),
  eqDiv('/='),
  eqAdd('+='),
  eq("=");

  final String operand;
  const AssignOperand(this.operand);

  static AssignOperand? parse(String text) {
    return values.firstWhereOrNull((element) => element.operand == text);
  }
}

class LetStmt extends AssignStmt {
  LetStmt(super.name, super.type, super.expr);

  @override
  String toString() {
    return 'let $name: ${type ?? expr.returnType} = $expr';
  }
}

class AssignStmt extends Stmt {
  AssignStmt(this.name, this.type, this.expr, [this.op = AssignOperand.eq]);
  final String name;
  final TypeAst? type;
  final Expr expr;
  final AssignOperand op;

  @override
  TypeAst get returnType => type ?? super.returnType;
  @override
  String toString() {
    return 'AssignStmt: $name: ${type ?? expr.returnType} ${op.operand} $expr';
  }
}

class ForStmt extends Stmt {
  final AssignStmt? assign;
  final Expr? condition;
  final Stmt? stmt;
  final Block block;

  ForStmt(this.assign, this.condition, this.stmt, this.block);
}

class VariableRef extends Expr {
  VariableRef(this.pointer);
  final AssignStmt pointer;

  @override
  TypeAst get returnType => pointer.returnType;
}

abstract class TypeValueExpr extends Expr {}

class ValueExpr extends TypeValueExpr {
  ValueExpr(this.type, this.value);
  final BuiltinTypeAst type;
  final String value;

  @override
  String toString() {
    return '$value (:${type.type.text})';
  }

  @override
  TypeAst get returnType => type;
}

// Gen(name: "dev"); foo(name: "dev")
class ParamListExpr extends TypeValueExpr {
  ParamListExpr(this.name, this.expr);
  final String name;
  final Expr expr;

  @override
  TypeAst get returnType => expr.returnType;
}

class StructInitExpr extends TypeValueExpr {
  StructInitExpr(this.type, this.values);
  final StructAst type;
  final List<Expr> values;

  @override
  String toString() {
    return 'StructInitExpr: ${type.name}{${values.join(', ')}}';
  }

  @override
  TypeAst get returnType => type;
}

class FunctionAst extends Ast with NamedAstMixin {
  FunctionAst(this.name, this.params, this.block, this.returnType);
  @override
  final String name;
  final List<ParamField> params;
  final Block block;
  TypeAst returnType;

  @override
  String toString() {
    return 'Function: $name(${params.join(', ')}) => $returnType $block';
  }
}

class VoidExprStmt extends Stmt {
  VoidExprStmt(this.expr);
  final Expr expr;

  @override
  String toString() {
    return 'VoidExprStmt: $expr';
  }
}

class FunctionCallExpr extends Expr {
  FunctionCallExpr(this.function, this.values);

  final FunctionAst function;
  final List<Expr> values;

  @override
  TypeAst get returnType => function.returnType;

  @override
  String toString() {
    return '${function.name}(${values.join(',')})';
  }
}

class ReturnStmt extends Stmt {
  ReturnStmt(this.expr);
  final Expr expr;
}

// let x = 0
// x.foo()
// x
// x..foo()..bar()
class VariableExpr extends Expr {
  VariableExpr(this.name, this.exprs);
  final String name;
  final List<Expr> exprs;
  @override
  String toString() {
    return '$name.${exprs.join('.')}';
  }
}

enum Operand {
  lt('<'),
  ltOrEq('<='),
  gt('>'),
  gtOrEq('>='),
  add('+'),
  sub('-'),
  mul('*'),
  div('/'),
  mod('%'),
  ;

  final String op;
  const Operand(this.op);
}

class OpExpr extends Expr {
  OpExpr(this.op, this.lhs, this.rhs);
  final Operand op;
  final Expr? lhs;
  final Expr? rhs;

  @override
  String toString() {
    return '$lhs ${op.op} $rhs';
  }
}
