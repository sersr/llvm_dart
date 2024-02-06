part of 'expr.dart';

class IfExprBlock extends Expr implements LogPretty {
  IfExprBlock(this.expr, this.block);

  final Expr? expr;
  final Block block;

  IfExprBlock? child;

  @override
  IfExprBlock clone() {
    return IfExprBlock(expr?.clone(), block.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  String toString() {
    if (expr == null) {
      return block.toString();
    }
    return 'if $expr $block';
  }

  @override
  (Map, int) logPretty(int level) {
    return (
      {
        "condition": expr,
        "stmts": block,
      },
      level,
    );
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    expr?.analysis(context);
    return analysisBlock(block, context);
  }

  static AnalysisVariable? analysisBlock(
      Block? block, AnalysisContext context) {
    if (block == null) return null;
    block.analysis(context);

    return retFromBlock(block, context);
  }

  static AnalysisVariable? retFromBlock(Block block, AnalysisContext context) {
    if (block.isNotEmpty) {
      final last = block.lastOrNull;
      if (last is ExprStmt) {
        final expr = last.expr;
        return expr.analysis(context);
      }
    }
    return null;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    return null;
  }
}

class IfExpr extends Expr with RetExprMixin implements LogPretty {
  IfExpr(this.ifExprBlocks) {
    if (ifExprBlocks.isEmpty) return;
    IfExprBlock? last;
    for (var e in ifExprBlocks) {
      if (last == null) {
        last = e;
        continue;
      }

      last.child = e;
      last = e;
    }
  }

  @override
  Expr clone() {
    return IfExpr(ifExprBlocks.clone()).._variable = _variable;
  }

  @override
  (Object, int) logPretty(int level) {
    return (
      {
        "if expr": ifExprBlocks,
      },
      level
    );
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var element in ifExprBlocks) {
      element.incLevel(count);
    }
  }

  final List<IfExprBlock> ifExprBlocks;

  @override
  String toString() {
    return ifExprBlocks.join(' else ');
  }

  Ty? _getTy() {
    if (_variable == null) return null;
    Ty? ty;

    for (var val in _variable!.vals) {
      if (ty == null) {
        ty = val.ty;
        continue;
      }
      if (ty != val.ty) {
        return null;
      }
    }

    return ty;
  }

  @override
  ExprTempValue? buildRetExpr(FnBuildMixin context, Ty? baseTy, bool isRet) {
    if (ifExprBlocks.isEmpty) return null;

    var ty = baseTy ?? _getTy();

    if (LiteralKind.kVoid.ty.isTy(ty)) ty = null;

    final v = IfExprBuilder.createIfBlock(ifExprBlocks.first, context, ty,
        isRet, ifExprBlocks.lastOrNull?.expr == null);
    if (v == null) return null;
    return ExprTempValue(v);
  }

  AnalysisListVariable? _variable;
  @override
  AnalysisListVariable? analysis(AnalysisContext context) {
    final vals = <AnalysisVariable>[];

    void add(AnalysisVariable? val) {
      if (val is AnalysisListVariable) {
        vals.addAll(val.vals);
      } else if (val != null) {
        vals.add(val);
      }
    }

    for (var e in ifExprBlocks) {
      final val = e.analysis(context.childContext());
      add(val);
    }

    return _variable = AnalysisListVariable(vals);
  }
}

class BreakExpr extends Expr {
  BreakExpr(this.ident, this.label);
  @override
  Expr clone() {
    return BreakExpr(ident, label);
  }

  final Identifier ident;
  final Identifier? label;

  @override
  String toString() {
    if (label == null) {
      return '$ident [break]';
    }
    return '$ident $label [break]';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.brLoop();
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }
}

class ContinueExpr extends Expr {
  ContinueExpr(this.ident);
  final Identifier ident;
  @override
  Expr clone() {
    return ContinueExpr(ident);
  }

