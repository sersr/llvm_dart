// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:llvm_dart/ast/buildin.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:llvm_dart/llvm_core.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';

import '../llvm_dart.dart';
import 'ast.dart';
import 'variables.dart';

class LiteralExpr extends Expr {
  LiteralExpr(this.ident, this.ty);
  final Identifier ident;
  final BuiltInTy ty;

  @override
  String toString() {
    return '$ident[:$ty]';
  }

  static T run<T>(T Function() body, Ty? ty) {
    return runZoned(body, zoneValues: {#ty: ty});
  }

  BuiltInTy get realTy {
    final r = Zone.current[#ty];
    if (r is BuiltInTy) {
      return r;
    }
    return ty;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v = realTy.llvmType.createValue(context, str: ident.src);

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
    if (v == null) return null;
    return ExprTempValue(v, v.ty);
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
    // todo: phi
    return null;
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
    return null;
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
  }

  @override
  String toString() {
    return 'return $expr [Ret]';
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
    final sortFields = alignParam(
        fields, (p) => struct.fields.indexWhere((e) => e.ident == p.ident));

    for (var i = 0; i < sortFields.length; i++) {
      final f = sortFields[i];

      final v = f.build(context)?.variable;
      if (v == null) continue;
      final indics = <LLVMValueRef>[];
      indics.add(context.constI32(0));
      indics.add(context.constI32(i));
      final c = llvm.LLVMBuildInBoundsGEP2(context.builder, structType,
          value.alloca, indics.toNative(), indics.length, unname);

      llvm.LLVMBuildStore(context.builder, v.load(context), c);
    }
    return ExprTempValue(value, value.ty);
  }
}

class StructExprField {
  StructExprField(this.ident, this.expr);
  final Identifier? ident;
  final Expr expr;

  @override
  String toString() {
    return '$ident: $expr';
  }

  ExprTempValue? build(BuildContext context) {
    return expr.build(context);
  }
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

List<F> alignParam<F>(List<F> src, int Function(F) test) {
  final sortFields = <F>[];
  final fieldMap = <int, F>{};

  for (var i = 0; i < src.length; i++) {
    final p = src[i];
    final index = test(p);
    if (index != -1) {
      fieldMap[index] = p;
    } else {
      sortFields.add(p);
    }
  }

  var index = 0;
  for (var i = 0; i < sortFields.length; i++) {
    final p = sortFields[i];
    while (true) {
      if (fieldMap.containsKey(index)) {
        index++;
        continue;
      }
      fieldMap[index] = p;
      break;
    }
  }

  sortFields.clear();
  final keys = fieldMap.keys.toList()..sort();
  for (var k in keys) {
    final v = fieldMap[k];
    if (v != null) {
      sortFields.add(v);
    }
  }

  return sortFields;
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
    if (fn is SizeofFn) {
      if (params.isEmpty) {
        return null;
      }
      final first = params.first;
      final e = first.expr.build(context);
      Ty? ty = e?.ty;
      if (ty == null) {
        final e = first.expr;
        if (e is VariableIdentExpr) {
          final p = PathTy(e.ident);
          ty = p.grt(context);
        }
      }
      if (ty == null) return null;

      final v = fn.llvmType.createFunction(context, ty: ty);
      return ExprTempValue(v, BuiltInTy.int);
    }
    final fnType = fn.llvmType.createType(context);
    final isExtern = fn.extern;
    final fnValue = fn.llvmType.createFunction(context);

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];

    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    for (var p in sortFields) {
      final v = p.build(context)?.variable;
      if (v != null) {
        LLVMValueRef value;
        if (isExtern && v is LLVMStructAllocaVariable) {
          value = v.load2(context, isExtern);
        } else if (v is LLVMRefAllocaVariable) {
          value = v.load(context);
        } else {
          value = v.load(context);
        }

        args.add(value);
      }
    }

    final ret = llvm.LLVMBuildCall2(context.builder, fnType,
        fnValue.load(context), args.toNative(), args.length, unname);

    final retTy = fn.fnSign.fnDecl.returnTy.grt(context);
    return ExprTempValue(LLVMTempVariable(ret, retTy), retTy);
  }
}

class MethodCallExpr extends Expr {
  MethodCallExpr(this.ident, this.receiver, this.params);
  final Identifier ident;
  final Expr receiver;
  final List<FieldExpr> params;

  @override
  String toString() {
    if (receiver is OpExpr) {
      return '($receiver).$ident(${params.join(',')})';
    }
    return '$receiver.$ident(${params.join(',')})';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final variable = receiver.build(context);
    if (variable == null) return null;

    final valTy = variable.ty;
    if (valTy is! StructTy) return null;
    final structTy = valTy;
    final val = variable.variable;
    final impl = context.getImplForStruct(structTy);
    if (val == null || impl == null) {
      // error
      return null;
    }

    final fn = impl.getFn(ident);
    if (fn == null) {
      return null;
    }

    /// `FnCallExpr`
    final fnType = fn.llvmType.createType(context);
    final isExtern = fn.extern;
    final fnValue = fn.llvmType.createFunction(context);

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];

    // struct 一般是 StoreVariable
    if (val is StoreVariable) {
      args.add(val.alloca);
    } else {
      args.add(val.load(context));
    }

    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    for (var p in sortFields) {
      final v = p.build(context)?.variable;
      if (v != null) {
        LLVMValueRef value;
        if (isExtern && v is LLVMStructAllocaVariable) {
          value = v.load2(context, isExtern);
        } else if (v is LLVMRefAllocaVariable) {
          value = v.load(context);
        } else {
          value = v.load(context);
        }

        args.add(value);
      }
    }

    final ret = llvm.LLVMBuildCall2(context.builder, fnType,
        fnValue.load(context), args.toNative(), args.length, unname);

    final retTy = fn.fnSign.fnDecl.returnTy.grt(context);
    return ExprTempValue(LLVMTempVariable(ret, retTy), retTy);
  }
}

class StructDotFieldExpr extends Expr {
  StructDotFieldExpr(this.struct, this.kind, this.ident);
  final Identifier ident;
  final Expr struct;

