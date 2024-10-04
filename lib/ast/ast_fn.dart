part of 'ast.dart';

// 函数声明
class FnDecl extends Ty with NewInst<FnDecl> {
  FnDecl(this.ident, this.fields, this.generics, this._returnTy, this.isVar);
  @override
  final Identifier ident;

  @override
  final List<FieldDef> fields;

  @override
  final List<GenericDef> generics;

  final PathTy? _returnTy;
  final bool isVar;
  bool? _isDyn;

  set isDyn(bool v) => _isDyn = v;

  bool get isDyn => _isDyn ?? _parent?.isDyn ?? false;

  @override
  bool isTy(Ty? other) {
    if (other is FnDecl) {
      return const DeepCollectionEquality().equals(declProps, other.declProps);
    }
    return this == other;
  }

  bool isVoidRet(Tys c) =>
      _returnTy == null || getRetTyOrT(c) == LiteralKind.kVoid.ty;

  Ty getRetTy(Tys c) {
    return getRetTyOrT(c)!;
  }

  Ty? getRetTyOrT(Tys c) {
    final retTy = _returnTy;
    if (retTy == null) return LiteralKind.kVoid.ty;
    return retTy.grtOrT(c, gen: (ident) => getTy(c, ident));
  }

  FnDecl copyWith(List<FieldDef> newFields) {
    return FnDecl(ident, newFields, generics, _returnTy, isVar);
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
  FnDecl resolveGeneric(Tys context, List<FieldExpr> params) {
    if (generics.isEmpty && !extern) {
      final sortFields = alignParam(params, fields);
      bool update = false;

      final isBuild = context is FnBuildMixin;
      final newFields = List.of(fields);

      for (var param in params) {
        final sfIndex = sortFields.indexOf(param);
        assert(sfIndex >= 0);

        if (sfIndex > fields.length) continue;

        final fd = fields[sfIndex];
        final baseTy = fd.grtOrTUd(context);
        Ty? ty;

        if (isBuild) {
          final temp = param.build(context, baseTy: baseTy);
          ty = temp?.variable?.ty ?? temp?.ty;
        } else {
          ty = param.analysis(context as AnalysisContext)?.ty;
        }

        if (ty case FnDecl decl
            when baseTy is! FnClosure && decl.isTy(baseTy)) {
          newFields[sfIndex] = FieldDef.newDef(fd.ident, fd.rawTy, decl);
          update = true;
        }
      }

      if (update) {
        final newDecl = newTy(newFields);
        newDecl.cloneTys(context, this);
        return newDecl;
      }

      return this;
    }

    return super.resolveGeneric(context, params);
  }

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    final dyn = isDyn ? 'dyn ' : '';
    return '${dyn}fn $ident${generics.str}(${fields.join(',')}$isVals) -> ${_returnTy ?? 'void'}${tys.str}';
  }

  late final declProps = [fields, _returnTy, _tys];

  @override
  late final props = [fields, _returnTy, _tys];

  void analysisFn(AnalysisContext context) {
    for (var p in fields) {
      final t = getFieldTyOrT(context, p) ?? AnalysisTy(p.rawTy);
      context.pushNew(context.createVal(t, p.ident));
    }
  }

  @override
  FnDecl clone() {
    return FnDecl(ident, fields.clone(), generics, _returnTy, isVar);
  }

  @override
  late final LLVMFnDeclType llty = LLVMFnDeclType(this);

  @override
  FnDecl newTy(List<FieldDef> fields) {
    return copyWith(fields);
  }

  ImplFnDecl _toImpl() {
    return ImplFnDecl(ident, fields, generics, _returnTy, isVar);
  }

  FnCatch toCatch(List<Variable> variables, List<AnalysisVariable> analysis) {
    return FnCatch._(
        ident, fields, generics, _returnTy, isVar, analysis, variables);
  }

  FnClosure toDyn() {
    return FnClosure(ident, fields.clone(), generics, _returnTy, isVar);
  }
}

class ImplFnDecl extends FnDecl {
  ImplFnDecl(
      super.ident, super.fields, super.generics, super.returnTy, super.isVar);
  ImplFnDecl._(super.ident, super.fields, super.generics, super.returnTy,
      super.isVar, this.implFn);
  late ImplFnMixin implFn;

