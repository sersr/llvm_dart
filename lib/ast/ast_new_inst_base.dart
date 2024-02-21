part of 'ast.dart';

class GenericDef with EquatableMixin {
  GenericDef(this.ident, this.constraints);
  final Identifier ident;
  final List<PathTy> constraints;

  List<Ty> getConstraints(Tys c, {GenTy? gen}) {
    final list = <Ty>[];
    for (var pathTy in constraints) {
      final ty = pathTy.grtOrT(c, gen: gen);
      if (ty != null) {
        list.add(ty);
      }
    }

    return list;
  }

  @override
  String toString() {
    if (constraints.isEmpty) {
      return ident.src;
    }

    return '$ident: ${constraints.join(' + ')}';
  }

  @override
  late final props = [constraints, ident];
}

/// 字段定义
///
/// 函数，结构体的字段格式
class FieldDef with EquatableMixin implements Clone<FieldDef> {
  FieldDef(this.ident, this._ty) : _rty = null;
  FieldDef.newDef(this.ident, this._ty, this._rty);
  final Identifier ident;
  final PathTy _ty;
  PathTy get rawTy => _ty;
  final Ty? _rty;
  Ty? _cache;

  Ty grt(Tys c) => grtOrT(c)!;

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    return _rty ?? (_cache ??= _ty.grtOrT(c, gen: gen));
  }

  Ty? grtOrTUd(Tys c, {GenTy? gen}) {
    return _rty ?? _ty.grtOrT(c, gen: gen);
  }

  @override
  FieldDef clone() {
    return FieldDef.newDef(ident, _ty, _rty);
  }

  @override
  String toString() {
    if (!ident.isValid) {
      return '$_ty';
    }
    return '$ident: $_ty';
  }

  @override
  late final props = [_rty, _ty.ident, _ty.genericInsts, _ty.kind, ident];
}

typedef GenTy = Ty? Function(Identifier ident);