  final List<PointerKind> kind;

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final structVal = struct.build(context);
    final val = structVal?.variable;
    var ty = val?.ty.getRealTy(context);

    if (ty is! StructTy) return null;
    final newVal = PointerKind.refDerefs(val, context, kind);

    final v = ty.llvmType.getField(newVal as StoreVariable, context, ident);
    if (v == null) return null;
    return ExprTempValue(v, v.ty);
  }

  @override
  String toString() {
    var e = struct;
    if (e is RefExpr) {
      if (e.kind.isNotEmpty) {
        return '${kind.join('')}($struct).$ident';
      }
    }
    return '${kind.join('')}$struct.$ident';
  }
}

enum OpKind {
  /// The `+` operator (addition)
  Add('+', 60),

  /// The `-` operator (subtraction)
  Sub('-', 60),

  /// The `*` operator (multiplication)
  Mul('*', 110),

  /// The `/` operator (division)
  Div('/', 110),

  /// The `%` operator (modulus)
  Rem('%', 110),

  /// The `&&` operator (logical and)
  And('&&', 0),

  /// The `||` operator (logical or)
  Or('||', 0),

  /// The `^` operator (bitwise xor)
  BitXor('^', 1000),

  /// The `&` operator (bitwise and)
  BitAnd('&', 50),

  /// The `|` operator (bitwise or)
  BitOr('|', 50),

  /// The `<<` operator (shift left)
  Shl('<<', 50),

  /// The `>>` operator (shift right)
  Shr('>>', 50),

  /// The `==` operator (equality)
  Eq('==', 10),

  /// The `<` operator (less than)
  Lt('<', 10),

  /// The `<=` operator (less than or equal to)
  Le('<=', 10),

  /// The `!=` operator (not equal to)
  Ne('!=', 10),

  /// The `>=` operator (greater than or equal to)
  Ge('>=', 10),

  /// The `>` operator (greater than)
  Gt('>', 10),
  ;

  final String op;
  const OpKind(this.op, this.level);
  final int level;

  static OpKind? from(String src) {
    return values.firstWhereOrNull((element) => element.op == src);
  }

  int? getICmpId(bool isSigned) {
    if (index < Eq.index) return null;
    int? i;
    switch (this) {
      case Eq:
        return LLVMIntPredicate.LLVMIntEQ;
      case Ne:
        return LLVMIntPredicate.LLVMIntNE;
      case Gt:
        i = LLVMIntPredicate.LLVMIntUGT;
        break;
      case Ge:
        i = LLVMIntPredicate.LLVMIntUGE;
        break;
      case Lt:
        i = LLVMIntPredicate.LLVMIntULT;
        break;
      case Le:
        i = LLVMIntPredicate.LLVMIntULE;
        break;
      default:
    }
    if (i != null && isSigned) {
      return i + 4;
    }
    return i;
  }

