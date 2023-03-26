// ignore_for_file: constant_identifier_names

import 'package:collection/collection.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/llvm_core.dart';
import 'package:nop/nop.dart';

import 'ast.dart';

class LiteralExpr extends Expr {
  LiteralExpr(this.ident, this.ty);
  final Identifier ident;
  final BuiltInTy ty;

  @override
  String toString() {
    return '$ident[:$ty]';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v = ty.llvmType.createValue(context, str: ident.src);

    return ExprTempValue(v, ty);
  }
}

class IfExprBlock {
  IfExprBlock(this.expr, this.block);

  final Expr expr;
  final Block block;
  IfExprBlock? child;
  Block? elseBlock;

  void incLvel([int count = 1]) {
    block.incLevel(count);
  }

  @override
  String toString() {
    return '$expr$block';
  }
}

class IfExpr extends Expr {
  IfExpr(this.ifExpr, this.elseIfExpr, this.elseBlock) {
    IfExprBlock last = ifExpr;
    if (elseIfExpr != null) {
      for (var e in elseIfExpr!) {
        last.child = e;
        last = e;
      }
    }
    last.elseBlock = elseBlock;
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    elseBlock?.incLevel(count);
    ifExpr.incLvel();
    elseIfExpr?.forEach((element) {
      element.incLvel(count);
    });
  }

  final IfExprBlock ifExpr;
  final List<IfExprBlock>? elseIfExpr;
  final Block? elseBlock;

  @override
  String toString() {
    final el = elseBlock == null ? '' : ' else$elseBlock';
    final elIf =
        elseIfExpr == null ? '' : ' else if ${elseIfExpr!.join(' else if ')}';

    return 'if $ifExpr$elIf$el';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v = context.createIfBlock(ifExpr);
    return ExprTempValue(v, Ty.unknown);
  }
}

class BreakExpr extends Expr {
  BreakExpr(this.ident, this.label);
  final Identifier ident;
  final Identifier? label;

  @override
  String toString() {
    if (label == null) {
      return '$ident [break]';
    }
    return '$ident $label [break]';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.brLoop();
    return null;
  }
}

class ContinueExpr extends Expr {
  ContinueExpr(this.ident);
  final Identifier ident;

  @override
  String toString() {
    return ident.toString();
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.contine();
    return null;
  }
}

/// label: loop { block }
class LoopExpr extends Expr {
  LoopExpr(this.ident, this.block);
  final Identifier ident; // label
  final Block block;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  String toString() {
    return 'loop$block';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.forLoop(block, null, null);
  }
}

/// label: while expr { block }
class WhileExpr extends Expr {
  WhileExpr(this.ident, this.expr, this.block);

  final Identifier ident;
  final Expr expr;
  final Block block;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  String toString() {
    return 'while $expr$block';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.forLoop(block, null, expr);
  }
}

class RetExpr extends Expr {
  RetExpr(this.expr, this.ident);
  final Identifier ident;
  final Expr? expr;

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final e = expr?.build(context);

    context.ret(e?.variable);
    return e;
    // return expr?.build(context);
  }

  @override
  String toString() {
    return 'return [Ret]';
  }
}

// struct: CS{ name: "struct" }
class StructExpr extends Expr {
  StructExpr(this.ident, this.fields);
  final Identifier ident;
  final List<StructExprField> fields;

  @override
  String toString() {
    return '$ident{${fields.join(',')}}';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final struct = context.getStruct(ident);
    if (struct == null) return null;
    final structType = struct.llvmType.createType(context);
    final value = struct.llvmType.createValue(context);
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final v = f.build(context)?.variable;
      if (v == null) continue;
      final indics = <LLVMValueRef>[];
      indics.add(context.constI32(0));
      indics.add(context.constI32(i));
      final c = llvm.LLVMBuildInBoundsGEP2(context.builder, structType,
          value.alloca, indics.toNative().cast(), indics.length, unname);
      // value.store(context, c);
      llvm.LLVMBuildStore(context.builder, v.load(context), c);
    }
    return ExprTempValue(value, value.ty);
  }
}

class StructExprField {
  StructExprField(this.ident, this.expr);
  final Identifier ident;
  final Expr expr;

  @override
  String toString() {
    return '$ident: $expr';
  }

  ExprTempValue? build(BuildContext context) {
    return expr.build(context);
  }
}

class VariableRefExpr extends Expr {
  VariableRefExpr(this.ident);
  final Identifier ident;

  @override
  ExprTempValue? buildExpr(BuildContext context) {}
}

class AssignExpr extends Expr {
  AssignExpr(this.ref, this.ident, this.expr);
  final Identifier ident;
  final Expr ref;
  final Expr expr;

  @override
  String toString() {
    return '$ref = $expr';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final lhs = ref.build(context);
    final rhs = expr.build(context);
    final lVariable = lhs?.variable;
    final rVariable = rhs?.variable;
    if (lVariable is LLVMAllocaVariable && rVariable != null) {
      lVariable.store(context, rVariable.load(context));
    }

    return null;
  }
}