  @override
  Ty? getTy(Tys<LifeCycleVariable> c, Identifier ident) {
    final ty = super.getTy(c, ident);
    if (ty != null) {
      return ty;
    }
    return implFn.implty.getTy(c, ident);
  }

  @override
  ImplFnDecl clone() {
    return ImplFnDecl._(
        ident, fields.clone(), generics, _returnTy, isVar, implFn);
  }

  @override
  ImplFnDecl copyWith(List<FieldDef> newFields) {
    return ImplFnDecl._(ident, newFields, generics, _returnTy, isVar, implFn);
  }
}

class Fn extends Ty {
  Fn(this._fnDecl, this.block);

  Identifier get fnName => _fnDecl.ident;

  @override
  Identifier get ident => fnName;

  List<FieldDef> get fields => _fnDecl.fields;

  List<GenericDef> get generics => _fnDecl.generics;

  @override
  bool get extern => _fnDecl.extern;

  @override
  set extern(bool v) {
    super.extern = v;
    _fnDecl.extern = v;
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block?.incLevel(count);
  }

  @protected
  final FnDecl _fnDecl;
  final Block? block;

  FnDecl get baseFnDecl => _fnDecl;

  @override
  String toString() {
    var b = '';
    if (block != null) {
      b = ' $block';
    }
    return '$pad$_fnDecl$b';
  }

  @override
  late final props = [_fnDecl, block, _constraints];

  bool isVoidRet(Tys c) => _fnDecl.isVoidRet(c);

  Ty getRetTy(Tys c) => _fnDecl.getRetTy(c);

  Ty? getRetTyOrT(Tys c) => _fnDecl.getRetTyOrT(c);

  @override
  Fn clone() {
    return Fn(_fnDecl.clone(), block)..copy(this);
  }

  Fn resolveGeneric(Tys context, List<FieldExpr> params) {
    var newFnDecl = _fnDecl.resolveGeneric(context, params);

    return Fn(newFnDecl, block)..copy(this);
  }

  late final _cache = <ListKey, Variable>{};

  @override
  void prepareBuild(FnBuildMixin context, {bool push = true}) {
    super.prepareBuild(context);
    // _depFns = null;
    if (push) context.pushFn(fnName, this);
  }

  Fn? _parent;
  Fn get parentOrCurrent => _parent ?? this;
  void copy(Fn from) {
    _parent = from.parentOrCurrent;
    variables = from.variables;
    _buildContext = from.currentContext;
    _analysisContext = from.analysisContext;
  }

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ?? _parent?.currentContext;

  Variable genFn({FnDecl? fnDecl, bool ignoreFree = false}) {
    final context = currentContext ?? parentOrCurrent.currentContext!;
    FnDecl decl = fnDecl ?? _fnDecl;

    late final allCatchs = <Variable>[];

    for (var val in variables) {
      final variable = context.getVariable(val.ident);
      if (variable != null) {
        allCatchs.add(variable);
      }
    }

    if (allCatchs.isNotEmpty) {
      decl = decl.toCatch(allCatchs, variables.toList());
    }

    final key = ListKey([getKey(), decl]);

    final fn = parentOrCurrent._cache[key];

    if (fn != null) {
      return LLVMConstVariable(fn.getBaseValue(context), decl, ident);
    }

    final fnValue = AbiFn.createFunction(context, this, decl);
    parentOrCurrent._cache[key] = fnValue;

    context.buildFnBB(this, decl,
        fnValue: fnValue.value, ignoreFree: ignoreFree);

    return fnValue;
  }

  void pushTyGenerics(Tys context, FnDecl fnDecl) {
    context.pushDyTys(fnDecl.tys);
  }

  Object? getKey() {
    return null;
  }

  Set<AnalysisVariable> variables = {};

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
    pushTyGenerics(child, _fnDecl);

    child.setFnContext(this);
    _fnDecl.analysisFn(child);
    analysisStart(child);
    block?.analysis(child, hasRet: true);
    variables = {...child.catchVariables, ...child.childrenVariables};
  }

  @override
  LLVMType get llty => throw UnimplementedError('use FnDecl');

  late final fnWrap = FnWrap(this);
}

