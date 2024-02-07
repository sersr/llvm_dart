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

  @override
  bool isTy(Ty? other) {
    return this == other;
  }

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
  String toString() {
    final isVals = isVar ? ', ...' : '';
    return 'fn $ident${generics.str}(${fields.join(',')}$isVals) -> ${_returnTy ?? 'void'}${tys.str}';
  }

  @override
  late final props = [ident.toRawIdent, fields, _returnTy, _tys];

  void analysisFn(AnalysisContext context) {
    for (var p in fields) {
      final t = getFieldTyOrT(context, p) ?? AnalysisTy(p.rawTy);
      context.pushVariable(
        context.createVal(t, p.ident, p.rawTy.kind)..lifecycle.isOut = true,
      );
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

  FnClosure toClosure(List<Variable> variable) {
    final list = <FieldDef>[];
    list.add(FieldDef.newDef(
        'fn'.ident, PathTy.none, RefTy.pointer(LiteralKind.kVoid.ty)));

    for (var val in variable) {
      final field = FieldDef.newDef(val.ident, PathTy.none, val.ty);
      list.add(field);
    }

    return FnClosure(ident, fields, generics, _returnTy, isVar, list)
      .._tys = tys
      .._parent = parentOrCurrent;
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

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block?.incLevel(count);
  }

  final FnDecl _fnDecl;
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

    return '$pad$ext$fnDecl$b';
  }

  @override
  late final props = [_fnDecl, block, _constraints];

  @override
  Fn clone() {
    return Fn(fnDecl, block)..copy(this);
  }

  Fn resolveGeneric(Tys context, List<FieldExpr> params) {
    final newFnDecl = fnDecl.resolveGeneric(context, params);
    return Fn(newFnDecl, block)..copy(this);
  }

  late final _cache = <ListKey, Variable>{};

  @override
  void prepareBuild(FnBuildMixin context, {bool push = true}) {
    super.prepareBuild(context);
    if (push) context.pushFn(fnName, this);
  }

  Fn? _parent;
  Fn get parentOrCurrent => _parent ?? this;
  void copy(Fn from) {
    _parent = from.parentOrCurrent;
    selfVariables = from.selfVariables;
    _get = from._get;
    _buildContext = from.currentContext;
    _analysisContext = from.analysisContext;
  }

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ?? _parent?.currentContext;

  FnDecl get fnDecl => _closure ?? _fnDecl;
  FnDecl? _closure;

  Variable genFn([bool ignoreFree = false]) {
    final context = currentContext ?? parentOrCurrent.currentContext!;
    FnDecl decl = fnDecl;

    final allCatchs = <Variable>[];

    for (var val in variables) {
      final variable = context.getVariable(val.ident);
      if (variable != null) {
        allCatchs.add(variable);
      }
    }

    if (allCatchs.isNotEmpty) {
      decl = fnDecl.toClosure(allCatchs);
    }
    _closure = decl;

    final key = ListKey([getKey(), decl]);

    var fn = parentOrCurrent._cache[key];
    if (fn != null) {
      if (decl is FnClosure) {
        fn = decl.llty.wrapFn(context, fn, allCatchs);
      }
      return fn;
    }

    final fnValue = AbiFn.createFunction(context, this);
    if (decl is FnClosure) {
      fn = decl.llty.wrapFn(context, fnValue, allCatchs);
    } else {
      fn = fnValue;
    }

    parentOrCurrent._cache[key] = fnValue;

    context.buildFnBB(this, fnValue: fnValue.value, ignoreFree: ignoreFree);

    return fn;
  }

  void pushTyGenerics(Tys context) {
    context.pushDyTys(fnDecl.tys);
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
    _fnDecl.analysisFn(child);
    analysisStart(child);
    block?.analysis(child, hasRet: true);
    selfVariables = child.catchVariables;
    _get = () => child.childrenVariables;
  }

  @override
  late final LLVMFnType llty = LLVMFnType(this);
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
}

