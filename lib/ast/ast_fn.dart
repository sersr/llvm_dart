part of 'ast.dart';

// 函数声明
class FnDecl extends Ty {
  FnDecl(this.ident, this.fields, this.generics, this._returnTy, this.isVar);
  @override
  final Identifier ident;

  final List<FieldDef> fields;
  final List<GenericDef> generics;

  final PathTy? _returnTy;
  final bool isVar;

  FnDecl copyWith([List<FieldDef>? newFields]) {
    return FnDecl(
        ident, newFields ?? fields.clone(), generics, _returnTy, isVar);
  }

  FnDecl copyExtra(StoreLoadMixin c, Set<AnalysisVariable> extra) {
    final newFields = fields.clone();
    for (var e in extra) {
      final ty = c.getVariable(e.ident)?.ty ?? e.ty;
      newFields.add(FieldDef.newDef(e.ident, PathTy.none, ty));
    }

    return copyWith(newFields).._constraints = _constraints;
  }

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    return 'fn $ident${generics.str}(${fields.join(',')}$isVals) -> ${_returnTy ?? 'void'}';
  }

  @override
  late final props = [ident, fields, _returnTy];

  void analysisFn(AnalysisContext context, Fn fn) {
    for (var p in fields) {
      final t = fn.getFieldTyOrT(context, p) ?? AnalysisTy(p.rawTy);
      context.pushVariable(
        context.createVal(t, p.ident, p.rawTy.kind)..lifecycle.isOut = true,
      );
    }
  }

  @override
  Ty clone() {
    return FnDecl(ident, fields.clone(), generics, _returnTy, isVar);
  }

  @override
  late final LLVMType llty = LLVMFnDeclType(this);
}

class Fn extends Ty with NewInst<Fn> {
  Fn(this.fnDecl, this.block);

  Identifier get fnName => fnDecl.ident;

  @override
  Identifier get ident => fnName;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block?.incLevel(count);
  }

  final FnDecl fnDecl;
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

    return '$pad$ext$fnDecl$b${tys.str}';
  }

  @override
  late final props = [fnDecl, block, _tys, _constraints];

  Ty getRetTy(Tys c) {
    return getRetTyOrT(c)!;
  }

  Ty? getRetTyOrT(Tys c) {
    final retTy = fnDecl._returnTy;
    if (retTy == null) return LiteralKind.kVoid.ty;
    return retTy.grtOrT(c, gen: (ident) => getTy(c, ident));
  }

  @override
  Fn clone() {
    return Fn(fnDecl, block)..copy(this);
  }

  late final _cache = <ListKey, LLVMConstVariable>{};

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
    _analysisContext = from.analysisContext;
  }

  LLVMConstVariable genFn([
    Set<AnalysisVariable>? variables,
    Map<Identifier, Set<AnalysisVariable>>? map,
    bool ignoreFree = false,
  ]) {
    return _customBuild(currentContext!, variables, ignoreFree, map);
  }

  LLVMConstVariable _customBuild(FnBuildMixin context,
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
    }

    final key = ListKey(vk);

    var fn = parentOrCurrent._cache[key];
    if (fn != null) return fn;

    fn = AbiFn.createFunction(context, this, variables);
    parentOrCurrent._cache[key] = fn;

    context.buildFnBB(
      this,
      fnValue: fn,
      map: map,
      extra: variables,
      ignoreFree: ignoreFree,
    );

    return fn;
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

  @override
  void prepareAnalysis(AnalysisContext context, {bool push = true}) {
    super.prepareAnalysis(context);
    if (push) context.pushFn(ident, this);
  }

  void analysisStart(AnalysisContext context) {}

  void analysisFn() {
    final context = analysisContext!;

    final child = context.childContext();
    pushTyGenerics(child);

    child.setFnContext(this);
    fnDecl.analysisFn(child, this);
    analysisStart(child);
    block?.analysis(child, hasRet: true);
    selfVariables = child.catchVariables;
    _get = () => child.childrenVariables;
  }

  @override
  late final LLVMFnType llty = LLVMFnType(this);

  @override
  List<FieldDef> get fields => fnDecl.fields;
  @override
  List<GenericDef> get generics => fnDecl.generics;

  @override
  Fn newTy(List<FieldDef> fields) {
    return Fn(fnDecl.copyWith(fields), block)..copy(this);
  }
}

mixin ImplFnMixin on Fn {
  ImplTy get implty;

  Ty get ty => implty.ty!;

  late final _fnList = <ImplTy, ImplFnMixin>{};

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

  void _pushSelf(Tys context) {
    final structTy = implty.ty;
    if (structTy != null) context.pushDyTy(Identifier.Self, structTy);

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
    if (ident == Identifier.Self) {
      return ty;
    }

    return implty.tys[ident];
  }
}

class ImplFn extends Fn with ImplFnMixin {
  ImplFn(super.fnSign, super.block, this.implty);
  @override
  final ImplTy implty;

  @override
  ImplFnMixin newTy(List<FieldDef> fields) {
    return ImplFn(fnDecl.copyWith(fields), block, implty)..copy(this);
  }

  @override
  ImplFn newWithImplTy(ImplTy ty) {
    return ImplFn(fnDecl.copyWith(), block, ty)..copy(this);
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
    return ImplStaticFn(fnDecl.copyWith(fields), block, implty)..copy(this);
  }

  @override
  ImplStaticFn newWithImplTy(ImplTy ty) {
    return ImplStaticFn(fnDecl.copyWith(), block, ty)..copy(this);
  }
}

// class FnTy extends Fn {
//   FnTy(FnDecl fnDecl) : super(FnSign(false, fnDecl), null);

//   FnTy copyWith(Set<AnalysisVariable> extra) {
//     final rawDecl = fnSign.fnDecl;
//     final cache = rawDecl.fields.toList();
//     for (var e in extra) {
//       cache.add(FieldDef.newDef(e.ident, PathTy.none, e.ty));
//     }
//     final decl = FnDecl(rawDecl.ident, cache, rawDecl.generics,
//         rawDecl._returnTy, rawDecl.isVar);
//     return FnTy(decl)
//       ..copy(this)
//       .._constraints = _constraints;
//   }

//   @override
//   Fn clone() {
//     return FnTy(fnSign.fnDecl)..copy(this);
//   }

//   @override
//   LLVMConstVariable? build(
//       [Set<AnalysisVariable>? variables,
//       Map<Identifier, Set<AnalysisVariable>>? map]) {
//     return null;
//   }
// }