mixin ImplFnMixin on Fn {
  ImplTy get implty;
  Ty get ty => implty.ty!;
  bool get isStatic;

  late final _fnList = <ImplTy, ImplFnMixin>{};

  ImplFnMixin? getWith(ImplTy ty) {
    final parent = parentOrCurrent as ImplFnMixin;
    if (parent.implty == ty) return parent;
    return parent._fnList.putIfAbsent(ty, () => newWithImplTy(ty));
  }

  ImplFnMixin newWithImplTy(ImplTy ty);

  @override
  void pushTyGenerics(Tys context, FnDecl fnDecl) {
    super.pushTyGenerics(context, fnDecl);
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
}

class ImplFn extends Fn with ImplFnMixin {
  ImplFn(ImplFnDecl super.fnDecl, super.block, this.implty, this.isStatic) {
    _fnDecl.implFn = this;
  }

  factory ImplFn.decl(FnDecl fnDecl, Block? block, ImplTy implty,
      [bool isStatic = false]) {
    final fn = ImplFn(fnDecl._toImpl(), block, implty, isStatic);
    return fn;
  }

  @override
  final bool isStatic;

  @override
  final ImplTy implty;

  @override
  ImplFnDecl get _fnDecl => super._fnDecl as ImplFnDecl;

  @override
  ImplFn newWithImplTy(ImplTy ty) {
    return ImplFn(_fnDecl.clone(), block, ty, isStatic)..copy(this);
  }

  @override
  ImplFn resolveGeneric(Tys context, List<FieldExpr> params) {
    final newFnDecl = _fnDecl.resolveGeneric(context, params) as ImplFnDecl;
    return ImplFn(newFnDecl, block, implty, isStatic)..copy(this);
  }

  @override
  void analysisStart(AnalysisContext context) {
    final ident = Identifier.self;
    final ty = implty.ty;
    if (ty == null) return;
    context.pushNew(context.createVal(ty, ident));
  }
}

class FnClosure extends FnDecl {
  FnClosure(
      super.ident, super.fields, super.generics, super.returnTy, super.isVar);

  @override
  FnClosure clone() {
    return FnClosure(ident, fields.clone(), generics, _returnTy, isVar)
      .._tys = _tys
      .._parent = parentOrCurrent;
  }

  @override
  // ignore: overridden_fields
  late final LLVMFnClosureType llty = LLVMFnClosureType(this);

  @override
  FnClosure newTy(List<FieldDef> fields) {
    return FnClosure(ident, fields, generics, _returnTy, isVar);
  }

  @override
  FnClosure toDyn() {
    return this;
  }
}

class FnCatch extends FnDecl {
  FnCatch._(super.ident, super.fields, super.generics, super.returnTy,
      super.isVar, this.analysisVariables, this._variables);

  FnCatch newVariables(List<Variable> variables) {
    return FnCatch._(ident, fields.clone(), generics, _returnTy, isVar,
        analysisVariables, variables);
  }

  List<Variable> getVariables() => _variables;

  static Variable? toFnClosure(FnBuildMixin context, Ty? ty, Variable val) {
    if (val.ty case FnDecl vTy when ty is FnClosure && vTy is! FnClosure) {
      final newTy = vTy.toDyn();
      final fnCatch = vTy is FnCatch ? vTy : vTy.toCatch(const [], const []);
      return context.root.createClosureBase(context, fnCatch, newTy, val);
    }

    return null;
  }

  final List<AnalysisVariable> analysisVariables;
  final List<Variable> _variables;

  @override
  FnDecl copyWith(List<FieldDef> newFields) {
    return FnCatch._(ident, newFields, generics, _returnTy, isVar,
        analysisVariables, _variables);
  }

  @override
  FnCatch clone() {
    return FnCatch._(ident, fields.clone(), generics, _returnTy, isVar,
        analysisVariables, _variables);
  }

  @override
  // ignore: overridden_fields
  late final props = [super.props, ...analysisVariables.map((e) => e.ty)];

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    final dyn = isDyn ? 'dyn ' : '';
    return '${dyn}fn $ident${generics.str}(${fields.join(',')}$isVals) -> ${_returnTy ?? 'void'}${tys.str}: {${analysisVariables.join(',')}}';
  }
}
