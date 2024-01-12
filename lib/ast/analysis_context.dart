import 'ast.dart';
import 'expr.dart';
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

  AnalysisVariable? _getVariable(Identifier ident, AnalysisContext? currentFn) {
    final list = variables[ident];

    final fnContext = getLastFnContext();
    if (list != null) {
      var last = list.last;
      for (var val in list.reversed) {
        last = val;
        if (val.ident.start > ident.start) continue;
        break;
      }
      if (fnContext != currentFn) {
        if (!last.isGlobal) {
          currentFn?.catchVariables.add(last);
        }
      }
      last.updateLifeCycle(ident);
      return last;
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
  Set<AnalysisVariable> get childrenVariables {
    final cache = <AnalysisVariable>{};
    for (var v in _catchFns) {
      cache.addAll(v());
    }
    return cache;
  }

  final _catchFns = <Set<AnalysisVariable> Function()>[];

  void addChild(Fn target) {
    final fn = getLastFnContext();
    if (fn == null) return;
    if (fn._currentFn == target) return;
    fn._catchFns.add(() {
      final c = <AnalysisVariable>{};
      for (var v in target.variables) {
        if (isCurrentFn(v, fn)) {
          continue;
        }
        c.add(v);
      }
      return c;
    });
  }

  @override
  AnalysisVariable? getVariableImpl(Identifier ident, {bool prin = false}) {
    final list = variables[ident];
    if (list != null) {
      var last = list.last;
      for (var val in list.reversed) {
        last = val;
        if (val.ident.start > ident.start) continue;
        break;
      }
      last.updateLifeCycle(ident);

      return last;
    }
    final fnContext = getLastFnContext();
    return _getVariable(ident, fnContext);
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
  VA? getKVImpl<K, VA>(
      K k, Map<K, List<VA>> Function(Tys<LifeCycleVariable> c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return super.getKVImpl(k, map, handler: handler, test: test) ??
        parent?.getKVImpl(k, map, handler: handler, test: test);
  }

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

  List<AnalysisVariable> allLifeCycyle = [];

  void forEach(void Function(AnalysisVariable variable) action) {
    allLifeCycyle.forEach(action);
    for (var child in children) {
      child.forEach(action);
    }
  }

  AnalysisVariable createVal(Ty ty, Identifier ident,
      [List<PointerKind>? kind]) {
    final val = AnalysisVariable._(ty, ident, kind ?? []);
    val.lifecycle.fnContext = this;
    return val;
  }

  AnalysisStructVariable createStructVal(
      Ty ty, Identifier ident, Map<Identifier, AnalysisVariable> map,
      [List<PointerKind>? kind]) {
    final val = AnalysisStructVariable._(ty, ident, map, kind ?? []);
    val.lifecycle.fnContext = this;
    return val;
  }
}

class AnalysisVariable extends LifeCycleVariable {
  AnalysisVariable._(this.ty, this._ident, this.kind);
  final Ty ty;
  final List<PointerKind> kind;
  final Identifier _ident;

  @override
  Identifier get ident => _ident;

  AnalysisVariable copy(
      {Ty? ty,
      Identifier? ident,
      List<PointerKind>? kind,
      bool isGlobal = false}) {
    return AnalysisVariable._(
        ty ?? this.ty, ident ?? this.ident, kind ?? this.kind.toList())
      ..lifecycle.from(lifecycle)
      ..isGlobal = isGlobal
      ..parent = this;
  }

  bool isGlobal = false;

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

class AnalysisStructVariable extends AnalysisVariable {
  AnalysisStructVariable._(Ty ty, Identifier ident,
      Map<Identifier, AnalysisVariable> map, List<PointerKind> kind)
      : _params = map,
        super._(ty, ident, kind);

  @override
  AnalysisStructVariable copy(
      {Ty? ty,
      Identifier? ident,
      Map<Identifier, AnalysisVariable>? map,
      List<PointerKind>? kind,
      bool isGlobal = false}) {
    return AnalysisStructVariable._(ty ?? this.ty, ident ?? this.ident,
        map ?? _params, kind ?? this.kind.toList())
      ..lifecycle.from(lifecycle)
      ..isGlobal = isGlobal
      ..parent = this;
  }

  final Map<Identifier, AnalysisVariable> _params;

  AnalysisVariable? getParam(Identifier ident) {
    return _params[ident];
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