  @override
  String toString() {
    return ident.toString();
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.brContinue();
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }
}

/// label: loop { block }
class LoopExpr extends Expr {
  LoopExpr(this.ident, this.block);
  final Identifier ident; // label
  final Block block;
  @override
  Expr clone() {
    return LoopExpr(ident, block.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  String toString() {
    return 'loop$block';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.forLoop(block, null, null);
    // todo: phi
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    block.analysis(context.childContext());
    return null;
  }
}

/// label: while expr { block }
class WhileExpr extends Expr {
  WhileExpr(this.ident, this.expr, this.block);
  @override
  Expr clone() {
    return WhileExpr(ident, expr.clone(), block.clone());
  }

  final Identifier ident;
  final Expr expr;
  final Block block;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  String toString() {
    return 'while $expr$block';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.forLoop(block, null, expr);
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final child = context.childContext();
    expr.analysis(child);
    block.analysis(child.childContext());
    return null;
  }
}

class MatchItemExpr extends BuildMixin
    implements Clone<MatchItemExpr>, LogPretty {
  MatchItemExpr(this.expr, this.block, this.op);
  final Expr expr;
  final Block block;
  final OpKind? op;

  MatchItemExpr? child;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  (Object, int) logPretty(int level) {
    return (
      {
        "expr": expr,
        "op": op,
        "stmts": block,
      },
      level
    );
  }

  AnalysisVariable? analysis(AnalysisContext context) {
    final child = context.childContext();
    final e = expr;
    if (e is FnCallExpr) {
      final enumVariable = e.expr.analysis(child);
      final params = e.params;
      final enumTy = enumVariable?.ty;
      if (enumTy is EnumItem) {
        for (var i = 0; i < params.length; i++) {
          final p = params[i];
          if (i >= enumTy.fields.length) {
            break;
          }
          final f = enumTy.fields[i];
          final ident = p.pattern;
          if (ident != null) {
            final ty = enumTy.getFieldTyOrT(child, f) ??
                p.analysis(context)?.ty ??
                AnalysisTy(f.rawTy);

            child.pushVariable(child.createVal(ty, ident));
          }
        }
      }
    } else {
      expr.analysis(child);
    }
    block.analysis(child);

    return IfExprBlock.retFromBlock(block, context);
  }

  bool get isValIdent {
    return op == null && expr is VariableIdentExpr;
  }

  bool get isOther {
    final e = expr;
    if (e is VariableIdentExpr) {
      if (e.ident.src == '_') {
        return true;
      }
    }
    return false;
  }

  void build4(FnBuildMixin context, ExprTempValue parrern, bool isRet) {
    final child = context;
    final e = expr as VariableIdentExpr;
    child.pushVariable(parrern.variable!.newIdent(e.ident));
    block.build(child, hasRet: isRet);
  }

  ExprTempValue? build3(FnBuildMixin context, ExprTempValue pattern) {
    return OpExpr.math(
        context, op ?? OpKind.Eq, pattern.variable, expr, Identifier.none);
  }

  int? build2(FnBuildMixin context, ExprTempValue pattern, bool isRet) {
    final child = context;
    var e = expr;
    int? value;
    List<FieldExpr> params = const [];

    if (e is FnCallExpr) {
      params = e.params;
      e = e.expr;
    }

    final enumVariable = e.build(child);
    var item = enumVariable?.ty;
    final val = pattern.variable;
    if (val != null) {
      final valTy = val.ty;
      if (item is EnumItem && valTy is NewInst) {
        assert(item.parent.parentOrCurrent == valTy.parentOrCurrent,
            "error: ${item.parent} is not $valTy");

        item = item.newInst(valTy.tys, context);
        value = item.llty.load(child, val, params);
      } else {
        Log.e('${val.ident.light}\n$valTy enum match error\n$item',
            showTag: false);
      }
    }

    block.build(child, hasRet: isRet);
    return value;
  }

  @override
  MatchItemExpr clone() {
    return MatchItemExpr(expr.clone(), block.clone(), op);
  }

  @override
  String toString() {
    final o = op == null ? '' : '${op!.op} ';
    return '$pad$o$expr => $block';
  }
}

class MatchExpr extends Expr with RetExprMixin implements LogPretty {
  MatchExpr(this.expr, this.items) {
    for (var item in items) {
      item.incLevel();
    }
  }

  final Expr expr;
  final List<MatchItemExpr> items;

  @override
  (Object, int) logPretty(int level) {
    return (
      {
        "match expr": expr,
        "items": items,
      },
      level
    );
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var item in items) {
      item.incLevel(count);
    }
  }

  List<AnalysisVariable>? _variables;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    expr.analysis(context);
    final variables = _variables = [];
    for (var item in items) {
      final val = item.analysis(context);
      if (val != null) {
        variables.add(val);
      }
    }
    return AnalysisListVariable(variables);
  }

  Ty? _getTy() {
    if (_variables == null) return null;
    Ty? ty;

    for (var val in _variables!) {
      if (ty == null) {
        ty = val.ty;
        continue;
      }
      if (ty != val.ty) {
        return null;
      }
    }

    return ty;
  }

  @override
  ExprTempValue? buildRetExpr(FnBuildMixin context, Ty? baseTy, bool isRet) {
    final temp = expr.build(context);
    if (temp == null) return null;

    var ty = baseTy ?? _getTy();

    if (LiteralKind.kVoid.ty.isTy(ty)) ty = null;

    final variable = MatchBuilder.matchBuilder(context, items, temp, ty, isRet);

    if (variable == null) return null;

    return ExprTempValue(variable);
  }

  @override
  Expr clone() {
    return MatchExpr(expr.clone(), items.clone()).._variables = _variables;
  }

  @override
  String toString() {
    return 'match $expr {\n${items.join(',\n')}\n$pad}';
  }
}
