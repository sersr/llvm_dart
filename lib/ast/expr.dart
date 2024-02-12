// ignore_for_file: constant_identifier_names
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../abi/abi_fn.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'builders/builders.dart';
import 'builders/coms.dart';
import 'buildin.dart';
import 'llvm/build_context_mixin.dart';
import 'llvm/build_methods.dart';
import 'llvm/variables.dart';
import 'memory.dart';
import 'stmt.dart';
import 'tys.dart';

part 'expr_flow.dart';
part 'expr_fn.dart';
part 'expr_literal.dart';
part 'expr_op.dart';

class FieldExpr extends Expr {
  FieldExpr(this.expr, this.ident);
  final Identifier? ident;
  final Expr expr;

  Identifier? get pattern {
    if (ident != null) return ident;
    final e = expr;
    if (e is VariableIdentExpr) {
      return e.ident;
    }
    return null;
  }

  @override
  FieldExpr cloneSelf() {
    return FieldExpr(expr.clone(), ident);
  }

  @override
  String toString() {
    if (ident == null) {
      return '$expr';
    }
    return '$ident: $expr';
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> context, Ty? baseTy) {
    return expr.getTy(context, baseTy);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    return expr.build(context, baseTy: baseTy);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return expr.analysis(context);
  }

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;
}

class StructDotFieldExpr extends Expr {
  StructDotFieldExpr(this.struct, this.ident);
  final Identifier ident;
  final Expr struct;

  @override
  bool get hasUnknownExpr => struct.hasUnknownExpr;

  @override
  Expr cloneSelf() {
    return StructDotFieldExpr(struct.clone(), ident);
  }

  @override
  Ty? getTy(Tys context, Ty? baseTy) {
    final ty = struct.getTy(context, null);
    if (ty is! StructTy) return null;

    for (var field in ty.fields) {
      if (field.ident == ident) return field.grtOrTUd(context);
    }

    return null;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final structVal = struct.build(context);
    final val = structVal?.variable;
    var newVal = val;

    newVal = newVal?.defaultDeref(context, newVal.ident);

    if (newVal == null) return null;
    ExprTempValue? temp;
    RefDerefCom.loopGetDeref(context, newVal, (variable) {
      final ty = variable.ty;

      if (ty is StructTy) {
        final v = ty.llty.getField(variable, context, ident);
        if (v != null) {
          temp = ExprTempValue(v.newIdent(ident));
          return true;
        }
      }
      return false;
    });

    return temp;
  }

  @override
  String toString() {
    return '$struct.$ident';
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var variable = struct.analysis(context);
    if (variable == null) return null;
    var structTy = variable.ty;

    while (true) {
      if (structTy is! RefTy) {
        break;
      }
      structTy = structTy.parent;
    }
    if (structTy is RefTy) {
      structTy = structTy.baseTy;
    }
    if (structTy is! StructTy) return null;

    final v =
        structTy.fields.firstWhereOrNull((element) => element.ident == ident);
    if (v == null) {
      return null;
    }

    final ty = structTy.getFieldTyOrT(context, v);

    final vv = context.createVal(ty ?? AnalysisTy(v.rawTy), ident);
    vv.lifecycle.fnContext = variable.lifecycle.fnContext;
    return vv;
  }
}

class VariableIdentExpr extends Expr {
  VariableIdentExpr(this.ident, this.genericInsts);
  final Identifier ident;
  final List<PathTy> genericInsts;

  PathTy? _pathTy;
  PathTy get pathTy => _pathTy ??= PathTy(ident, genericInsts);
  @override
  String toString() {
    return '$ident${genericInsts.str}';
  }

  @override
  Ty? getTy(Tys context, Ty? baseTy) {
    return context.getVariable(ident)?.ty ?? pathTy.grtOrT(context) ?? baseTy;
  }

  @override
  Expr cloneSelf() {
    return VariableIdentExpr(ident, genericInsts);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    if (ident.src == 'null') {
      final ty = baseTy?.typeOf(context);

      if (ty == null) return null;

      final v = LLVMConstVariable(llvm.LLVMConstNull(ty), baseTy!, ident);
      return ExprTempValue(v);
    }

    final val = context.getVariable(ident);
    if (val != null) {
      return ExprTempValue(val.newIdent(ident, dirty: false));
    }

    final ty = switch (baseTy) {
      NewInst ty => pathTy.grtOrT(context, gen: (ident) => ty.tys[ident]),
      _ => pathTy.grtOrT(context),
    };

    switch (ty) {
      case StructTy(fields: List(isEmpty: true), done: true):
        final val = ty.llty.buildTupeOrStruct(context, const []);
        return ExprTempValue(val, ty: ty);
      case Fn(fnDecl: FnDecl(done: true)):
        final value = ty.genFn();
        return ExprTempValue(value.newIdent(ident, dirty: false));
    }

    if (ty != null) return ExprTempValue.ty(ty, ident);

    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final v = context.getVariable(ident);

    if (v != null) return v.copy(ident: ident);
    final ty = pathTy.grtOrT(context);
    if (ty is Fn) {
      context.addChild(ty);
    }

    if (ty != null) return context.createVal(ty, ident);
    return null;
  }
}

class BlockExpr extends Expr implements LogPretty {
  BlockExpr(this.block);

  final Block block;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  (Object, int) logPretty(int level) {
    return ({'block': block}, level);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final child = context.childContext();
    block.analysis(child);
    return null;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final childContext = context.createBlockContext();
    block.build(childContext);
    childContext.freeHeapCurrent(childContext);
    return null;
  }

  @override
  Expr cloneSelf() {
    return BlockExpr(block.clone());
  }

  @override
  String toString() {
    return block.toString();
  }
}

class AsExpr extends Expr {
  AsExpr(this.lhs, this.rhs);
  final Expr lhs;
  final PathTy rhs;

  @override
  Ty? getTy(Tys context, Ty? baseTy) {
    return rhs.grt(context);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final r = rhs.grtOrT(context);
    final l = lhs.analysis(context);

    if (l == null || r == null) return l;
    return context.createVal(r, l.ident);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final r = rhs.grt(context);
    final l = lhs.build(context, baseTy: r);
    final lv = l?.variable;
    if (l == null || lv == null) return null;

    final value = AsBuilder.asType(context, lv, rhs.ident, r);
    return ExprTempValue(value);
  }

  @override
  Expr cloneSelf() {
    return AsExpr(lhs.clone(), rhs);
  }

  @override
  String toString() {
    return '$lhs as $rhs';
  }
}