class ImplFn extends Fn with ImplFnMixin {
  ImplFn(ImplFnDecl super.fnDecl, super.block, this.implty, this.isStatic) {
    fnDecl.implFn = this;
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
  ImplFnDecl get fnDecl => super.fnDecl as ImplFnDecl;

  @override
  ImplFn newWithImplTy(ImplTy ty) {
    return ImplFn(fnDecl.clone(), block, ty, isStatic)..copy(this);
  }

  @override
  ImplFn resolveGeneric(Tys context, List<FieldExpr> params) {
    final newFnDecl = fnDecl.resolveGeneric(context, params) as ImplFnDecl;
    return ImplFn(newFnDecl, block, implty, isStatic)..copy(this);
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

class FnClosure extends FnDecl {
  FnClosure(super.ident, super.fields, super.generics, super.returnTy,
      super.isVar, this.catchVariables);

  final List<FieldDef> catchVariables;

  @override
  FnClosure clone() {
    return FnClosure(ident, fields.clone(), generics, _returnTy, isVar,
        catchVariables.clone())
      .._tys = _tys
      .._parent = parentOrCurrent;
  }

  @override
  // ignore: overridden_fields
  late final LLVMFnClosureType llty = LLVMFnClosureType(this);

  @override
  // ignore: overridden_fields
  late final props = [super.props, catchVariables];

  @override
  FnClosure newTy(List<FieldDef> fields) {
    return FnClosure(
        ident, fields, generics, _returnTy, isVar, catchVariables.clone());
  }
}

class LLVMFnClosureType extends LLVMFnDeclType {
  LLVMFnClosureType(FnClosure super.ty);

  @override
  FnClosure get ty => super.ty as FnClosure;

  LLVMTypeRef? _type;
  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    if (_type != null) return _type!;
    final vals = <LLVMTypeRef>[];
    for (var field in ty.catchVariables) {
      vals.add(field.grt(c).typeOf(c));
    }

    return _type = c.typeStruct(vals, 'Fn_closure');
  }

  @override
  int getBytes(StoreLoadMixin c) {
    var size = 0;
    for (var field in ty.catchVariables) {
      size += field.grt(c).llty.getBytes(c);
    }

    return size;
  }

  @override
  LLVMTypeRef createFnType(StoreLoadMixin context) {
    final decl = ty;
    final fields = decl.fields;
    final list = <LLVMTypeRef>[];
    var retTy = decl.getRetTy(context);
    list.add(typeOf(context));

    for (var p in fields) {
      final realTy = ty.getFieldTy(context, p);
      LLVMTypeRef type = realTy.typeOf(context);

      list.add(type);
    }
    final ret = retTy.typeOf(context);

    return context.typeFn(list, ret, ty.isVar);
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final name = 'Fn_closure';

    final elements = <LLVMMetadataRef>[];
    final fields = ty.catchVariables;
    final file = llvm.LLVMDIScopeGetFile(c.scope);

    var start = 0;
    for (var field in fields) {
      var rty = field.grt(c);
      LLVMMetadataRef ty;

      ty = rty.llty.createDIType(c);
      final alignSize = rty.llty.getBytes(c) * 8;

      final fieldName = field.ident.src;

      final (namePointer, nameLength) = fieldName.toNativeUtf8WithLength();

      ty = llvm.LLVMDIBuilderCreateMemberType(
        c.dBuilder!,
        c.scope,
        namePointer,
        nameLength,
        file,
        field.ident.offset.row,
        alignSize,
        alignSize,
        start,
        0,
        ty,
      );
      elements.add(ty);
      start += alignSize;
    }
    final (namePointer, nameLength) = name.toNativeUtf8WithLength();

    var alignSize = fields.fold<int>(0, (previousValue, element) {
      final size = element.grt(c).llty.getBytes(c);
      if (previousValue > size) return previousValue;
      return size;
    });

    return llvm.LLVMDIBuilderCreateStructType(
      c.dBuilder!,
      c.scope,
      namePointer,
      nameLength,
      llvm.LLVMDIScopeGetFile(c.unit),
      12,
      getBytes(c) * 8,
      alignSize * 8,
      0,
      nullptr,
      elements.toNative(),
      elements.length,
      0,
      nullptr,
      '0'.toChar(),
      1,
    );
  }

  Variable wrapFn(StoreLoadMixin c, Variable fn, List<Variable> variables) {
    final alloca = createAlloca(c, Identifier.none);
    final type = typeOf(c);

    for (var i = 0; i < ty.catchVariables.length; i++) {
      final ptr = alloca.getBaseValue(c);
      final fieldTy = ty.catchVariables[i].grt(c);
      final value = llvm.LLVMBuildStructGEP2(c.builder, type, ptr, i, unname);
      final field = LLVMAllocaVariable(
          value, fieldTy, fieldTy.typeOf(c), Identifier.none);
      if (i == 0) {
        field.store(c, fn.load(c));
        continue;
      }
      final val = variables[i - 1];
      field.store(c, val.load(c));
    }

    return alloca;
  }

  void pushVariables(FnBuildMixin context, LLVMValueRef fn) {
    final fnWrap = llvm.LLVMGetParam(fn, 0);
    final type = typeOf(context);
    final alloca = createAlloca(context, Identifier.none);
    alloca.store(context, fnWrap);

    for (var i = 1; i < ty.catchVariables.length; i++) {
      final item = ty.catchVariables[i];
      final fieldTy = item.grt(context);
      final value = llvm.LLVMBuildStructGEP2(
          context.builder, type, alloca.alloca, i, unname);
      final field = LLVMAllocaVariable(
          value, fieldTy, fieldTy.typeOf(context), item.ident);

      context.pushVariable(field);
    }
  }

  LLVMValueRef load(FnBuildMixin context, Variable fn) {
    final ptr = fn.getBaseValue(context);
    final type = typeOf(context);
    final value =
        llvm.LLVMBuildStructGEP2(context.builder, type, ptr, 0, unname);

    final item = ty.catchVariables[0];

    final fieldTy = item.grt(context);
    final field =
        LLVMAllocaVariable(value, fieldTy, fieldTy.typeOf(context), item.ident);

    return field.load(context);
  }
}
