import 'dart:async';

import 'package:equatable/equatable.dart';

import 'ast.dart';

abstract class LifeCycleVariable {
  Identifier? ident;

  Identifier? lifeEnd;

  Identifier? get lifeCycyle => lifeEnd ?? ident;

  void updateLifeCycle(Identifier ident) {
    if (lifeEnd == null) {
      lifeEnd = ident;
      return;
    }
    if (ident.start >= lifeEnd!.start) {
      lifeEnd = ident;
    }
  }
}

class ImportPath with EquatableMixin {
  ImportPath(this.name);
  final Identifier name;

  @override
  List<Object?> get props => [name];

  @override
  String toString() {
    return name.toString();
  }
}

typedef ImportHandler = Tys Function(Tys, ImportPath);
typedef RunImport<T> = T Function(T Function());

abstract class GlobalContext {
  Tys import(Tys current, ImportPath path);
  V? getVariable<V>(Identifier ident);
  VA? getKVImpl<K, VA, T>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test});
}

mixin Tys<V extends LifeCycleVariable> {
  Tys defaultImport();
  String? currentPath;
  late GlobalContext importHandler;

  final imports = <ImportPath, Tys>{};

  R? runImport<R>(R Function() body) {
    if (_runImport) return null;
    return runZoned(body, zoneValues: {#_runImport: true});
  }

  // ImportHandler? importHandler;

  // ImportHandler? getImportHandler() {
  //   if (importHandler != null) return importHandler!;
  //   return parent?.getImportHandler();
  // }

  void pushImport(ImportPath path, {Identifier? name}) {
    if (!imports.containsKey(path)) {
      final im = importHandler.import(this, path);
      imports[path] = im;
      initImportContext(im);
    }
  }

  void initImportContext(covariant Tys child) {}

  final variables = <Identifier, List<V>>{};

  bool get _runImport {
    return Zone.current[#_runImport] == true;
  }

  V? getVariable(Identifier ident) =>
      getVariableImpl(ident) ?? importHandler.getVariable(ident);

  V? getVariableImpl(Identifier ident) {
    final list = variables[ident];
    if (list != null) {
      var last = list.last;
      // ignore: invalid_use_of_protected_member
      if (last.ident!.data != ident.data) {
        return last;
      }
      for (var val in list) {
        final valIdent = val.ident!;
        if (valIdent.start > ident.start) {
          break;
        }
        if (valIdent.start == ident.start) {
          return val;
        }
        last = val;
      }
      last.updateLifeCycle(ident);
      return last;
    }

    final v = runImport(() {
      for (var imp in imports.values) {
        final v = imp.getVariable(ident);
        if (v != null) {
          v.updateLifeCycle(ident);
          return v;
        }
      }
    });

    return v as V?;
  }

  void pushVariable(Identifier ident, covariant V variable,
      {bool isAlloca = true}) {
    final list = variables.putIfAbsent(ident, () => []);
    if (!list.contains(variable)) {
      variable.ident = ident;
      if (list.isEmpty) {
        list.add(variable);
      } else {
        final index = list.indexWhere((e) => e.ident!.start > ident.start);
        if (index == -1) {
          list.add(variable);
        } else {
          list.insert(index, variable);
        }
      }
    }
  }

  bool _contain(Iterable<List<Ty>> i, Ty ty) {
    return i.any((element) => element.contains(ty));
  }

  bool contains(Ty ty) {
    var result = _contain(structs.values, ty);
    if (!result) {
      result = _contain(enums.values, ty);
    }
    if (!result) {
      result = _contain(impls.values, ty);
    }
    if (!result) {
      result = _contain(components.values, ty);
    }

    return result;
  }

  // 当前范围内可获取的 struct
  final structs = <Identifier, List<StructTy>>{};
  StructTy? getStruct(Identifier ident) {
    return getKV(ident, (c) => c.structs, handler: (c) => c.getStruct(ident));
  }

  void pushStruct(Identifier ident, StructTy ty) {
    pushKV(ident, ty, structs);
  }

  final enums = <Identifier, List<EnumTy>>{};
  EnumTy? getEnum(Identifier ident) {
    return getKV(ident, (c) => c.enums, handler: (c) => c.getEnum(ident));
  }

  void pushEnum(Identifier ident, EnumTy ty) {
    if (pushKV(ident, ty, enums)) {
      ty.push(this);
    }
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    return getKV(ident, (c) => c.fns, handler: (c) {
      return c.getFn(ident);
    });
  }

  void pushFn(Identifier ident, Fn fn) {
    pushKV(ident, fn, fns);
  }

  final components = <Identifier, List<ComponentTy>>{};
  ComponentTy? getComponent(Identifier ident) {
    return getKV(ident, (c) => c.components,
        handler: (c) => c.getComponent(ident));
  }

  void pushComponent(Identifier ident, ComponentTy com) {
    pushKV(ident, com, components);
  }

  final impls = <Identifier, List<ImplTy>>{};
  ImplTy? getImpl(Identifier ident) {
    return getKV(ident, (c) => c.impls, handler: (c) {
      return c.getImpl(ident);
    });
  }

  void pushImpl(Identifier ident, ImplTy ty) {
    pushKV(ident, ty, impls);
  }

  final implForStructs = <Ty, List<ImplTy>>{};
  ImplTy? getImplForStruct(Ty structTy, Identifier ident) {
    ImplTy? cache;
    if (structTy is StructTy) {
      structTy = structTy.parentOrCurrent;
    }
    final v = getKV(structTy, (c) => c.implForStructs,
        handler: (c) => c.getImplForStruct(structTy, ident),
        test: (v) {
          Ty? ty = v.struct.grtOrT(this, getTy: getStruct);

          bool? isRealTy;
          if (ty is StructTy && structTy is StructTy) {
            if (ty.tys.isNotEmpty && structTy.tys.isNotEmpty) {
              for (var index = 0; index < ty.generics.length; index += 1) {
                final g = structTy.generics[index].ident;
                final gTy = structTy.tys[g];
                final gg = ty.generics[index].ident;
                final ggTy = ty.tys[gg];
                if (gTy == ggTy) {
                  isRealTy = true;
                } else {
                  isRealTy = false;
                  break;
                }
              }
            }
          }
          if (isRealTy == false) {
            return false;
          }

          final contains = v.contains(ident);

          if (isRealTy == true && contains) {
            cache = v;
          }

          return contains;
        });
    return cache ?? v;
  }

  void pushImplForStruct(Ty structTy, ImplTy ty) {
    if (structTy is StructTy) {
      structTy = structTy.parentOrCurrent;
    }
    pushKV(structTy, ty, implForStructs);
  }

  final cTys = <Identifier, List<TypeAliasTy>>{};

  TypeAliasTy? getCty(Identifier ident) {
    return getKV(ident, (c) => c.cTys, handler: (c) {
      return c.getCty(ident);
    });
  }

  void pushCty(Identifier ident, TypeAliasTy ty) {
    pushKV(ident, ty, cTys);
  }

  final _dyTys = <Identifier, List<Ty>>{};

  Ty? getDyTy(Identifier ident) {
    return getKV(ident, (c) => c._dyTys, handler: (c) {
      return c.getCty(ident);
    });
  }

  void pushDyTy(Identifier ident, Ty ty) {
    pushKV(ident, ty, _dyTys);
  }

  void pushDyTys(Map<Identifier, Ty> all) {
    for (var MapEntry(:key, :value) in all.entries) {
      pushKV(key, value, _dyTys);
    }
  }

  void pushAllTy(Map<Object, Ty> all) {
    final impls = all.values.whereType<ImplTy>();
    for (var ty in all.values) {
      if (ty is StructTy) {
        pushStruct(ty.ident, ty);
      } else if (ty is Fn) {
        pushFn(ty.fnSign.fnDecl.ident, ty);
      } else if (ty is EnumTy) {
        pushEnum(ty.ident, ty);
      } else if (ty is ComponentTy) {
        pushComponent(ty.ident, ty);
      } else if (ty is ImplTy) {
        pushImpl(ty.struct.ident, ty);
      } else if (ty is TypeAliasTy) {
        pushCty(ty.ident, ty);
      } else {
        print('unknown ty {${ty.runtimeType}}');
      }
    }
    for (var impl in impls) {
      final struct = impl.struct.grtOrT(this);
      if (struct != null) {
        pushImplForStruct(struct, impl);
        impl.initStructFns(this);
      }
    }
  }

  Ty? getTy(Identifier i) {
    return getStruct(i) ??
        getComponent(i) ??
        getImpl(i) ??
        getFn(i) ??
        getEnum(i) ??
        getCty(i) ??
        getDyTy(i);
  }

  Ty? getTyIgnoreImpl(Identifier i) {
    return getStruct(i) ?? getFn(i) ?? getEnum(i) ?? getCty(i);
  }

  void errorExpr(UnknownExpr unknownExpr) {}

  VA? getKV<K, VA>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return getKVImpl(k, map, handler: handler, test: test) ??
        importHandler.getKVImpl<K, VA, V>(k, map, handler: handler, test: test);
  }

  VA? getKVImpl<K, VA>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    final list = map(this)[k];
    final hasTest = test != null;

    if (list != null) {
      for (var item in list.reversed) {
        if (hasTest && !test(item)) continue;

        return item;
      }
    }
    if (handler != null) {
      final v = runImport(() {
        for (var imp in imports.values) {
          final v = handler(imp);
          if (v != null) {
            if (hasTest && !test(v)) continue;

            return v;
          }
        }
        return null;
      });
      if (v != null) {
        return v;
      }
    }
    return null;
    // return parent?.getKV(k, map, importHandle: importHandle, test: test);
  }

  bool pushKV<K, VA>(K k, VA v, Map<K, List<VA>> map) {
    final list = map.putIfAbsent(k, () => []);
    if (!list.contains(v)) {
      list.add(v);
      return true;
    }
    return false;
  }
}

typedef ImportKV<VA> = VA? Function(Tys c);
