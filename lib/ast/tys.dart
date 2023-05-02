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

typedef ImportHandler<T> = T Function(Tys, ImportPath);
typedef RunImport<T> = T Function(T Function());

mixin Tys<T extends Tys<T, V>, V extends IdentVariable> {
  T? get parent;

  String? currentPath;

  final imports = <ImportPath, T>{};

  R? runImport<R>(R Function() body) {
    if (_runImport) return null;
    return runZoned(body, zoneValues: {#_runImport: true});
  }

  ImportHandler<T>? importHandler;

  ImportHandler<T>? getImportHandler() {
    if (importHandler != null) return importHandler!;
    return parent?.getImportHandler();
  }

  void pushImport(ImportPath path, {Identifier? name}) {
    if (!imports.containsKey(path)) {
      final im = getImportHandler()?.call(this, path);
      if (im != null) {
        imports[path] = im;
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
    final list = structs[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getStruct(ident);
  }

  void pushStruct(Identifier ident, StructTy ty) {
    final list = structs.putIfAbsent(ident, () => []);
    if (!list.contains(ty)) {
      list.add(ty);
    }
  }

  final enums = <Identifier, List<EnumTy>>{};
  EnumTy? getEnum(Identifier ident) {
    final list = enums[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getEnum(ident);
  }

  void pushEnum(Identifier ident, EnumTy ty) {
    final list = enums.putIfAbsent(ident, () => []);
    if (!list.contains(ty)) {
      list.add(ty);
      ty.push(this);
    }
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    final list = fns[ident];
    if (list != null) {
      return list.last;
    }

    final v = runImport(() {
      for (var imp in imports.values) {
        final v = imp.getFn(ident);
        if (v != null) {
          return v;
        }
      }
    });

    return v ?? parent?.getFn(ident);
  }

  void pushFn(Identifier ident, Fn fn) {
    final list = fns.putIfAbsent(ident, () => []);
    if (!list.contains(fn)) {
      list.add(fn);
    }
  }

  final components = <Identifier, List<ComponentTy>>{};
  ComponentTy? getComponent(Identifier ident) {
    final list = components[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getComponent(ident);
  }

  void pushComponent(Identifier ident, ComponentTy com) {
    final list = components.putIfAbsent(ident, () => []);
    if (!list.contains(com)) {
      list.add(com);
    }
  }

  final impls = <Identifier, List<ImplTy>>{};
  ImplTy? getImpl(Identifier ident) {
    final list = impls[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getImpl(ident);
  }

  void pushImpl(Identifier ident, ImplTy ty) {
    final list = impls.putIfAbsent(ident, () => []);
    if (!list.contains(ty)) {
      list.add(ty);
    }
  }

  final implForStructs = <StructTy, List<ImplTy>>{};
  ImplTy? getImplForStruct(StructTy structTy) {
    final list = implForStructs[structTy.parentOrCurrent];
    if (list != null) {
      return list.last;
    }
    return parent?.getImplForStruct(structTy);
  }

  void pushImplForStruct(StructTy structTy, ImplTy ty) {
    final list = implForStructs.putIfAbsent(structTy, () => []);
    if (!list.contains(ty)) {
      list.add(ty);
    }
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
        getEnum(i);
  }

  void errorExpr(UnknownExpr unknownExpr) {}
}
