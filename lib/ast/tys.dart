import 'dart:async';

import 'package:equatable/equatable.dart';

import '../parsers/lexers/token_kind.dart';
import 'ast.dart';

abstract class IdentVariable {
  Identifier? ident;
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

mixin Tys<T extends Tys<T, V>, V extends IdentVariable> {
  T? get parent;

  T import();
  String? currentPath;

  final imports = <ImportPath, T>{};

  R? runImport<R>(R Function() body) {
    if (_runImport) return null;
    return runZoned(body, zoneValues: {#_runImport: true});
  }

  ImportHandler? importHandler;

  ImportHandler? getImportHandler() {
    if (importHandler != null) return importHandler!;
    return parent?.getImportHandler();
  }

  void pushImport(ImportPath path, {Identifier? name}) {
    if (!imports.containsKey(path)) {
      final im = getImportHandler()?.call(this, path);
      if (im != null) {
        imports[path] = im as T;
      }
    }
  }

  final variables = <Identifier, List<V>>{};

  bool get _runImport {
    return Zone.current[#_runImport] == true;
  }

  V? getVariable(Identifier ident) {
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
      return last;
    }

    final v = runImport(() {
      for (var imp in imports.values) {
        final v = imp.getVariable(ident);
        if (v != null) {
          return v;
        }
      }
    });

    return v ?? parent?.getVariable(ident);
  }

  void pushVariable(Identifier ident, V variable) {
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
    return getKV(ident, (c) => c.structs,
        importHandle: (c) => c.getStruct(ident));
  }

  void pushStruct(Identifier ident, StructTy ty) {
    pushKV(ident, ty, structs);
  }

  final enums = <Identifier, List<EnumTy>>{};
  EnumTy? getEnum(Identifier ident) {
    return getKV(ident, (c) => c.enums, importHandle: (c) => c.getEnum(ident));
  }

  void pushEnum(Identifier ident, EnumTy ty) {
    if (pushKV(ident, ty, enums)) {
      ty.push(this);
    }
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    return getKV(ident, (c) => c.fns, importHandle: (c) {
      return c.getFn(ident);
    });
    // final list = fns[ident];
    // if (list != null) {
    //   return list.last;
    // }

    // final v = runImport(() {
    //   for (var imp in imports.values) {
    //     final v = imp.getFn(ident);
    //     if (v != null) {
    //       return v;
    //     }
    //   }
    // });

    // return v ?? parent?.getFn(ident);
  }

  void pushFn(Identifier ident, Fn fn) {
    pushKV(ident, fn, fns);
  }

  final components = <Identifier, List<ComponentTy>>{};
  ComponentTy? getComponent(Identifier ident) {
    return getKV(ident, (c) => c.components,
        importHandle: (c) => c.getComponent(ident));
  }

  void pushComponent(Identifier ident, ComponentTy com) {
    pushKV(ident, com, components);
  }

  final impls = <Identifier, List<ImplTy>>{};
  ImplTy? getImpl(Identifier ident) {
    return getKV(ident, (c) => c.impls, importHandle: (c) {
      return c.getImpl(ident);
    });
  }

  void pushImpl(Identifier ident, ImplTy ty) {
    pushKV(ident, ty, impls);
  }

  final implForStructs = <StructTy, List<ImplTy>>{};
  ImplTy? getImplForStruct(StructTy structTy, Identifier ident) {
    ImplTy? cache;
    final v = getKV(structTy.parentOrCurrent, (c) => c.implForStructs,
        importHandle: (c) => c.getImplForStruct(structTy, ident),
        test: (v) {
          Ty? ty = v.struct.grtOrT(this);
          if (ty is! StructTy) {
            ty = getStruct(v.struct.ident);
          }

          bool? isRealTy;
          if (ty is StructTy) {
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

          final constain = v.contains(ident);

          if (isRealTy == true && constain) {
            cache = v;
          }

          return constain;
        });
    return cache ?? v;
  }

  void pushImplForStruct(StructTy structTy, ImplTy ty) {
    pushKV(structTy.parentOrCurrent, ty, implForStructs);
  }

  final cTys = <Identifier, List<CTypeTy>>{};

  CTypeTy? getCty(Identifier ident) {
    return getKV(ident, (c) => c.cTys, importHandle: (c) {
      return c.getCty(ident);
    });
  }

  void pushCty(Identifier ident, CTypeTy ty) {
    pushKV(ident, ty, cTys);
  }

  void pushAllTy(Map<Token, Ty> all) {
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
      } else if (ty is CTypeTy) {
        pushCty(ty.ident, ty);
      } else {
        print('unknown ty {${ty.runtimeType}}');
      }
    }
    for (var impl in impls) {
      final struct = getStruct(impl.struct.ident);
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
        getCty(i);
  }

  void errorExpr(UnknownExpr unknownExpr) {}

  VA? getKV<K, VA>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA, T>? importHandle, bool Function(VA v)? test}) {
    final list = map(this)[k];
    final hasTest = test != null;

    if (list != null) {
      for (var item in list.reversed) {
        if (hasTest && !test(item)) continue;

        return item;
      }
    }
    if (importHandle != null) {
      final v = runImport(() {
        for (var imp in imports.values) {
          final v = importHandle(imp);
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

    return parent?.getKV(k, map, importHandle: importHandle, test: test);
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

typedef ImportKV<VA, T> = VA? Function(T c);
