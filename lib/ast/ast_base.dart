part of 'ast.dart';

class ExprTempValue {
  ExprTempValue(Variable this.variable, {Ty? ty})
      : _ty = ty,
        _ident = null;

  ExprTempValue.ty(Ty this._ty, this._ident) : variable = null;
  final Ty? _ty;
  final Variable? variable;
  final Identifier? _ident;
  Identifier? get ident => _ident ?? variable?.ident;
  Ty get ty => _ty ?? variable!.ty;
}

abstract class Expr extends BuildMixin implements Clone<Expr> {
  bool _first = true;

  bool get hasUnknownExpr => false;

  void reset() {
    _first = true;
    _temp = null;
  }

  ExprTempValue? _temp;
  ExprTempValue? build(FnBuildMixin context, {Ty? baseTy}) {
    if (!_first) return _temp;
    _first = false;
    return _temp ??= buildExpr(context, baseTy);
  }

  ExprTempValue? get temp => _temp;

  Ty? getTy(StoreLoadMixin context) => null;

  AnalysisVariable? analysis(AnalysisContext context);

  @protected
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy);
}

mixin RetExprMixin on Expr {
  @override
  ExprTempValue? build(FnBuildMixin context, {Ty? baseTy, bool isRet = false}) {
    if (!_first) return _temp;
    _first = false;
    return _temp ??= buildRetExpr(context, baseTy, isRet);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    throw 'use buildRetExpr';
  }

  ExprTempValue? buildRetExpr(FnBuildMixin context, Ty? baseTy, bool isRet);
}

class UnknownExpr extends Expr {
  UnknownExpr(this.ident, this.message);
  final Identifier ident;
  final String message;

  @override
  bool get hasUnknownExpr => true;

  @override
  Expr clone() {
    return this;
  }

  @override
  String toString() {
    return 'UnknownExpr: $ident';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.errorExpr(this);
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }
}

abstract class Clone<T> {
  T clone();
}

abstract class BuildMixin {
  int level = 0;
  @mustCallSuper
  void incLevel([int count = 1]) {
    level += count;
  }

  final extensions = <Object, dynamic>{};

  static int padSize = 2;

  String get pad => getWhiteSpace(level, padSize);
  @override
  String toString() {
    return pad;
  }
}

abstract class Stmt extends BuildMixin
    with EquatableMixin
    implements Clone<Stmt> {
  void build(bool isRet);

  FnBuildMixin? _buildContext;
  FnBuildMixin get buildContext => _buildContext!;

  @mustCallSuper
  void prepareBuild(FnBuildMixin context) {
    assert(_buildContext == null);
    _buildContext = context;
  }

  AnalysisContext? _analysisContext;
  AnalysisContext get analysisContext => _analysisContext!;
  @mustCallSuper
  void prepareAnalysis(AnalysisContext context) {
    assert(_analysisContext == null);
    _analysisContext = context;
  }

  void analysis(bool isRet) {}
}

String getWhiteSpace(int level, int pad) {
  return ' ' * level * pad;
}

extension ListClone<S, T extends Clone<S>> on List<T> {
  List<T> clone() {
    return List.from(map((e) {
      return e.clone();
    }));
  }
}

extension ListStr<T> on List<T> {
  String get str {
    if (isEmpty) return '';
    return '<${join(',')}>';
  }

  String get constraints {
    if (isEmpty) return '';
    return '[[\n${join(',')}\n]]\n';
  }
}

extension on Map<Identifier, Ty> {
  String get str {
    if (isEmpty) return '';
    return ' : ${toString()}';
  }
}