  int? getFCmpId(bool isSigned) {
    if (index < Eq.index) return null;
    int? i;

    switch (this) {
      case Eq:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOEQ
            : LLVMRealPredicate.LLVMRealUEQ;
        break;
      case Ne:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealONE
            : LLVMRealPredicate.LLVMRealUNE;
        break;
      case Gt:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOGT
            : LLVMRealPredicate.LLVMRealUGT;
        break;
      case Ge:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOGE
            : LLVMRealPredicate.LLVMRealUGE;
        break;
      case Lt:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOLT
            : LLVMRealPredicate.LLVMRealULT;
        break;
      case Le:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOLE
            : LLVMRealPredicate.LLVMRealULE;
        break;
      default:
    }

    return i;
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

    var rc = rhs;
    if (rc is RefExpr) {
      if (rc.kind.isEmpty) {
        if (rc.current is OpExpr) {
          rc = rc.current;
        }
      }
    }

    if (rc is OpExpr) {
      if (op.level > rc.op.level) {
        rs = '($rs)';
      }
    }
    var lc = lhs;
    if (lc is RefExpr) {
      if (lc.kind.isEmpty) {
        if (lc.current is OpExpr) {
          lc = lc.current;
        }
      }
    }
    if (lc is OpExpr) {
      if (op.level > lc.op.level) {
        ls = '($ls)';
      }
    }

    var ss = '$ls ${op.op} $rs';
    return ss;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final l = lhs.build(context);
    // final r = rhs.build(context);

    if (l == null) return null;
    var isFloat = false;
    var signed = false;
    final lValue = l.variable;
    // final RValue = r.variable;
    if (lValue is LLVMTempOpVariable) {
      isFloat = lValue.isFloat;
      signed = lValue.isSigned;
    } else {
      var lty = l.ty;
      if (lty is BuiltInTy) {
        final kind = lty.ty;
        if (kind.isFp) {
          isFloat = true;
        } else if (kind.isInt) {
          signed = kind.signed;
        }
      }
    }

    final v = context.math(l.variable!, (context) {
      final r = rhs.build(context)?.variable;
      return r;
    }, op, isFloat, signed: signed);
    return ExprTempValue(v, v.ty);
  }
}

enum PointerKind {
  deref('*'),
  none(''),
  neg('-'),
  ref('&');

  final String char;
  const PointerKind(this.char);

  static PointerKind? from(TokenKind kind) {
    if (kind == TokenKind.and) {
      return PointerKind.ref;
    } else if (kind == TokenKind.star) {
      return PointerKind.deref;
    } else if (kind == TokenKind.minus) {
      return PointerKind.neg;
    }
    return null;
  }

  Variable? refDeref(Variable? val, BuildContext c) {
    if (this == PointerKind.none) return val;
    Variable? inst;
    if (val != null) {
      if (val is LLVMRefAllocaVariable && this == PointerKind.deref) {
        inst = val.getDeref(c);
      } else if (this == PointerKind.ref) {
        inst = val.getRef(c);
      } else if (this == PointerKind.neg) {
        final va = val.load(c);
        final t = llvm.LLVMTypeOf(va);
        final tyKind = llvm.LLVMGetTypeKind(t);
        final isFloat = tyKind == LLVMTypeKind.LLVMFloatTypeKind ||
            tyKind == LLVMTypeKind.LLVMDoubleTypeKind ||
            tyKind == LLVMTypeKind.LLVMBFloatTypeKind;
        LLVMValueRef llvmValue;
        if (isFloat) {
          llvmValue = llvm.LLVMBuildFNeg(c.builder, va, unname);
        } else {
          llvmValue = llvm.LLVMBuildNeg(c.builder, va, unname);
        }
        return LLVMTempVariable(llvmValue, val.ty);
      }
    }
    return inst;
  }

  static Variable? refDerefs(
      Variable? val, BuildContext c, List<PointerKind> kind) {
    if (val == null) return val;
    Variable? vv = val;
    for (var k in kind.reversed) {
      vv = k.refDeref(vv, c);
    }
    return vv;
  }

  @override
  String toString() => char == '' ? '$runtimeType' : char;
}

class VariableIdentExpr extends Expr {
  VariableIdentExpr(this.ident, List<PointerKind>? pointerKind)
      : pointerKind = pointerKind ?? [];
  final Identifier ident;

  final List<PointerKind> pointerKind;
  @override
  String toString() {
    return '$ident';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final val = context.getVariable(ident);
    if (val == null) return null;
    final newVal = PointerKind.refDerefs(val, context, pointerKind);
    return ExprTempValue(newVal, val.ty);
  }
}

class RefExpr extends Expr {
  RefExpr(this.current, this.kind);
  final Expr current;
  final List<PointerKind> kind;
  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final val = current.build(context);
    var vv = PointerKind.refDerefs(val?.variable, context, kind);
    if (vv != null) {
      return ExprTempValue(vv, val!.variable!.ty);
    }
    return val;
  }

  @override
  String toString() {
    var s = kind.join('');
    if (kind.isNotEmpty) {
      var e = current;
      if (e is RefExpr) {
        e = e.current;
      }
      if (e is OpExpr) {
        return '$s($current)';
      }
    }
    return '$s$current';
  }
}
