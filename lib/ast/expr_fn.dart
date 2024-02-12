part of 'expr.dart';

class FnExpr extends Expr {
  FnExpr(this.fn);
  final Fn fn;
  @override
  FnExpr cloneSelf() {
    return FnExpr(fn.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    fn.incLevel(count);
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    return fn;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    fn.prepareBuild(context);

    if (fn.fnDecl.done) {
      final value = fn.genFn();
      return ExprTempValue(value);
    }

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
    final decl = fn.fnDecl;
    if (decl case ImplFnDecl(ident: Identifier(src: 'new'), implFn: var implFn)
        when implFn.isStatic) {
      final fields = decl.fields;
      final sortFields = alignParam(params, fields);
      final newParams = <Variable>[];
      for (var i = 0; i < sortFields.length; i++) {
        final p = sortFields[i];
        Ty? baseTy;
        if (i < fields.length) {
          baseTy = decl.getFieldTy(context, fields[i]);
        }

        final temp = p.build(context, baseTy: baseTy);
        var v = temp?.variable;
        if (v != null) {
          v = v.newIdent(fields[i].ident);
          newParams.add(v);
        }
      }

      var variable = context.compileRun(implFn, newParams);
      if (variable == null) return null;

      return ExprTempValue(variable);
    }

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
  Expr cloneSelf() {
    return FnCallExpr(expr.clone(), params.clone());
  }

  @override
  String toString() {
    return '$expr(${params.ast})';
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    final temp = expr.getTy(context, null);
    if (temp is StructTy) return temp;
    if (temp is BuiltinFn) {
      return doTysFns(context, temp);
    }

    if (temp == null) return null;

    final callTemp = CallBuilder.callImplTy(context, temp, params);
    if (callTemp != null) return callTemp;
    if (temp is FnDecl) return temp.getRetTyOrT(context);
    if (temp is Fn) return temp.fnDecl.getRetTyOrT(context);

    return null;
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
    if (fn is BuiltinFn) {
      return doBuiltFns(context, fn, temp.ident ?? Identifier.none, params);
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
      return StructExpr.analysisStruct(context, valTy, params)
          .copy(ident: variable.ident);
    }

    final temp = CallBuilder.callImplTys(context, variable, params);
    if (temp != null) return temp;

    if (variable.ty is BuiltinFn) {
      return doAnalysisFns(context, variable.ty);
    }

    if (valTy is FnDecl) {
      return context.createVal(valTy.getRetTy(context), variable.ident);
    }

    if (valTy is! Fn) return null;
    final fn = valTy.resolveGeneric(context, params);
    return context.createVal(fn.fnDecl.getRetTy(context), Identifier.none);
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
  Expr cloneSelf() {
    return MethodCallExpr(ident, receiver.clone(), params.clone());
  }

  @override
  String toString() {
    if (receiver is OpExpr) {
      return '($receiver).$ident(${params.ast})';
    }
    return '$receiver.$ident(${params.ast})';
  }

  ImplFnMixin? resolveImplFn(Tys context, Ty structTy) {
    var implFn = context.getImplFnForTy(structTy, ident);

    if (structTy case StructTy(done: false)
        when implFn != null && implFn.isStatic) {
      /// 对于类方法(静态方法)，struct 中存在泛型，并且没有指定时，从静态方法中的参数列表
      /// 自动获取
      final map =
          implFn.fnDecl.getTysWith(context, params, others: structTy.generics);

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

    return implFn;
  }

  @override
  Ty? getTy(Tys context, Ty? baseTy) {
    final temp = receiver.getTy(context, null);
    var structTy = temp;

    if (structTy is NewInst && structTy.tys.isEmpty && structTy.isTy(baseTy)) {
      structTy = baseTy!;
    }

    if (structTy == null) return null;

    if (structTy is StructTy) {
      for (var field in structTy.fields) {
        if (field.ident != ident) continue;

        if (field.grtOrTUd(context) case FnDecl decl) {
          return decl.getRetTyOrT(context);
        }
      }
    }

    final implFn = resolveImplFn(context, structTy);

    return implFn?.fnDecl.getRetTyOrT(context);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = receiver.build(context);
    final variable = temp?.variable;

    var structTy = variable?.ty ?? temp?.ty;
    if (structTy == null) return null;

    if (structTy is NewInst && structTy.tys.isEmpty && structTy.isTy(baseTy)) {
      structTy = baseTy!;
    }

    ImplFnMixin? implFn;
    Variable? val;

    if (variable == null) {
      implFn = resolveImplFn(context, structTy);
    } else {
      val = variable.getBaseVariable(context, variable.ident);
      // 字段有可能是一个函数指针
      if (val.ty case StructTy ty) {
        final field = ty.llty.getField(val, context, ident);
        if (field case Variable(ty: FnDecl ty)) {
          return baseCall(context, field!, ty, params);
        }
      }

      RefDerefCom.loopGetDeref(context, val, (variable) {
        final fn = context.getImplFnForTy(variable.ty, ident);
        if (fn != null) {
          implFn = fn;
          val = variable;
          return true;
        }

        return false;
      });
    }

    if (implFn != null) return fnCall(context, implFn!, params, struct: val);

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

    Fn? fn = resolveImplFn(context, structTy);

    if (fn == null) {
      if (structTy is! StructTy) return null;
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
