import 'package:equatable/equatable.dart';
import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:nop/nop.dart';

class AnalysisContext with Tys<AnalysisContext, AnalysisVariable> {
  AnalysisContext.root() : parent = null;

  AnalysisContext._(AnalysisContext this.parent);

  AnalysisContext childContext() {
    final c = AnalysisContext._(this);
    children.add(c);
    return c;
  }

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
      var index = list.length;
      for (var val in list.reversed) {
        index -= 1;
        // Log.w('...${val.ident.start} ${ident.start} $ident');
        last = val;
        if (val.ident.start > ident.start) continue;
        Log.w('${val.ident.light}\n${ident.light}',
            showTag: false, showPath: false);
        break;
      }
      if (fnContext != currentFn) {
        currentFn?.catchVariables.add(last);
      }
      return last..index = index;
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
  AnalysisVariable? getVariable(Identifier ident, [int index = -1]) {
    final list = variables[ident];
    if (list != null) {
      var last = list.last;
      var index = list.length;
      for (var val in list.reversed) {
        last = list.last;
        index -= 1;
        if (val.ident.start > ident.start) continue;
        return val;
      }
      return last..index = index;
    }
    final fnContext = getLastFnContext();
    return _getVariable(ident, fnContext);
  }

  @override
  void pushVariable(Identifier ident, AnalysisVariable variable) {
    variable.lifeCycle.fnContext = getLastFnContext();
    Log.e('${ident.light}\n${variable.ident.light}', showTag: false);
    Log.i(tree(), showTag: false);
    super.pushVariable(ident, variable);
    Log.w('${variables[ident]}');
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

  AnalysisVariable createVal(Ty ty, Identifier ident,
      [List<PointerKind> kind = const []]) {
    final val = AnalysisVariable._(ty, ident, kind);
    val.lifeCycle.fnContext = getLastFnContext();
    return val;
  }

  AnalysisStructVariable createStructVal(
      Ty ty, Identifier ident, Map<Identifier, AnalysisVariable> map,
      [List<PointerKind> kind = const []]) {
    final val = AnalysisStructVariable._(ty, ident, map, kind);
    val.lifeCycle.fnContext = getLastFnContext();
    return val;
  }
}

class AnalysisVariable {
  AnalysisVariable._(this.ty, this.ident, this.kind);
  final Ty ty;
  final List<PointerKind> kind;
  final Identifier ident;

  int index = -1;

  AnalysisVariable copy({Ty? ty, Identifier? ident, List<PointerKind>? kind}) {
    return AnalysisVariable._(
        ty ?? this.ty, ident ?? this.ident, kind ?? this.kind.toList())
      ..lifeCycle.from(lifeCycle);
  }

  late final LifeCycle lifeCycle = LifeCycle();

  @override
  String toString() {
    return '$ident: [$ty]';
  }
}

class AnalysisStructVariable extends AnalysisVariable {
  AnalysisStructVariable._(
      Ty ty, Identifier ident, Map<Identifier, AnalysisVariable> map,
      [List<PointerKind> kind = const []])
      : _params = map,
        super._(ty, ident, kind);

  @override
  AnalysisStructVariable copy(
      {Ty? ty,
      Identifier? ident,
      Map<Identifier, AnalysisVariable>? map,
      List<PointerKind>? kind}) {
    return AnalysisStructVariable._(ty ?? this.ty, ident ?? this.ident,
        map ?? _params, kind ?? this.kind.toList())
      ..lifeCycle.from(lifeCycle);
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
