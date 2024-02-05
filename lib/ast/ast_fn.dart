part of 'ast.dart';

// 函数声明
class FnDecl with EquatableMixin {
  FnDecl(this.ident, this.params, this.generics, this.returnTy, this.isVar);
  final Identifier ident;

  FnDecl copywith(List<FieldDef> params) {
    return FnDecl(ident, params, generics, returnTy, isVar);
  }

  final List<FieldDef> params;
  final List<GenericDef> generics;

  final PathTy returnTy;
  final bool isVar;

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    final g = generics.isNotEmpty ? '<${generics.join(',')}>' : '';
    return '$ident$g(${params.join(',')}$isVals) -> $returnTy';
  }

  @override
  List<Object?> get props => [ident, params, returnTy];

  void analysis(AnalysisContext context, Fn fn) {
    for (var p in params) {
      final t = fn.getFieldTyOrT(context, p);
      context.pushVariable(
        context.createVal(t ?? AnalysisTy(p.rawTy), p.ident, p.rawTy.kind)
          ..lifecycle.isOut = true,
      );
    }
  }
}

// 函数签名
class FnSign with EquatableMixin {
  FnSign(this.extern, this.fnDecl);
  final FnDecl fnDecl;
  // header
  final bool extern;

  Identifier get ident => fnDecl.ident;

  @override
  String toString() {
    return fnDecl.toString();
  }

  void analysis(AnalysisContext context, Fn fn) {
    fnDecl.analysis(context, fn);
  }

  @override
  List<Object?> get props => [fnDecl, extern];
}

class Fn extends Ty with NewInst<Fn> {
  Fn(this.fnSign, this.block);

  Identifier get fnName => fnSign.fnDecl.ident;

  @override
  Identifier get ident => fnName;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block?.incLevel(count);
  }

  final FnSign fnSign;
  final Block? block;

  @override
  String toString() {
    var b = '';
    if (block != null) {
      b = ' $block';
    }

    var ext = '';
    if (extern) {
      ext = 'extern ';
    }

    return '$pad${ext}fn $fnSign$b${tys.str}';
  }

  @override
  List<Object?> get props => [fnSign, block, _tys, _constraints];

  Ty getRetTy(Tys c) {
    return getRetTyOrT(c)!;
  }

  Ty? getRetTyOrT(Tys c) {
    return fnSign.fnDecl.returnTy.grtOrT(c, gen: (ident) {
      return getTy(c, ident);
    });
  }

  @override
  Fn clone() {
    return Fn(fnSign, block)..copy(this);
  }

  final _cache = <ListKey, LLVMConstVariable>{};

  @override
  void prepareBuild(FnBuildMixin context, {bool push = true}) {
    super.prepareBuild(context);
    if (push) context.pushFn(fnName, this);
  }

  void copy(Fn from) {
    _parent = from.parentOrCurrent;
    selfVariables = from.selfVariables;
    _get = from._get;
    _buildContext = from.currentContext;
  }

  LLVMConstVariable? genFn([
    Set<AnalysisVariable>? variables,
    Map<Identifier, Set<AnalysisVariable>>? map,
    bool ignoreFree = false,
  ]) {
    final context = currentContext;
    assert(context != null);
    if (context == null) return null;
    return _customBuild(context, variables, ignoreFree, map);
  }

  LLVMConstVariable? _customBuild(FnBuildMixin context,
      [Set<AnalysisVariable>? variables,
      bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    final vk = [];

    final k = getKey();
    if (k != null) {
      vk.add(k);
    }

    if (variables != null && variables.isNotEmpty) {
      vk.add(variables.toList());
    }
    for (var v in selfVariables) {
      final vt = v.ty;
      vk.add(vt);
      // if (vt is StructTy) {
      //   vk.add(vt.tys);
      // }
    }
    final key = ListKey(vk);

    var fn = parentOrCurrent._cache[key];
    if (fn != null) return fn;
    fn = context.buildFnBB(this, variables, ignoreFree, map ?? const {});
    return parentOrCurrent._cache[key] = fn;
  }

  void pushTyGenerics(Tys context) {
    context.pushDyTys(tys);
  }

  Object? getKey() {
    return null;
  }

  Set<AnalysisVariable> selfVariables = {};
  Set<AnalysisVariable> get variables {
    final v = _get?.call();
    if (v == null) return selfVariables;
    return {...selfVariables, ...v};
  }

  Set<AnalysisVariable> Function()? _get;

  Set<RawIdent> returnVariables = {};

  bool _anaysised = false;

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
    context.pushFn(ident, this);
  }

  void analysisStart(AnalysisContext context) {}

  void analysisFn() {
    final context = analysisContext;
    if (_anaysised || context == null) return;
    _anaysised = true;
    if (generics.isNotEmpty && tys.isEmpty) {
      return;
    }

    final child = context.childContext();
    pushTyGenerics(child);

    child.setFnContext(this);
    fnSign.fnDecl.analysis(child, this);
    analysisStart(child);
    block?.analysis(child, hasRet: true);
    selfVariables = child.catchVariables;
    _get = () => child.childrenVariables;
  }

  @override
  late final LLVMFnType llty = LLVMFnType(this);

  @override
  List<FieldDef> get fields => fnSign.fnDecl.params;
  @override
  List<GenericDef> get generics => fnSign.fnDecl.generics;

  @override
  Fn newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return Fn(s, block)..copy(this);
  }
}

