import 'package:nop/nop.dart';

import 'ast.dart';
import 'expr.dart';
import 'llvm/llvm_types.dart';
import 'tys.dart';

class RootAnalysis with Tys<AnalysisVariable> {
  @override
  late GlobalContext global;

  @override
  String get currentPath => throw UnimplementedError();
}

class AnalysisContext with Tys<AnalysisVariable> {
  AnalysisContext.root(this.root, this.currentPath) : parent = null;

  AnalysisContext._(AnalysisContext this.parent, this.root, this.currentPath);

  final RootAnalysis root;

  @override
  GlobalContext get global => root.global;

  AnalysisContext childContext() {
    final c = AnalysisContext._(this, root, currentPath);
    children.add(c);
    return c;
  }

  @override
  final String currentPath;

  final children = <AnalysisContext>[];

  AnalysisContext? getLastFnContext() {
    if (currentFn != null) return this;
    return parent?.getLastFnContext();
  }

  bool isChildOrCurrent(AnalysisContext other) {
    if (this == other) return true;
    AnalysisContext? c = other;
    while (true) {
      if (c == this) return true;
      if (c == null) return false;
      c = c.parent?.getLastFnContext();
    }
  }

  @override
  bool get isGlobal => getLastFnContext() == null;

  @override
  AnalysisVariable? getVariable(Identifier ident) {
    final currentFn = getLastFnContext();

    final variable = super.getVariable(ident);

    if (variable case AnalysisVariable(pushContext: AnalysisContext context)
        when currentFn != null) {
      if (context.getLastFnContext() case AnalysisContext context
          when context != currentFn) {
        currentFn.catchVariables.add(variable);
      }
    }

    return variable;
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

  final childrenVariables = <AnalysisVariable>{};

  final _depFns = <Fn>{};

  void addChild(Fn target) {
    final fn = getLastFnContext();
    if (fn == null) return;
    if (fn._currentFn == target) return;

    final c = <AnalysisVariable>{};
    for (var v in target.variables) {
      if (isCurrentFn(v, fn)) {
        continue;
      }
      c.add(v);
    }

    if (c.isNotEmpty) {
      _depFns.add(target);
      Log.w(target);
      fn.childrenVariables.addAll(c);
    }
  }

  @override
  void pushVariable(AnalysisVariable variable, {bool isAlloca = true}) {
    variable.lifecycle.fnContext = getLastFnContext();
    allLifeCycyle.add(variable);

    super.pushVariable(variable, isAlloca: isAlloca);
  }

  AnalysisContext? getFnContext(Identifier ident) {
    final list = fns[ident];
    if (list != null) {
      return this;
    }
    return parent?.getFnContext(ident);
  }

  AnalysisContext getRootContext() {
    if (parent != null) return parent!.getRootContext();
    return this;
  }

  Fn? _currentFn;
  Fn? get currentFn => _currentFn;

  void setFnContext(Fn fn) {
    _currentFn = fn;
  }

  final AnalysisContext? parent;

  /// override: Tys
  @override
  VA? getKVImpl<VA>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    return super.getKVImpl(map, test: test) ??
        parent?.getKVImpl(map, test: test);
  }

  String tree() {
    final buf = StringBuffer();
    AnalysisContext? p = this;
    int l = 0;
    while (p != null) {
      buf.write(' ' * l);
      buf.write('_${p.currentFn?.fnDecl.ident}\n');
      l += 4;
      p = p.parent;
    }
    return buf.toString();
  }

  List<AnalysisVariable> allLifeCycyle = [];

  void forEach(void Function(AnalysisVariable variable) action) {
    allLifeCycyle.forEach(action);
    for (var child in children) {
      child.forEach(action);
    }
  }

  AnalysisVariable createVal(Ty ty, Identifier ident) {
    final val = AnalysisVariable._(ty, ident);
    val.lifecycle.fnContext = this;
    return val;
  }
}

class AnalysisTy extends Ty {
  AnalysisTy(this.pathTy);
  final PathTy pathTy;

  @override
  Identifier get ident => pathTy.ident;
  @override
  Ty clone() {
    return this;
  }

  @override
  bool isTy(Ty? other) {
    if (other is AnalysisTy) {
      return pathTy.ident == other.ident;
    }
    return super.isTy(other);
  }

  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  late final props = [pathTy];

  @override
  String toString() {
    return pathTy.toString();
  }
}

class AnalysisVariable extends LifeCycleVariable {
  AnalysisVariable._(this.ty, this._ident);
  @override
  final Ty ty;
  final Identifier _ident;

  @override
  Identifier get ident => _ident;

  AnalysisVariable copy({Ty? ty, Identifier? ident, bool isGlobal = false}) {
    return AnalysisVariable._(ty ?? this.ty, ident ?? this.ident)
      ..lifecycle.from(lifecycle)
      ..isGlobal = isGlobal
      ..parent = this;
  }

  bool isGlobal = false;

  bool get isRef {
    if (ty case RefTy(isPointer: false)) {
      return true;
    }
    return false;
  }

  AnalysisVariable? parent;

  List<AnalysisVariable> get allParent {
    final l = <AnalysisVariable>[];
    var p = parent;
    while (p != null) {
      l.add(p);
      p = p.parent;
    }
    return l;
  }

  late final LifeCycle lifecycle = LifeCycle();

  @override
  String toString() {
    return '$ident: [$ty]';
  }
}

class AnalysisListVariable extends AnalysisVariable {
  AnalysisListVariable(this.vals)
      : super._(LiteralKind.kVoid.ty, Identifier.none);

  final List<AnalysisVariable> vals;
  @override
  Ty get ty => vals.firstOrNull?.ty ?? LiteralKind.kVoid.ty;

  @override
  bool get isGlobal => vals.firstOrNull?.isGlobal ?? false;

  @override
  set isGlobal(bool v) {
    vals.firstOrNull?.isGlobal = v;
  }

  @override
  AnalysisVariable? get parent => vals.firstOrNull?.parent;

  @override
  Identifier get ident => vals.firstOrNull?.ident ?? super.ident;

  @override
  LifeCycle get lifecycle => vals.firstOrNull?.lifecycle ?? super.lifecycle;

  @override
  set parent(AnalysisVariable? v) {
    vals.firstOrNull?.parent == v;
  }

  @override
  AnalysisVariable copy(
      {Ty? ty,
      Identifier? ident,
      List<PointerKind>? kind,
      bool isGlobal = false}) {
    return vals.first.copy(ty: ty, ident: ident, isGlobal: isGlobal);
  }
}

class LifeCycle {
  LifeCycle();
  AnalysisContext? fnContext;

  void from(LifeCycle other) {
    fnContext = other.fnContext;
    isOut = other.isOut;
  }

  bool isOut = false;
  bool get isInner => !isOut;
}
