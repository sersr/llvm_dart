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

  bool isCurrentFn(AnalysisVariable variable, AnalysisContext? current) {
    if (getLastFnContext() != current) return false;
    if (variables.containsKey(variable.ident)) {
      return true;
    }
    return parent?.isCurrentFn(variable, current) ?? false;
  }

  // 匿名函数自动捕捉的变量集合
  late final catchVariables = <AnalysisVariable>{};
  Set<AnalysisVariable> childrenVariables = {};

  void addChild(Set<AnalysisVariable> child) {
    final fn = getLastFnContext();
    if (fn == null) return;
    for (var v in child) {
      if (isCurrentFn(v, fn)) {
        continue;
      }
      fn.childrenVariables.add(v);
    }
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

  AnalysisVariable? getVariableOrFn(
      Identifier ident,
      void Function(AnalysisVariable variable) mVar,
      void Function(Fn fn) getFn) {
    final list = variables[ident];
    if (list != null) {
      return list.last;
    }
    final fnContext = getLastFnContext();
    return _getVariable(ident, fnContext);
  }

  AnalysisContext? fnContext;
  Fn? currentFn;
  void setFnContext(AnalysisContext fnC, Fn fn) {
    fnContext = fnC;
    fnC.currentFn = fn;
    currentFn = fn;
  }

  @override
  final AnalysisContext? parent;

  String tree() {
    final buf = StringBuffer();
    AnalysisContext? p = this;
    int l = 0;
    while (p != null) {
      buf.write(' ' * l);
      buf.write('_${p.currentFn?.fnSign.fnDecl.ident}\n');
      l += 4;
      p = p.parent;
    }
    return buf.toString();
  }
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
