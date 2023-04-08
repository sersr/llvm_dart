import 'package:equatable/equatable.dart';
import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/tys.dart';

class AnalysisContext with Tys<AnalysisContext, AnalysisVariable> {
  AnalysisContext.root() : parent = null;

  AnalysisContext._(AnalysisContext this.parent);

  AnalysisContext childContext() {
    return AnalysisContext._(this);
  }

  AnalysisContext? getLastFnContext() {
    if (fnContext != null) return fnContext;
    return parent?.getLastFnContext();
  }

  AnalysisVariable? _getVariable(Identifier ident, AnalysisContext? currentFn) {
    final list = variables[ident];
    final fnContext = getLastFnContext();
    if (list != null) {
      final val = list.last;
      if (fnContext != currentFn) {
        currentFn?.catchVariables.add(val);
      }
      return val;
    }

    return parent?._getVariable(ident, currentFn);
  }

  // 匿名函数自动捕捉的变量集合
  late final catchVariables = <AnalysisVariable>{};
  Set<AnalysisVariable> childrenVariables = {};

  void addChild(Set<AnalysisVariable> child) {
    childrenVariables.addAll(child);
  }

  @override
  AnalysisVariable? getVariable(Identifier ident) {
    final list = variables[ident];
    if (list != null) {
      return list.last;
    }
    final fnContext = getLastFnContext();
    return _getVariable(ident, fnContext);
  }

  AnalysisContext? fnContext;

  void setFnContext(AnalysisContext fn) {
    fnContext = fn;
  }

  @override
  final AnalysisContext? parent;
}

class AnalysisVariable with EquatableMixin {
  AnalysisVariable(this.ty, this.ident, [this.kind = const []]);
  final Ty ty;
  final List<PointerKind> kind;
  final Identifier ident;

  @override
  String toString() {
    return '$ident: [$ty]';
  }

  @override
  List<Object?> get props => [ident, ty];
}
