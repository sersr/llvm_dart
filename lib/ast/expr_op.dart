// ignore_for_file: constant_identifier_names

part of 'expr.dart';

enum OpKind {
  /// The `+` operator (addition)
  Add('+', 70),

  /// The `-` operator (subtraction)
  Sub('-', 70),

  /// The `*` operator (multiplication)
  Mul('*', 80),

  /// The `/` operator (division)
  Div('/', 80),

  /// The `%` operator (modulus)
  Rem('%', 80),

  /// The `&&` operator (logical and)
  And('&&', 31),

  /// The `||` operator (logical or)
  Or('||', 30),

  // /// The `!` operator (not)
  // Not('!', 100),

  /// The `^` operator (bitwise xor)
  BitXor('^', 41),

  /// The `&` operator (bitwise and)
  BitAnd('&', 52),

  /// The `|` operator (bitwise or)
  BitOr('|', 50),

  /// The `<<` operator (shift left)
  Shl('<<', 60),

  /// The `>>` operator (shift right)
  Shr('>>', 60),

  /// The `==` operator (equality)
  Eq('==', 40),

  /// The `<` operator (less than)
  Lt('<', 41),

  /// The `<=` operator (less than or equal to)
  Le('<=', 41),

  /// The `!=` operator (not equal to)
  Ne('!=', 40),

  /// The `>=` operator (greater than or equal to)
  Ge('>=', 41),

  /// The `>` operator (greater than)
  Gt('>', 41),
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

  int? getFCmpId(bool ordered) {
    if (index < Eq.index) return null;
    int? i;

    switch (this) {
      case Eq:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOEQ
            : LLVMRealPredicate.LLVMRealUEQ;
        break;
      case Ne:
        i = ordered
            ? LLVMRealPredicate.LLVMRealONE
            : LLVMRealPredicate.LLVMRealUNE;
        break;
      case Gt:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOGT
            : LLVMRealPredicate.LLVMRealUGT;
        break;
      case Ge:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOGE
            : LLVMRealPredicate.LLVMRealUGE;
        break;
      case Lt:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOLT
            : LLVMRealPredicate.LLVMRealULT;
        break;
      case Le:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOLE
            : LLVMRealPredicate.LLVMRealULE;
        break;
      default:
    }

    return i;
  }
}

class OpExpr extends Expr {
  OpExpr(this.op, this.lhs, this.rhs, this.opIdent);
  final OpKind op;
  final Expr lhs;
  final Expr rhs;

  final Identifier opIdent;

  @override
  bool get hasUnknownExpr => lhs.hasUnknownExpr || rhs.hasUnknownExpr;

  @override
  Expr cloneSelf() {
    return OpExpr(op, lhs.clone(), rhs.clone(), opIdent);
  }

  @override
  String toString() {
    var rs = '$rhs';
    var ls = '$lhs';

    var rc = rhs;

    if (rc is OpExpr) {
      if (op.level > rc.op.level) {
        rs = '($rs)';
      }
    }
    var lc = lhs;

    if (lc is OpExpr) {
      if (op.level > lc.op.level) {
        ls = '($ls)';
      }
    }

    var ss = '$ls ${op.op} $rs';
    return ss;
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    final lty = lhs.getTy(context, baseTy);
    final rty = rhs.getTy(context, baseTy ?? lty);
    Ty? bestTy = lty ?? rty;

    if (lty is BuiltInTy && rty is BuiltInTy) {
      final big = lty.literal.size > rty.literal.size;
      bestTy = big ? lty : rty;
    } else if (lty is RefTy || rty is BuiltInTy) {
      return LiteralKind.i64.ty;
    }
    return bestTy;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final bestTy = getTy(context, baseTy);

    var l = lhs.build(context, baseTy: bestTy);
    var r = rhs.build(context, baseTy: l?.ty ?? bestTy);
    if (l == null || r == null) return null;

    final value = math(context, op, l.variable, rhs, opIdent);
    var val = value?.variable;
    final valTy = val?.ty;

    if (valTy != null && valTy.isTy(baseTy)) {
      return value;
    }

    if (baseTy is BuiltInTy && baseTy != valTy && valTy is BuiltInTy) {
      if (valTy.literal == LiteralKind.kStr && baseTy.literal.isInt) {
        val = LLVMAllocaVariable(val!.getBaseValue(context), baseTy,
            baseTy.typeOf(context), Identifier.none);
      } else {
        final v =
            context.castLit(valTy.literal, val!.load(context), baseTy.literal);
        val = LLVMConstVariable(v, baseTy, Identifier.none);
      }
      return ExprTempValue(val);
    } else if (l.ty is RefTy && valTy is BuiltInTy && valTy.literal.isInt) {
      return ExprTempValue(
          LLVMConstVariable(val!.getBaseValue(context), l.ty, Identifier.none));
    }

    return value;
  }

