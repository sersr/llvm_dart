part of 'expr.dart';

class LiteralExpr extends Expr {
  LiteralExpr(this.ident, this.ty);
  final Identifier ident;
  final BuiltInTy ty;
  @override
  Expr clone() {
    return LiteralExpr(ident, ty);
  }

  @override
  String toString() {
    if (ty.literal == LiteralKind.kStr) {
      return '${jsonEncode(ident.src)}[:$ty]';
    }
    return '${ident.src}[:$ty]';
  }

  @override
  Ty? getTy(Tys context) {
    return ty;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    if (baseTy is! BuiltInTy) {
      baseTy = ty;
    }
    final v = baseTy.llty.createValue(ident: ident);

    return ExprTempValue(v);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return context.createVal(ty, ident);
  }
}

// struct: CS{ name: "struct" }
class StructExpr extends Expr {
  StructExpr(this.expr, this.params);
  final Expr expr;
  final List<FieldExpr> params;

  @override
  Ty? getTy(Tys context) {
    return expr.getTy(context);
  }

  @override
  StructExpr clone() {
    return StructExpr(expr.clone(), params.clone());
  }

  @override
  String toString() {
    return '$expr{${params.ast}}';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    var structTy = getTy(context);

    if (structTy is StructTy && structTy.tys.isEmpty) {
      if (baseTy is StructTy && structTy.ident == baseTy.ident) {
        structTy = baseTy;
      }
    }

    if (structTy is! StructTy) return null;

    return buildTupeOrStruct(structTy, context, params);
  }

  static ExprTempValue? buildTupeOrStruct(
      StructTy struct, FnBuildMixin context, List<FieldExpr> params) {
    struct = struct.resolveGeneric(context, params);
    var fields = struct.fields;
    final sortFields =
        alignParam(params, (p) => fields.indexWhere((e) => e.ident == p.ident));

    for (var i = 0; i < params.length; i++) {
      final param = params[i];
      final sfIndex = sortFields.indexOf(param);
      assert(sfIndex >= 0);
      final fd = fields[sfIndex];
      param.build(context, baseTy: struct.getFieldTy(context, fd));
    }

    final value = struct.llty.buildTupeOrStruct(
      context,
      params,
      sFields: sortFields,
    );

    return ExprTempValue(value);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var val = expr.analysis(context);
    var ty = val?.ty;
    if (ty is! StructTy) return null;
    return analysisStruct(context, ty, params);
  }

  static AnalysisVariable analysisStruct(
      AnalysisContext context, StructTy ty, List<FieldExpr> params) {
    final struct = ty.resolveGeneric(context, params);

    final sortFields = alignParam(
        params, (p) => struct.fields.indexWhere((e) => e.ident == p.ident));

    for (var field in sortFields) {
      field.analysis(context);
    }

    return context.createVal(struct, struct.ident);
  }
}

class ArrayExpr extends Expr {
  ArrayExpr(this.elements, this.identStart, this.identEnd);

  final Identifier identStart;
  final Identifier identEnd;

  final List<Expr> elements;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    Ty? ty;
    for (var element in elements) {
      final v = element.analysis(context);
      if (v != null) {
        ty ??= v.ty;
      }
    }

    if (ty == null) return null;
    return context.createVal(ArrayTy(ty, elements.length), Identifier.none);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final values = <LLVMValueRef>[];
    Ty? arrTy = baseTy;

    Ty? ty;
    if (arrTy is ArrayTy) {
      ty = arrTy.elementTy;
    }

    Ty? elementTy;
    for (var element in elements) {
      final v = element.build(context, baseTy: ty);
      final variable = v?.variable;
      if (variable != null) {
        elementTy ??= variable.ty;
        values.add(variable.load(context));
      }
    }

    ty ??= elementTy;

    if (arrTy == null && ty != null) {
      arrTy = ArrayTy(ty, elements.length);
    }
    if (arrTy is ArrayTy) {
      final extra = arrTy.size - values.length;
      if (extra > 0) {
        final zero =
            values.lastOrNull ?? llvm.LLVMConstNull(ty!.typeOf(context));
        values.addAll(List.generate(extra, (index) => zero));
      }
      final v = arrTy.llty.createArray(context, values);
      return ExprTempValue(v);
    }

    return null;
  }

  @override
  ArrayExpr clone() {
    return ArrayExpr(elements.clone(), identStart, identEnd);
  }

  @override
  String toString() {
    return '[${elements.join(',')}]';
  }
}

class ArrayOpExpr extends Expr {
  ArrayOpExpr(this.ident, this.arrayOrPtr, this.expr);
  final Identifier ident;
  final Expr arrayOrPtr;
  final Expr expr;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final array = arrayOrPtr.build(context);
    final arrVal = array?.variable;
    final ty = arrVal?.ty;

    if (arrVal == null) return null;

    final temp = ArrayOpImpl.elementAt(context, arrVal, ident, expr);
    if (temp != null) return temp;

    final loc = expr.build(context);
    final locVal = loc?.variable;
    if (locVal == null || loc == null) return null;

    if (ty is ArrayTy) {
      final element =
          ty.llty.getElement(context, arrVal, locVal.load(context), ident);

      return ExprTempValue(element);
    } else if (ty is RefTy) {
      final elementTy = ty.parent.typeOf(context);
      final offset = ident.offset;

      final element = LLVMAllocaVariable.delay(() {
        final index = locVal.load(context);
        final indics = <LLVMValueRef>[index];
        final p = arrVal.load(context);

        context.diSetCurrentLoc(offset);
        return llvm.LLVMBuildInBoundsGEP2(context.builder, elementTy, p,
            indics.toNative(), indics.length, unname);
      }, ty.parent, elementTy, ident);

      return ExprTempValue(element);
    }

    return null;
  }

  @override
  ArrayOpExpr clone() {
    return ArrayOpExpr(ident, arrayOrPtr.clone(), expr.clone());
  }

  @override
  String toString() {
    return "$arrayOrPtr[$expr]";
  }
}
