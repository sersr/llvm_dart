part of 'ast.dart';

class Block extends BuildMixin with EquatableMixin implements LogPretty {
  Block(this._innerStmts, this.ident, this.blockStart, this.blockEnd,
      {bool inc = true}) {
    if (inc) _init();
    _lastIndex = _innerStmts.lastIndexWhere((element) => element is! TyStmt);
  }

  Block._(this._innerStmts, this.ident, this.blockStart, this.blockEnd);

  void _init() {
    for (var s in _innerStmts) {
      s.incLevel();
    }
  }

  @override
  (List, int) logPretty(int level) {
    return (_innerStmts, level);
  }

  final Identifier? ident;
  final List<Stmt> _innerStmts;
  late final int _lastIndex;

  final Identifier blockStart;
  final Identifier blockEnd;

  bool get isNotEmpty => _lastIndex != -1;
  bool get isEmpty => _lastIndex == -1;

  Stmt? get lastOrNull => _lastIndex == -1 ? null : _innerStmts[_lastIndex];

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);

    for (var s in _innerStmts) {
      s.incLevel(count);
    }
  }

  Block clone() {
    return Block._(_innerStmts.clone(), ident, blockStart, blockEnd)
      .._lastIndex = _lastIndex;
  }

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = _innerStmts.map((e) => '$e\n').join();
    return '${ident == null ? '' : '$ident '}{\n$s$p}';
  }

  void build(FnBuildMixin context, {bool hasRet = false}) {
    context.block = this;
    for (var stmt in _innerStmts) {
      stmt.prepareBuild(context);
    }
    if (!hasRet) {
      for (var stmt in _innerStmts) {
        stmt.build(false);
      }
    } else {
      for (var i = 0; i < _innerStmts.length; i++) {
        final stmt = _innerStmts[i];
        stmt.build(i == _lastIndex);
      }
    }
  }

  @override
  List<Object?> get props => _innerStmts;

  void analysis(AnalysisContext context, {bool hasRet = false}) {
    for (var stmt in _innerStmts) {
      stmt.prepareAnalysis(context);
    }

    if (!hasRet) {
      for (var stmt in _innerStmts) {
        stmt.analysis(false);
      }
    } else {
      for (var i = 0; i < _innerStmts.length; i++) {
        final stmt = _innerStmts[i];
        stmt.analysis(i == _lastIndex);
      }
    }
  }
}