  static ExprTempValue? math(FnBuildMixin context, OpKind op, Variable? l,
      Expr? rhs, Identifier opIdent) {
    if (l == null) return null;
    final rhsExp =
        rhs?.build(context, baseTy: l.ty is RefTy ? LiteralKind.i64.ty : l.ty);

    final v = context.math(l, rhsExp?.variable, op, opIdent);

    return ExprTempValue(v);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final l = lhs.analysis(context);
    // final r = lhs.analysis(context);
    if (l == null) return null;
    if (op.index >= OpKind.Eq.index && op.index <= OpKind.Gt.index ||
        op.index >= OpKind.And.index && op.index <= OpKind.Or.index) {
      return context.createVal(LiteralKind.kBool.ty, Identifier.none);
    }
    return context.createVal(l.ty, Identifier.none);
  }
}

enum PointerKind {
  pointer('*'),
  ref('&');

  final String char;
  const PointerKind(this.char);

  static PointerKind? from(TokenKind kind) {
    if (kind == TokenKind.and) {
      return PointerKind.ref;
    } else if (kind == TokenKind.star) {
      return PointerKind.pointer;
    }
    return null;
  }

  Ty? unWrapTy(Ty? baseTy) {
    if (baseTy is! RefTy) return null;
    return baseTy.parent;
  }

  Ty refDrefTy(Tys c, Ty ty) {
    return switch (this) {
      pointer when ty is RefTy => ty.parent,
      ref => RefTy(ty),
      _ => ty,
    };
  }

  Variable? refDeref(Variable? val, StoreLoadMixin c, Identifier id) {
    Variable? inst;
    if (val != null) {
      if (this == PointerKind.pointer) {
        inst = val.defaultDeref(c, id);
      } else if (this == PointerKind.ref) {
        inst = val.getRef(c, id);
      }
    }
    return inst ?? val;
  }

  @override
  String toString() => char == '' ? '$runtimeType' : char;
}

extension ListPointerKind on List<PointerKind> {
  Ty wrapRefTy(Ty baseTy) {
    for (var i = length - 1; i >= 0; i--) {
      final kind = this[i];
      baseTy = RefTy.from(baseTy, kind == PointerKind.pointer);
    }
    return baseTy;
  }

  Ty unWrapRefTy(Ty baseTy) {
    for (var _ in this) {
      if (baseTy is RefTy) {
        baseTy = baseTy.parent;
      }
    }
    return baseTy;
  }
}

class RefExpr extends Expr {
  RefExpr(this.current, this.pointerIdent, this.kind);
  final Expr current;
  final PointerKind kind;
  final Identifier pointerIdent;
  @override
  bool get hasUnknownExpr => current.hasUnknownExpr;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    current.incLevel(count);
  }

  @override
  Expr cloneSelf() {
    return RefExpr(current.clone(), pointerIdent, kind);
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    if (baseTy != null) {
      baseTy = kind.unWrapTy(baseTy);
    }

    final temp = current.getTy(context, baseTy);
    return temp;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final val = current.build(context, baseTy: kind.unWrapTy(baseTy));
    var variable = val?.variable;
    if (variable == null) return val;

    var vv = kind.refDeref(val?.variable, context, pointerIdent);
    if (vv != null) {
      return ExprTempValue(vv.newIdent(pointerIdent));
    }
    return val;
  }

  @override
  String toString() {
    return '$kind$current';
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final val = current.analysis(context);
    if (val == null) return null;
    final state = kind == PointerKind.ref && val.isAlloca && !val.isGlobal;
    final deps = state ? [val] : const <AnalysisVariable>[];

    final ty = kind.refDrefTy(context, val.ty);
    return context.createVal(ty, pointerIdent)..lifecycle.updateRef(deps);
  }
}

enum UnaryKind {
  /// The `!` operator (not)
  Not('!'),
  Neg('-'),
  ;

  final String op;
  const UnaryKind(this.op);