mixin NewInst<T extends Ty> on Ty {
  List<FieldDef> get fields;
  List<GenericDef> get generics;

  Map<Identifier, Ty>? _tys;

  Map<Identifier, Ty> get tys => _tys ?? const {};

  bool get done => tys.length >= generics.length;

  T? _parent;
  T get parentOrCurrent => _parent ?? this as T;

  @override
  bool get extern => _parent?.extern ?? super.extern;

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ?? _parent?.currentContext;

  @override
  AnalysisContext? get analysisContext =>
      super.analysisContext ?? _parent?.analysisContext;

  @override
  bool isTy(Ty? other) {
    if (other is NewInst) {
      return other.parentOrCurrent == parentOrCurrent;
    }
    return super.isTy(other);
  }

  @override
  void cloneTys(Tys c, covariant NewInst<T> parent) {
    _initData(c, parent.parentOrCurrent, parent.tys);
  }

  _initData(Tys c, T parent, Map<Identifier, Ty> tys) {
    _parent = parent;
    if (tys.isNotEmpty) _tys = tys;

    for (var fd in fields) {
      getFieldTyOrT(c, fd);
    }
  }

  T newInst(Map<Identifier, Ty> tys, Tys c) {
    final parent = parentOrCurrent;

    final newFields = fields.clone();

    final ty = newTy(newFields);
    (ty as NewInst)._initData(c, parent, tys);
    ty.initNewInst(c);
    return ty;
  }

  void initNewInst(Tys c) {}

  /// 从泛型实体获取map
  ///
  /// struct Box<S,T> {
  ///  ...
  /// }
  ///
  /// fn main() {
  ///   let box = Box<i32, i64>{ ... };
  /// }
  ///
  /// generics    : <S  , T  >
  ///
  /// genericInsts: <i32, i64>
  ///
  ///  => map: {S: i32, T: i64 }
  static Map<Identifier, Ty> getTysFromGenericInsts(
    Tys c,
    List<PathTy> genericInsts,
    List<GenericDef> generics, {
    Ty? Function(Identifier ident)? gen,
  }) {
    final types = <Identifier, Ty>{};

    if (genericInsts.length != generics.length && gen == null) return types;

    for (var i = 0; i < genericInsts.length; i += 1) {
      final pathTy = genericInsts[i];
      final generic = generics[i];
      final gty = pathTy.grtOrT(c, gen: gen);
      if (gty != null) {
        types[generic.ident] = gty;
      }
    }

    if (gen != null) {
      for (var generic in generics) {
        final ty = gen(generic.ident);
        if (ty != null) {
          types[generic.ident] = ty;
        }
      }
    }

    return types;
  }

  T newInstWithGenerics(
      Tys c, List<PathTy> genericInsts, List<GenericDef> generics,
      {GenTy? gen}) {
    final types = getTysFromGenericInsts(c, genericInsts, generics, gen: gen);

    return newInst(types, c);
  }

  static (bool, Ty?) checkTy(Tys c, Ty exactTy, PathTy pathTy,
      List<GenericDef> generics, Map<Identifier, Ty> genMapTy, bool isLimited) {
    if (pathTy is SlicePathTy) {
      if (exactTy is! SliceTy) return (false, null);

      final elementTy = pathTy.elementTy.grtOrT(c);

      if (elementTy == null) {
        final result = resolve(c, exactTy.elementTy, pathTy.elementTy, generics,
            genMapTy, isLimited);
        if (!result) return (false, null);
      } else if (!exactTy.elementTy.isTy(elementTy)) {
        return (false, null);
      }

      if (pathTy is ArrayPathTy && exactTy is ArrayTy) {
        final constSize = pathTy.size.grtOrT(c);
        if (constSize == null) {
          final result = resolve(
              c, exactTy.sizeTy, pathTy.size, generics, genMapTy, isLimited);
          return (result, null);
        } else if (constSize != exactTy.sizeTy) {
          return (false, null);
        }
      }

      return (true, null);
    }

    Ty? tyConstraint;

    final pathBaseTy = pathTy.getBaseTy(c);
    tyConstraint = pathBaseTy;

    var pathGenerics = const <GenericDef>[];
    var tys = const <Identifier, Ty>{};

    if (pathBaseTy is TypeAliasTy) {
      final alias = pathBaseTy.aliasTy;

      // 从[TypeAlaisTy] 中获取基本类型
      final newMap = <Identifier, Ty>{};
      final result =
          resolve(c, exactTy, alias, pathBaseTy.generics, newMap, isLimited);
      if (!result) return (false, null);
      assert(newMap.length == pathTy.genericInsts.length);
      pathGenerics = pathBaseTy.generics;
      tys = newMap;
    } else if (exactTy is NewInst) {
      pathGenerics = exactTy.generics;
      tys = exactTy.tys;

      if (!exactTy.isTy(pathBaseTy)) {
        if (exactTy is FnDecl && pathBaseTy is FnDecl) {
          return (true, tyConstraint);
        }
        return (false, null);
      }
    } else if (pathBaseTy is ComponentTy) {
      /// exactTy不支持泛型如: i32 , i64 ...
      final currentImplTy = c.getImplWith(exactTy, comTy: pathBaseTy);
      final com = currentImplTy?.comTy;

      if (!pathBaseTy.isTy(com)) {
        return (false, null);
      }

      tyConstraint = com;
      pathGenerics = com!.generics;
      tys = com.tys;
    }

    if (pathTy.genericInsts.length != pathGenerics.length) {
      return (false, null);
    }

    for (var i = 0; i < pathTy.genericInsts.length; i += 1) {
      final genericInst = pathTy.genericInsts[i];
      final ty = tys[pathGenerics[i].ident];
      if (ty != null) {
        final result =
            resolve(c, ty, genericInst, generics, genMapTy, isLimited);
        if (!result) return (false, null);
      }
    }

    return (true, tyConstraint);
  }

  static bool resolve(Tys c, Ty exactTy, PathTy pathTy,
      List<GenericDef> generics, Map<Identifier, Ty> genMapTy, bool isLimited) {
    var result = true;
    exactTy = pathTy.kind.unWrapRefTy(exactTy);

    final currentGenField =
        generics.firstWhereOrNull((e) => e.ident == pathTy.ident);
    if (currentGenField != null) {
      // fn bar<T, X: Bar<T>>(x: X);
      // 处理泛型内部依赖，X已知晓，处理T

      genMapTy.putIfAbsent(pathTy.ident, () {
        final list = <ComponentTy>[];
        var isDyn = false;
        for (var g in currentGenField.constraints) {
          final (r, com) =
              checkTy(c, exactTy, g, generics, genMapTy, isLimited);
          result &= r;
          if (com is ComponentTy) list.add(com);
          if (com is FnDecl) {
            isDyn = com.isDyn || com is FnClosure;
          }
        }

        if (exactTy case Fn(fnDecl: var decl)) {
          if (decl.isDyn || isDyn) {
            return decl.toDyn()..isDyn = true;
          }
          return decl.clone();
        } else if (exactTy case FnDecl decl) {
          if (decl.isDyn || isDyn) {
            return decl.toDyn()..isDyn = true;
          }
          return decl.clone();
        }
        return exactTy.newConstraints(c, list);
      });
    }

    if (genMapTy.length == generics.length) {
      return result;
    }

    if (!result) return result;

    // Gen<i32> : Gen<T>
    // 泛型在下一级中
    return checkTy(c, exactTy, pathTy, generics, genMapTy, isLimited).$1;
  }

  Map<Identifier, Ty> getTysWith(Tys context, List<FieldExpr> params,
      {List<GenericDef> others = const []}) {
    final generics = [...this.generics, ...others];

    if (tys.length >= generics.length) return const {};

    final genMapTy = <Identifier, Ty>{};
    final sortFields = alignParam(params, fields);

    bool isBuild = context is FnBuildMixin;

    Ty? gen(Identifier ident) {
      return genMapTy[ident] ?? tys[ident];
    }

    for (var param in params) {
      final sfIndex = sortFields.indexOf(param);
      assert(sfIndex >= 0);
      final fd = fields[sfIndex];
      Ty? ty;
      if (isBuild) {
        ty = param.build(context, baseTy: fd.grtOrTUd(context, gen: gen))?.ty;
      } else {
        ty = param.analysis(context as AnalysisContext)?.ty;
      }
      if (ty != null) {
        resolve(context, ty, fd.rawTy, generics, genMapTy, false);
      }
    }

    return genMapTy;
  }

  T resolveGeneric(Tys context, List<FieldExpr> params) {
    final genMapTy = getTysWith(context, params);
    if (genMapTy.isEmpty) return this as T;

    return newInst(genMapTy, context);
  }

  @protected
  T newTy(List<FieldDef> fields);

  /// 从[ident]获取[Ty]
  ///
  /// 不直接调用;
  ///
  /// 一般[fields]中的泛型都在[generics]中，
  /// 不过静态函数[ImplStaticFn]可能来源于[StructTy]结构体
  ///
  /// [ImplFnMixin.getTy]
  @mustCallSuper
  Ty? getTy(Tys c, Identifier ident) {
    return tys[ident];
  }

  Ty getFieldTy(Tys c, FieldDef fd) {
    return getFieldTyOrT(c, fd)!;
  }

  Ty? getFieldTyOrT(Tys c, FieldDef fd) {
    return fd.grtOrT(c, gen: (ident) {
      return getTy(c, ident);
    });
  }
}
