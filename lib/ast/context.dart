import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';

abstract class BuildContext {
  BuildContext(this.parent);
  final BuildContext? parent;

  BuildContext createChildContext();

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

  void errorExpr(UnknownExpr unknownExpr) {}

  Variable buildVariable(Ty ty, String ident) {
    return Variable(ty);
  }

  Variable buildAlloca(covariant Variable val, {Ty? ty}) {
    return Variable(ty ?? val.ty);
  }

  Variable buildAllocaNull(Ty ty) {
    return DeclVariable(ty, null);
  }

  Variable math(covariant Variable lhs, covariant Variable rhs, OpKind op) {
    return Variable(lhs.ty);
  }

  Variable buildFn(FnSign fn) {
    return Variable(fn.fnDecl.returnTy);
  }

  IfBuildContext buildIf(covariant Variable val) {
    return IfBuildContext(val, createChildContext(), createChildContext());
  }

  void buildFnBB(Fn fn, void Function(BuildContext child) action) {
    action(this);
  }

  void br(covariant BuildContext to) {}
  void buildIfExprBlock(IfExprBlock ifEB) {}
  void ret(covariant Variable? val) {}
}

class AnalysisBuildContext extends BuildContext {
  AnalysisBuildContext._(AnalysisBuildContext parent) : super(parent);
  AnalysisBuildContext.root() : super(null);
  @override
  BuildContext createChildContext() {
    return AnalysisBuildContext._(this);
  }
}

class BasicBlock {}

class IfBuildContext {
  IfBuildContext(this.val, this.then, this.elseContext);
  final Variable val;
  final BuildContext then;
  final BuildContext elseContext;
}

class Variable {
  Variable(this.ty);
  final Ty ty;

  bool get _isBuiltin {
    return ty is BuiltInTy;
  }

  LitKind get _lit {
    return (ty as BuiltInTy).ty;
  }

  bool get isInt {
    return _isBuiltin && _lit == LitKind.kInt;
  }

  bool get isBool {
    return _isBuiltin && _lit == LitKind.kBool;
  }

  bool get isDouble {
    return _isBuiltin && _lit == LitKind.kDouble;
  }

  bool get isFloat {
    return _isBuiltin && _lit == LitKind.kFloat;
  }

  bool get isString {
    return _isBuiltin && _lit == LitKind.kString;
  }

  bool get isVoid {
    return _isBuiltin && _lit == LitKind.kVoid;
  }
}

class DeclVariable extends Variable {
  DeclVariable(super.ty, this.value);
  Variable? value;
}