  static UnaryKind? from(String src) {
    return values.firstWhereOrNull((element) => element.op == src);
  }
}

class UnaryExpr extends Expr {
  UnaryExpr(this.op, this.expr, this.opIdent);
  final UnaryKind op;
  final Expr expr;

  final Identifier opIdent;

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;

  @override
  UnaryExpr cloneSelf() {
    return UnaryExpr(op, expr.clone(), opIdent);
  }

  @override
  String toString() {
    return '${op.op}$expr';
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    final temp = expr.getTy(context, baseTy);

    if (op == UnaryKind.Not) {
      if (LiteralKind.kBool.ty.isTy(temp)) return temp;
      return null;
    }

    return temp;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = expr.build(context, baseTy: baseTy);
    var val = temp?.variable;
    if (val == null) return null;
    if (op == UnaryKind.Not) {
      if (val.ty.isTy(LiteralKind.kBool.ty)) {
        final value = val.load(context);
        final notValue = llvm.LLVMBuildNot(context.builder, value, unname);
        final variable = LLVMConstVariable(notValue, val.ty, opIdent);
        return ExprTempValue(variable);
      }

      return OpExpr.math(context, OpKind.Eq, val, null, opIdent);
    } else if (op == UnaryKind.Neg) {
      final va = val.load(context);
      final t = llvm.LLVMTypeOf(va);
      final tyKind = llvm.LLVMGetTypeKind(t);
      final isFloat = tyKind == LLVMTypeKind.LLVMFloatTypeKind ||
          tyKind == LLVMTypeKind.LLVMDoubleTypeKind ||
          tyKind == LLVMTypeKind.LLVMBFloatTypeKind;
      LLVMValueRef llvmValue;
      if (isFloat) {
        llvmValue = llvm.LLVMBuildFNeg(context.builder, va, unname);
      } else {
        llvmValue = llvm.LLVMBuildNeg(context.builder, va, unname);
      }
      final variable = LLVMConstVariable(llvmValue, val.ty, opIdent);
      return ExprTempValue(variable);
    }
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    // todo
    final temp = expr.analysis(context);
    // final r = lhs.analysis(context);
    if (temp == null) return null;

    return context.createVal(temp.ty, Identifier.none);
  }
}

class AssignExpr extends Expr {
  AssignExpr(this.ref, this.expr);
  final Expr ref;
  final Expr expr;
  @override
  Expr cloneSelf() {
    return AssignExpr(ref.clone(), expr.clone());
  }

  @override
  bool get hasUnknownExpr => ref.hasUnknownExpr || expr.hasUnknownExpr;

  @override
  String toString() {
    return '$ref = $expr';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final lhs = ref.build(context);
    final rhs = expr.build(context, baseTy: lhs?.ty);

    final lv = lhs?.variable;
    final rv = rhs?.variable;

    if (lv is StoreVariable && rv != null) {
      var cav = rv;
      if (!lv.ty.isTy(rv.ty)) {
        cav = AsBuilder.asType(context, rv, Identifier.none, lv.ty);
      }
      lv.storeVariable(context, cav);
    }

    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final lhs = ref.analysis(context);
    final rhs = expr.analysis(context);
    if (lhs != null) {
      final lty = lhs.ty;

      if (rhs != null) {
        if (lty is! BuiltInTy && !RefTy.isRefTy(lty, rhs.ty)) {
          Log.e('$lty != ${rhs.ty}\n${lhs.ident.light}', showTag: false);
        }

        if (rhs.lifecycle.isStackRef) {
          final newVal = lhs.copy(ident: lhs.ident);
          newVal.lifecycle.updateRef([rhs]);
          return newVal;
        }
      }

      return lhs;
    }
    return null;
  }
}

class AssignOpExpr extends AssignExpr {
  AssignOpExpr(this.op, this.opIdent, super.ref, super.expr);
  final OpKind op;
  final Identifier opIdent;
  @override
  Expr cloneSelf() {
    return AssignOpExpr(op, opIdent, ref.clone(), expr.clone());
  }

  @override
  String toString() {
    return '$ref ${op.op}= $expr';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final lhs = ref.build(context);
    final lVariable = lhs?.variable;

    if (lVariable is StoreVariable) {
      final val = OpExpr.math(context, op, lVariable, expr, opIdent);
      final rValue = val?.variable;
      if (rValue != null) {
        lVariable.storeVariable(context, rValue);
      }
    }

    return null;
  }
}
