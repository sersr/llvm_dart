part of 'ast.dart';

class Block extends BuildMixin with EquatableMixin {
  Block(this._innerStmts, this.ident, this.blockStart, this.blockEnd) {
    _init();
    final fnStmt = <Fn>[];
    final others = <Stmt>[];
    final tyStmts = <Stmt>[];
    final implStmts = <Stmt>[];
    final aliasStmts = <Stmt>[];
    final importStmts = <Stmt>[];
    // 函数声明前置
    for (var stmt in _innerStmts) {
      if (stmt is TyStmt) {
        final ty = stmt.ty;
        switch (ty) {
          case Fn ty:
            fnStmt.add(ty);
          case ImplTy _:
            implStmts.add(stmt);
          case TypeAliasTy _:
            aliasStmts.add(stmt);
          case _:
            tyStmts.add(stmt);
        }

        continue;
      } else if (stmt case ExprStmt(expr: ImportExpr())) {
        importStmts.add(stmt);
        continue;
      }
      others.add(stmt);
    }
    _fnExprs = fnStmt;
    _stmts = others;
    _tyStmts = tyStmts;
    _implTyStmts = implStmts;
    _aliasStmts = aliasStmts;
    _importStmts = importStmts;
  }

  Block._(this._innerStmts, this.ident, this.blockStart, this.blockEnd);

  void _init() {
    // {
    //   stmt
    // }
    for (var s in _innerStmts) {
      s.incLevel();
    }
  }

  final Identifier? ident;
  final List<Stmt> _innerStmts;

  late List<Fn> _fnExprs;
  late List<Stmt> _stmts;
  late List<Stmt> _tyStmts;
  late List<Stmt> _implTyStmts;
  late List<Stmt> _aliasStmts;
  late List<Stmt> _importStmts;
  final Identifier blockStart;
  final Identifier blockEnd;

  bool get isNotEmpty => _stmts.isNotEmpty;

  Stmt? get lastOrNull => _stmts.lastOrNull;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);

    for (var s in _innerStmts) {
      s.incLevel(count);
    }
  }

  Block clone() {
    return Block._(_innerStmts, ident, blockStart, blockEnd)
      .._fnExprs = _fnExprs.clone()
      .._stmts = _stmts.clone()
      .._implTyStmts = _implTyStmts.clone()
      .._aliasStmts = _aliasStmts.clone()
      .._importStmts = _importStmts.clone()
      .._tyStmts = _tyStmts.clone();
  }

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = _innerStmts.map((e) => '$e\n').join();
    return '${ident ?? ''} {\n$s$p}';
  }

  void build(FnBuildMixin context, {bool hasRet = false}) {
    for (var stmt in _importStmts) {
      stmt.build(context, false);
    }

    for (var fn in _fnExprs) {
      fn.currentContext = context;
      fn.build();
    }

    for (var ty in _tyStmts) {
      ty.build(context, false);
    }

    for (var alias in _aliasStmts) {
      alias.build(context, false);
    }

    for (var implTy in _implTyStmts) {
      implTy.build(context, false);
    }

    if (!hasRet) {
      for (var stmt in _stmts) {
        stmt.build(context, false);
      }
    } else {
      final length = _stmts.length;
      final max = length - 1;

      // 先处理普通语句，在内部函数中可能会引用到变量等
      for (var i = 0; i < length; i++) {
        final stmt = _stmts[i];
        stmt.build(context, i == max);
      }
    }
  }

  @override
  List<Object?> get props => [_innerStmts];

  @override
  void analysis(AnalysisContext context) {
    for (var stmt in _importStmts) {
      stmt.analysis(context);
    }

    for (var fn in _fnExprs) {
      context.pushFn(fn.fnName, fn);
    }

    for (var ty in _tyStmts) {
      ty.analysis(context);
    }

    for (var alais in _aliasStmts) {
      alais.analysis(context);
    }

    for (var implTy in _implTyStmts) {
      implTy.analysis(context);
    }

    for (var stmt in _stmts) {
      stmt.analysis(context);
    }

    for (var fn in _fnExprs) {
      fn.analysis(context);
    }
  }
}
