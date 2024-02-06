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
    fn.build();
    return ExprTempValue.ty(fn, fn.ident);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    fn.prepareAnalysis(context);
    fn.analysis();
    return context.createVal(fn, fn.fnSign.fnDecl.ident);
  }

  @override
  String toString() {
    return '$fn';
  }
}

mixin FnCallMixin {
  Map<Identifier, Set<AnalysisVariable>> get childrenVariables {
    return _catchMapFns.map((key, value) => MapEntry(key, value()));
  }

  Set<AnalysisVariable> get catchVariables {
    final cache = <AnalysisVariable>{};
    for (var v in _catchFns) {
      cache.addAll(v());
    }
    return cache;
  }

  final _catchFns = <Set<AnalysisVariable> Function()>[];
  final _catchMapFns = <Identifier, Set<AnalysisVariable> Function()>{};

  void addChild(Identifier ident, Fn fnty) {
    ff() => fnty.variables;
    _catchFns.add(ff);
    _catchMapFns[ident] = ff;
  }

  void autoAddChild(Fn fn, List<FieldExpr> params, AnalysisContext context) {
    // ignore: invalid_use_of_protected_member
    final fields = fn.fnSign.fnDecl.params;
    final sortFields =
        alignParam(params, (p) => fields.indexWhere((e) => e.ident == p.ident));
    for (var f in sortFields) {
      Ty? vty;
      Identifier? ident;
      final index = sortFields.indexOf(f);
      if (index < fields.length) {
        final rf = fields[index];
        ident = rf.ident;
        final v = f.analysis(context);
        vty = v?.ty;
      } else {
        final fpv = f.analysis(context);
        vty = fpv?.ty;
        ident = fpv?.ident;
      }
      if (vty is Fn && ident != null) {
        addChild(ident, vty);
      }
    }
  }

  ExprTempValue? fnCall(
    FnBuildMixin context,
    Fn fn,
    Identifier ident,
    List<FieldExpr> params, {
    Variable? struct,
  }) {
    return AbiFn.fnCallInternal(
      context: context,
      fn: fn,
      ident: ident,
      params: params,
      struct: struct,
      extra: catchVariables,
      map: childrenVariables,
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
    final f = FnCallExpr(expr.clone(), params.clone());
    f._catchFns.addAll(_catchFns);
    f._catchMapFns.addAll(_catchMapFns);
    return f;
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

    if (fn is! Fn) return null;

    return fnCall(context, fn, variable?.ident ?? Identifier.none, params);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final fn = expr.analysis(context);
    if (fn == null) return null;
    final fnty = fn.ty;
    if (fnty is StructTy) {
      return StructExpr.analysisStruct(context, fnty, params);
    }

    final builtVal = doAnalysisFns(context, fn.ty);
    if (builtVal != null) {
      return builtVal;
    }

    if (fnty is! Fn) return null;
    final fnnn = fnty.resolveGeneric(context, params);
    autoAddChild(fnnn, params, context);

    return context.createVal(
        fnnn.fnSign.fnDecl.returnTy.grt(context), Identifier.none);
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
    return MethodCallExpr(ident, receiver.clone(), params.clone())
      .._catchFns.addAll(_catchFns)
      .._paramFn = _paramFn
      .._catchMapFns.addAll(_catchMapFns);
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

    if (structTy is StructTy) {
      /// 对于类方法(静态方法)，struct 中存在泛型，并且没有指定时，从静态方法中的参数列表
      /// 自动获取
      if (!structTy.done && implFn is ImplStaticFn) {
        final map =
            implFn.getTysWith(context, params, others: structTy.generics);
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
    }

    Fn? fn = implFn;

    // 字段有可能是一个函数指针
    if (fn == null) {
      if (val != null && structTy is StructTy) {
        final field = structTy.llty.getField(val, context, ident);
        if (field != null) {
          // 匿名函数作为参数要处理捕捉的变量
          if (field.ty is FnTy) {
            assert(_paramFn is Fn, 'ty: ${field.ty}, _paramFn: $_paramFn');
            fn = _paramFn ?? field.ty as FnTy;
          }
        }
      }
    }
    if (fn == null) return null;

    return fnCall(context, fn, ident, params, struct: val);
  }

  Fn? _paramFn;

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var variable = receiver.analysis(context);
    if (variable == null) return null;
    var structTy = variable.ty;
    if (structTy is! StructTy) return null;

    var implFn = context.getImplFnForTy(structTy, ident);

    if (!structTy.done && implFn is ImplStaticFn) {
      final map = implFn.getTysWith(context, params, others: structTy.generics);
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
      if (ty is FnTy) {
        fn = ty;
        autoAddChild(fn, params, context);
      }
    }
    if (fn == null) return null;
    fn = fn.resolveGeneric(context, params);

    return context.createVal(fn.getRetTy(context), Identifier.none);
  }
}
