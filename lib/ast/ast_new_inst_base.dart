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
  List<Object?> get props => [constraints, ident];
}

/// 字段定义
///
/// 函数，结构体的字段格式
class FieldDef with EquatableMixin implements Clone<FieldDef> {
  FieldDef(this.ident, this._ty) : _rty = null;
  FieldDef._internal(this.ident, this._ty, this._rty);
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
    return FieldDef._internal(ident, _ty, _rty);
  }

  List<PointerKind> get kinds => _ty.kind;
  @override
  String toString() {
    if (!ident.isValid) {
      return '$_ty';
    }
    return '$ident: $_ty';
  }

  @override
  List<Object?> get props => [_rty, _ty, ident];
}

typedef GenTy = Ty? Function(Identifier ident);

mixin NewInst<T extends Ty> on Ty {
  List<FieldDef> get fields;
  List<GenericDef> get generics;

  Map<Identifier, Ty>? _tys;

  Map<Identifier, Ty> get tys => _tys ?? const {};

  bool get done => tys.length >= generics.length;

  final _tyLists = <ListKey, T>{};

  T? _parent;
  T get parentOrCurrent => _parent ?? this as T;

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ?? _parent?.currentContext;

  @override
  bool isTy(Ty? other) {
    if (other is NewInst) {
      return other.parentOrCurrent == parentOrCurrent;
    }
    return super.isTy(other);
  }

  @override
  Ty newConstraints(Tys c, List<ComponentTy> newConstraints, bool isLimited) {
    final ty = super.newConstraints(c, newConstraints, isLimited) as NewInst;
    ty._initData(c, parentOrCurrent, tys);
    return ty;
  }

  _initData(Tys c, T parent, Map<Identifier, Ty> tys) {
    _parent = parent;
    if (tys.isNotEmpty) _tys = tys;
    // init ty
    for (var fd in fields) {
      getFieldTyOrT(c, fd);
    }
  }

  /// todo: 使用 `context.pushDyty` 实现
  T newInst(Map<Identifier, Ty> tys, Tys c) {
    final parent = parentOrCurrent;
    if (tys.isEmpty) return this as T;
    final key = ListKey(tys);

    final newInst = (parent as NewInst)._tyLists.putIfAbsent(key, () {
      final newFields = fields.clone();

      final ty = newTy(newFields);
      (ty as NewInst)._initData(c, parent, tys);
      return ty;
    });

    return newInst as T;
  }

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

  static bool resolve(Tys c, Ty exactTy, PathTy pathTy,
      List<GenericDef> generics, Map<Identifier, Ty> genMapTy, bool isLimited) {
    bool result = true;
    // x: Arc<Gen<T>> => Gen<T> => T
    //
    // fn hello<T>(y: T);
    //
    // hello(y: 1000);
    // ==> exactTy: i32; pathTy: T
    //
    // fn foo<T>(x: Gen<T>);
    //
    // foo(x: Gen<i32> { foo: 1000 } );
    // ==> exactTy: Gen<i32>; pathTy: Gen<T>
    void visitor(Ty exactTy, PathTy pathTy) {
      ComponentTy? checkTy(Ty exactTy, PathTy pathTy) {
        ComponentTy? tyConstraint;

        final tryTy = c.runIgnoreImport(() => pathTy.getBaseTy(c));
        var generics = const <GenericDef>[];
        var tys = const <Identifier, Ty>{};

        if (tryTy is TypeAliasTy) {
          final alias = tryTy.aliasTy;

          // 从[TypeAlaisTy] 中获取基本类型
          final newMap = <Identifier, Ty>{};
          result =
              resolve(c, exactTy, alias, tryTy.generics, newMap, isLimited);
          if (!result) return null;
          assert(newMap.length == pathTy.genericInsts.length);
          generics = tryTy.generics;
          tys = newMap;
        } else if (exactTy is NewInst) {
          generics = exactTy.generics;
          tys = exactTy.tys;

          if (tryTy is! NewInst ||
              tryTy.parentOrCurrent != exactTy.parentOrCurrent) {
            result = false;
            return null;
          }
        } else if (tryTy is ComponentTy) {
          /// exactTy不支持泛型如: i32 , i64 ...
          final currentImplTy =
              c.runIgnoreImport(() => c.getImplWith(exactTy, comTy: tryTy));
          final com = currentImplTy?.comTy;

          if (com?.parentOrCurrent != tryTy.parentOrCurrent) {
            result = false;
            return null;
          }
          tyConstraint = com;

          generics = com!.generics;
          tys = com.tys;
        }

        /// 除了[TypeAliasTy]泛型个数必须一致
        if (pathTy.genericInsts.length != generics.length) {
          result = false;
          return null;
        }

        for (var i = 0; i < pathTy.genericInsts.length; i += 1) {
          final genericInst = pathTy.genericInsts[i];
          final ty = tys[generics[i].ident];
          if (ty != null) visitor(ty, genericInst);
        }

        return tyConstraint;
      }

      exactTy = pathTy.kind.unWrapRefTy(exactTy);

      final currentGenField =
          generics.firstWhereOrNull((e) => e.ident == pathTy.ident);
      if (currentGenField != null) {
        // fn bar<T, X: Bar<T>>(x: X);
        // 处理泛型内部依赖，X已知晓，处理T

        genMapTy.putIfAbsent(pathTy.ident, () {
          final list = <ComponentTy>[];
          for (var g in currentGenField.constraints) {
            final com = checkTy(exactTy, g);
            if (com != null) {
              list.add(com);
            }
          }

          return exactTy.newConstraints(c, list, isLimited);
        });
      }

      if (genMapTy.length == generics.length) {
        return;
      }

      // Gen<i32> : Gen<T>
      // 泛型在下一级中
      checkTy(exactTy, pathTy);
    }

    visitor(exactTy, pathTy);

    return result;
  }

  Map<Identifier, Ty> getTysWith(Tys context, List<FieldExpr> params,
      {List<GenericDef> others = const []}) {
    final generics = [...this.generics, ...others];

    if (tys.length >= generics.length) return const {};

    final genMapTy = <Identifier, Ty>{};
    final fields = this.fields.clone();
    final sortFields =
        alignParam(params, (p) => fields.indexWhere((e) => e.ident == p.ident));

    bool isBuild = context is FnBuildMixin;

    Ty? gen(Identifier ident) {
      return genMapTy[ident] ?? tys[ident];
    }

    for (var i = 0; i < sortFields.length; i += 1) {
      final f = sortFields[i];
      if (i >= fields.length) break;
      final fd = fields[i];

      Ty? ty;
      if (isBuild) {
        ty = f.build(context, baseTy: fd.grtOrTUd(context, gen: gen))?.ty;
      } else {
        // fd.grtOrT(context, gen: gen)
        ty = f.analysis(context as AnalysisContext)?.ty;
      }
      if (ty != null) {
        resolve(context, ty, fd.rawTy, generics, genMapTy, false);
      }
    }

    return genMapTy;
  }

  T resolveGeneric(Tys context, List<FieldExpr> params,
      {List<GenericDef> others = const []}) {
    final genMapTy = getTysWith(context, params, others: others);
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