mixin ImplFnMixin on Fn {
  ImplTy get implty;

  Ty get ty => implty.ty!;

  final _fnList = <ImplTy, ImplFnMixin>{};

  ImplFnMixin? getWith(ImplTy ty) {
    final parent = parentOrCurrent as ImplFnMixin;
    if (parent.implty == ty) return parent;
    return parent._fnList.putIfAbsent(ty, () => newWithImplTy(ty));
  }

  ImplFnMixin newWithImplTy(ImplTy ty);

  @override
  ImplFnMixin newTy(List<FieldDef> fields);

  @override
  void pushTyGenerics(Tys context) {
    super.pushTyGenerics(context);
    _pushSelf(context);
  }

  static final _selfTyIdent = 'Self'.ident;

  void _pushSelf(Tys context) {
    final structTy = implty.ty;
    if (structTy != null) context.pushDyTy(_selfTyIdent, structTy);

    context.pushDyTys(implty.tys);
  }

  @override
  Object? getKey() {
    return implty;
  }

  @override
  Ty? getTy(Tys c, Identifier ident) {
    final tempTy = super.getTy(c, ident);
    if (tempTy != null) {
      return tempTy;
    }

    final ty = implty.ty;
    if (ident.src == 'Self') {
      return ty;
    }

    return implty.tys[ident];
  }

  // @override
  // List<Object?> get props => [super.props, _constraints];
}

class ImplFn extends Fn with ImplFnMixin {
  ImplFn(super.fnSign, super.block, this.implty);
  @override
  final ImplTy implty;

  @override
  ImplFnMixin newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return ImplFn(s, block, implty)..copy(this);
  }

  @override
  ImplFn newWithImplTy(ImplTy ty) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields.clone()));
    return ImplFn(s, block, ty)..copy(this);
  }

  @override
  void analysisStart(AnalysisContext context) {
    final ident = Identifier.self;
    final ty = implty.ty;
    if (ty == null) return;
    final v = context.createVal(ty, ident);
    v.lifecycle.isOut = true;
    context.pushVariable(v);
  }
}

class ImplStaticFn extends Fn with ImplFnMixin {
  ImplStaticFn(super.fnSign, super.block, this.implty);
  @override
  final ImplTy implty;

  @override
  ImplFnMixin newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return ImplStaticFn(s, block, implty)..copy(this);
  }

  @override
  ImplStaticFn newWithImplTy(ImplTy ty) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields.clone()));
    return ImplStaticFn(s, block, ty)..copy(this);
  }
}

class FnTy extends Fn {
  FnTy(FnDecl fnDecl) : super(FnSign(false, fnDecl), null);

  FnTy copyWith(Set<AnalysisVariable> extra) {
    final rawDecl = fnSign.fnDecl;
    final cache = rawDecl.params.toList();
    for (var e in extra) {
      cache.add(FieldDef(e.ident, PathTy.ty(e.ty, [PointerKind.ref])));
    }
    final decl = FnDecl(rawDecl.ident, cache, rawDecl.generics,
        rawDecl.returnTy, rawDecl.isVar);
    return FnTy(decl)
      ..copy(this)
      .._constraints = _constraints;
  }

  @override
  Fn clone() {
    return FnTy(fnSign.fnDecl)..copy(this);
  }

  @override
  LLVMConstVariable? build(
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    return null;
  }
}
