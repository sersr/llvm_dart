import 'package:llvm_dart/ast/build_methods.dart';

import '../llvm_core.dart';
import '../parsers/lexers/token_kind.dart';
import 'ast.dart';
import 'llvm_context.dart';

abstract class Variable {
  LLVMValueRef load(BuildContext c);
  Ty get ty;
}

mixin Tys<T extends Tys<T>> on BuildMethods {
  @override
  T? get parent;

  final variables = <Identifier, List<Variable>>{};

  Variable? getVariable(Identifier ident) {
    final list = variables[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getVariable(ident);
  }

  void pushVariable(Identifier ident, Variable variable) {
    final list = variables.putIfAbsent(ident, () => []);
    if (!list.contains(variable)) {
      list.add(variable);
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
    }
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    final list = fns[ident];
    if (list != null) {
      return list.last;
    }
    return parent?.getFn(ident);
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

  void pushCOmponent(Identifier ident, ComponentTy com) {
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

  void pushAllTy(Map<Token, Ty> all) {
    for (var ty in all.values) {
      if (ty is StructTy) {
        pushStruct(ty.ident, ty);
      } else if (ty is Fn) {
        pushFn(ty.fnSign.fnDecl.ident, ty);
      } else if (ty is EnumTy) {
        pushEnum(ty.ident, ty);
      } else if (ty is ComponentTy) {
        pushCOmponent(ty.ident, ty);
      } else if (ty is ImplTy) {
        pushImpl(ty.ident, ty);
      } else {
        print('unknown ty {${ty.runtimeType}}');
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