class AssignOpExpr extends AssignExpr {
  AssignOpExpr(this.op, super.ref, super.ident, super.expr);
  final OpKind op;

  @override
  String toString() {
    return '$ref ${op.op}= $expr';
  }
}

class FieldExpr extends Expr {
  FieldExpr(this.expr, this.ident);
  final Identifier? ident;
  final Expr expr;

  @override
  String toString() {
    if (ident == null) {
      return '$expr';
    }
    return '$ident: $expr';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    return expr.build(context);
  }
}

class FnCallExpr extends Expr {
  FnCallExpr(this.ident, this.params);
  final Identifier ident;
  final List<FieldExpr> params;

  @override
  String toString() {
    return '$ident(${params.join(',')})';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final fn = context.getFn(ident);
    if (fn == null) return null;

    final fnType = fn.llvmType.createType(context);
    final fnValue = fn.llvmType.createValue(context);
    // final declParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];
    for (var p in params) {
      final v = p.build(context)?.variable;
      if (v != null) {
        args.add(v.load(context));
      }
    }
    final ret = llvm.LLVMBuildCall2(context.builder, fnType,
        fnValue.load(context), args.toNative().cast(), args.length, unname);
    // return fn.fnSign.fnDecl.returnTy;
    return ExprTempValue(LLVMTempVariable(ret), fn.fnSign.fnDecl.returnTy);
  }
}

class MethodCallExpr extends Expr {
  MethodCallExpr(this.ident, this.receiver, this.params);
  final Identifier ident;
  final Expr receiver;
  final List<FieldExpr> params;

  @override
  String toString() {
    return '$receiver.$ident(${params.join(',')})';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final fn = context.getFn(ident);
    if (fn == null) {
      return null;
    }
    final declParams = fn.fnSign.fnDecl.params;
    for (var p in params) {
      p.build(context);
    }

    for (var p in params) {
      p.build(context);
    }
  }
}

enum OpKind {
  /// The `+` operator (addition)
  Add('+'),

  /// The `-` operator (subtraction)
  Sub('-'),

  /// The `*` operator (multiplication)
  Mul('*'),

  /// The `/` operator (division)
  Div('/'),

  /// The `%` operator (modulus)
  Rem('%'),

  /// The `&&` operator (logical and)
  And('&&'),

  /// The `||` operator (logical or)
  Or('||'),

  /// The `^` operator (bitwise xor)
  BitXor('^'),

  /// The `&` operator (bitwise and)
  BitAnd('&'),

  /// The `|` operator (bitwise or)
  BitOr('|'),

  /// The `<<` operator (shift left)
  Shl('<<'),

  /// The `>>` operator (shift right)
  Shr('>>'),

  /// The `==` operator (equality)
  Eq('=='),

  /// The `<` operator (less than)
  Lt('<'),

  /// The `<=` operator (less than or equal to)
  Le('<='),

  /// The `!=` operator (not equal to)
  Ne('!='),

  /// The `>=` operator (greater than or equal to)
  Ge('>='),

  /// The `>` operator (greater than)
  Gt('>'),
  ;

  final String op;
  const OpKind(this.op);

  static OpKind? from(String src) {
    return values.firstWhereOrNull((element) => element.op == src);
  }
}

class OpExpr extends Expr {
  OpExpr(this.op, this.lhs, this.rhs);
  final OpKind op;
  final Expr lhs;
  final Expr rhs;

  @override
  String toString() {
    var rs = '$rhs';
    var ls = '$lhs';
    if (rhs is OpExpr) {
      final r = rhs as OpExpr;
      if (op.index > r.op.index) {
        rs = '($rs)';
      }
    }
    if (lhs is OpExpr) {
      final l = lhs as OpExpr;
      if (op.index > l.op.index) {
        ls = '($ls)';
      }
    }
    var ss = '$ls ${op.op} $rs';

    return ss;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final l = lhs.build(context);
    final r = rhs.build(context);

    if (l == null || r == null) return null;
    var isFloat = false;
    var signed = false;
    final lValue = l.variable;
    // final RValue = r.variable;
    if (lValue is LLVMTempOpVariable) {
      isFloat = lValue.isFloat;
      signed = lValue.isSigned;
    } else {
      var lty = l.ty;
      if (lty is PathTy) {
        lty = lty.getRealTy(context) ?? lty;
      }
      if (lty is BuiltInTy) {
        final kind = lty.ty;
        if (kind == LitKind.kFloat || kind == LitKind.kDouble) {
          isFloat = true;
        }
      }
    }
    Log.w('isFloat $isFloat');
    final v =
        context.math(l.variable!, r.variable!, op, isFloat, signed: signed);
    return ExprTempValue(v, v.ty);
  }
}

class VariableIdentExpr extends Expr {
  VariableIdentExpr(this.ident);
  final Identifier ident;

  @override
  String toString() {
    return '$ident';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final val = context.getVariable(ident);
    if (val == null) return null;
    return ExprTempValue(val, val.ty);
  }
}
