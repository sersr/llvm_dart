part of 'expr.dart';

class FnExpr extends Expr {
  FnExpr(this.fn);
  final Fn fn;
  @override
  FnExpr clone() {
    return FnExpr(fn.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    fn.incLevel(count);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    fn.prepareBuild(context);
    return ExprTempValue.ty(fn, fn.ident);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    fn.prepareAnalysis(context);
    fn.analysisFn();
    return context.createVal(fn, fn.fnDecl.ident);
  }

  @override
  String toString() {
    return '$fn';
  }
}

mixin FnCallMixin {
  ExprTempValue? baseCall(
      FnBuildMixin context, Variable fn, FnDecl decl, List<FieldExpr> params) {
    return AbiFn.fnCallInternal(
      context: context,
      fn: fn,
      decl: decl,
      params: params,
      extern: decl.extern,
    );
  }

  ExprTempValue? fnCall(
    FnBuildMixin context,
    Fn fn,
    List<FieldExpr> params, {
    Variable? struct,
  }) {
    fn = fn.resolveGeneric(context, params);
    final fnValue = fn.genFn();
    return AbiFn.fnCallInternal(
      context: context,
      fn: fnValue,
      decl: fn.fnDecl,
      params: params,
      struct: struct,
      extern: fn.fnDecl.extern,
    );
  }
}

class FnCallExpr extends Expr with FnCallMixin {
  FnCallExpr(this.expr, this.params);
  final Expr expr;
  final List<FieldExpr> params;

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;

  @override
  Expr clone() {
    return FnCallExpr(expr.clone(), params.clone());
  }

  @override
  String toString() {
    return '$expr(${params.ast})';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = expr.build(context);
    if (temp == null) return null;
    final variable = temp.variable;
    final ty = temp.ty;

    if (ty is StructTy && variable != null) {
      return temp;
    }

    if (ty is StructTy) {
      return StructExpr.buildTupeOrStruct(ty, context, params);
    }

    final fn = ty;

    final builtinFn =
        doBuiltFns(context, fn, temp.ident ?? Identifier.none, params);
    if (builtinFn != null) {
      return builtinFn;
    }

    if (variable != null) {
      final temp = CallBuilder.callImpl(context, variable, params);
      if (temp != null) return temp;
    }

    if (fn is FnDecl && variable != null) {
      return baseCall(context, variable, fn, params);
    }

    if (fn is! Fn) return null;

    return fnCall(context, fn, params);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final variable = expr.analysis(context);
    for (var p in params) {
      p.analysis(context);
    }

    if (variable == null) return null;

    final valTy = variable.ty;
    if (valTy is StructTy) {
      return StructExpr.analysisStruct(context, valTy, params);
    }

    final temp = CallBuilder.callImplTys(context, variable, params);
    if (temp != null) return temp;

    final builtVal = doAnalysisFns(context, variable.ty);
    if (builtVal != null) return builtVal;

    if (valTy is FnDecl) {
      return context.createVal(valTy.getRetTy(context), variable.ident);
    }

    if (valTy is! Fn) return null;
    final fnnn = valTy.resolveGeneric(context, params);

    return context.createVal(fnnn.fnDecl.getRetTy(context), Identifier.none);
  }
}

class MethodCallExpr extends Expr with FnCallMixin {
  MethodCallExpr(this.ident, this.receiver, this.params);
  final Identifier ident;
  final Expr receiver;
  final List<FieldExpr> params;

  @override
  bool get hasUnknownExpr => receiver.hasUnknownExpr;

  @override
  Expr clone() {
    return MethodCallExpr(ident, receiver.clone(), params.clone());
  }

  @override
  String toString() {
    if (receiver is OpExpr) {
      return '($receiver).$ident(${params.ast})';
    }
    return '$receiver.$ident(${params.ast})';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = receiver.build(context);
    final variable = temp?.variable;
    final fnName = ident.src;

    final val = variable?.defaultDeref(context, variable.ident);

    if (variable != null) {
      final temp = CallBuilder.callImpl(context, variable, params);
      if (temp != null) return temp;
    }

    var valTy = val?.ty ?? temp?.ty;
    if (valTy == null) return null;

    var structTy = valTy;

    if (structTy is StructTy && structTy.tys.isEmpty) {
      if (baseTy is StructTy && structTy.ident == baseTy.ident) {
        structTy = baseTy;
      }
    }

    if (temp != null) {
      final builtin = context.root
          .arrayBuiltin(context, ident, fnName, val, structTy, params);
      if (builtin != null) return builtin;
    }

    var implFn = context.getImplFnForTy(structTy, ident);

    if (structTy case StructTy(done: false)
        when implFn != null && implFn.isStatic) {
      /// 对于类方法(静态方法)，struct 中存在泛型，并且没有指定时，从静态方法中的参数列表
      /// 自动获取
      final map =
          implFn.fnDecl.getTysWith(context, params, others: structTy.generics);
      if (structTy.tys.length != structTy.generics.length) {
        final newTys = <Identifier, Ty>{}..addAll(structTy.tys);
        for (var g in structTy.generics) {
          final ty = map[g.ident];
          if (ty != null) {
            newTys[g.ident] = ty;
          }
        }
        structTy = structTy.newInst(newTys, context);
        implFn = context.getImplFnForTy(structTy, ident);
      }
    }

    if (implFn != null) return fnCall(context, implFn, params, struct: val);

    // 字段有可能是一个函数指针

    if (val != null && structTy is StructTy && variable != null) {
      final field = structTy.llty.getField(val, context, ident);
      final fn = field?.ty;
      if (fn is FnDecl && field != null) {
        return baseCall(context, field, fn, params);
      }
    }

    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var variable = receiver.analysis(context);
    for (var p in params) {
      p.analysis(context);
    }

    if (variable == null) return null;
    var structTy = variable.ty;

    final temp = CallBuilder.callImplTys(context, variable, params);
    if (temp != null) return temp;

    if (structTy is! StructTy) return null;

    var implFn = context.getImplFnForTy(structTy, ident);

    if (!structTy.done && implFn != null && implFn.isStatic) {
      final map =
          implFn.fnDecl.getTysWith(context, params, others: structTy.generics);
      if (structTy.tys.length != structTy.generics.length) {
        final newTys = <Identifier, Ty>{...structTy.tys};
        for (var g in structTy.generics) {
          final ty = map[g.ident];
          if (ty != null) {
            newTys[g.ident] = ty;
          }
        }
        structTy = structTy.newInst(newTys, context);
        implFn = context.getImplFnForTy(structTy, ident);
      }
    }

    Fn? fn = implFn;

    if (fn == null) {
      final field =
          structTy.fields.firstWhereOrNull((element) => element.ident == ident);
      final ty = field?.grtOrT(context);
      if (ty is FnDecl) {
        return context.createVal(ty.getRetTy(context), ident);
      }
    }
    if (fn == null) return null;
    fn = fn.resolveGeneric(context, params);

    return context.createVal(fn.fnDecl.getRetTy(context), Identifier.none);
  }
}
