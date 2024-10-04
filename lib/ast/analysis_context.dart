import 'ast.dart';
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
      if (context.getLastFnContext() case var context?
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

  Set<AnalysisVariable> get childrenVariables =>
      _delay.expand((e) => e()).toSet();

  final _delay = <Set<AnalysisVariable> Function()>[];

  void addChild(Fn target) {
    final fn = getLastFnContext();
    if (fn == null) return;
    if (fn._currentFn == target) return;

    fn._delay.add(() {
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
  void pushVariable(AnalysisVariable variable, {bool isAlloca = true}) {
    variable.lifecycle.fnContext = getLastFnContext();
    variable._isAlloca = isAlloca;
    allLifeCycyle.add(variable);

    super.pushVariable(variable);
  }

  void pushNew(AnalysisVariable variable) {
    pushVariable(variable, isAlloca: false);
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
      buf.write('_${p.currentFn?.ident}\n');
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
      {AnalysisVariable? body, bool isGlobal = false}) {
    final val = body == null
        ? AnalysisVariable._(ty, ident)
        : AnalysisFieldVariable._(ty, ident, body);
    val.lifecycle.fnContext = this;
    val._isGlobal = isGlobal;
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
  late final props = [pathTy.ident, pathTy.genericInsts, pathTy.kind];

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

  AnalysisVariable copy({required Identifier ident}) {
    return AnalysisVariable._(ty, ident)
      ..lifecycle.from(lifecycle)
      .._isGlobal = isGlobal
      .._isAlloca = _isAlloca
      .._parent = this;
  }

  bool _isGlobal = false;
  bool get isGlobal => _isGlobal;
  bool _isAlloca = false;
  bool get isAlloca => _isAlloca;

  bool get isRef {
    if (ty case RefTy(isPointer: false)) {
      return true;
    }
    return false;
  }

  AnalysisVariable? _parent;

  List<AnalysisVariable> get allParent {
    final l = <AnalysisVariable>[];
    var p = _parent;
    while (p != null) {
      l.add(p);
      p = p._parent;
    }
    return l;
  }

  late final Lifecycle lifecycle = Lifecycle(this);

  @override
  String toString() {
    return '$ident: [$ty]';
  }
}

class AnalysisFieldVariable extends AnalysisVariable {
  AnalysisFieldVariable._(Ty ty, Identifier ident, this.owner)
      : super._(ty, ident);

  final AnalysisVariable owner;

  @override
  AnalysisFieldVariable copy({required Identifier ident}) {
    return AnalysisFieldVariable._(ty, ident, owner)
      ..lifecycle.from(lifecycle)
      .._isGlobal = isGlobal
      .._isAlloca = _isAlloca
      .._parent = this;
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
  AnalysisVariable? get _parent => vals.firstOrNull?._parent;

  @override
  Identifier get ident => vals.firstOrNull?.ident ?? super.ident;

  @override
  Lifecycle get lifecycle => vals.firstOrNull?.lifecycle ?? super.lifecycle;

  @override
  AnalysisVariable copy({required Identifier ident}) {
    return vals.first.copy(ident: ident);
  }
}

class Lifecycle {
  Lifecycle(this.current);
  AnalysisContext? fnContext;
  final AnalysisVariable current;

  void from(Lifecycle other) {
    fnContext = other.fnContext;
    _isStackRef = other._isStackRef;
    _deps = other._deps;
  }

  bool _isStackRef = false;

  bool get isStackRef {
    if (_isStackRef) return true;
    if (current case AnalysisFieldVariable v
        when v.owner.lifecycle._idents.contains(v.ident)) return true;

    return false;
  }

  List<AnalysisVariable>? _deps;
  List<AnalysisVariable>? _otherDeps;

  late final List<Identifier> _idents = [];

  List<String> light() {
    return [
      if (current case AnalysisFieldVariable v
          when v.owner.lifecycle._idents.contains(v.ident))
        ...v.owner.lifecycle.light(),
      ...?_deps?.expand((e) => e.lifecycle.light()),
      current.ident.light,
      ...?_otherDeps?.expand((e) => e.lifecycle.light()),
    ];
  }

  void _updateOwnerRef(Identifier ident, List<AnalysisVariable> deps) {
    _isStackRef = true;

    _otherDeps ??= [];
    if (!_idents.contains(ident)) {
      _idents.add(ident);
    }
    _otherDeps!.addAll(deps);
  }

  void updateRef(List<AnalysisVariable> deps) {
    if (deps.isEmpty) return;
    _isStackRef = true;
    if (current case AnalysisFieldVariable v) {
      v.owner.lifecycle._updateOwnerRef(current.ident, deps);
    }

    _deps ??= [];
    _deps!.addAll(deps);
  }
}
