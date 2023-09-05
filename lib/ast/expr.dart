// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../abi/abi_fn.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'buildin.dart';
import 'context.dart';
import 'llvm/variables.dart';
import 'memory.dart';
import 'stmt.dart';
import 'tys.dart';

class LiteralExpr extends Expr {
  LiteralExpr(this.ident, this.ty);
  final Identifier ident;
  final BuiltInTy ty;
  @override
  Expr clone() {
    return LiteralExpr(ident, ty);
  }

  @override
  String toString() {
    final isStr = ty.ty == LitKind.kStr;
    var v = isStr
        ? ident.src.replaceAll('\\\\', '\\').replaceAll('\n', '\\n')
        : ident.src;
    return '$v[:$ty]';
  }

  static T run<T>(T Function() body, Ty? ty) {
    return runZoned(body, zoneValues: {#ty: ty});
  }

  static Ty? get letTy {
    final r = Zone.current[#ty];
    if (r is Ty) {
      return r;
    }
    return null;
  }

  BuiltInTy get realTy {
    final r = Zone.current[#ty];
    if (r is BuiltInTy) {
      if (ty.ty.isNum && !r.ty.isNum) {
        return ty;
      }
      return r;
    }
    return ty;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v = realTy.llvmType.createValue(ident: ident);

    return ExprTempValue(v, ty, ident);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return context.createVal(realTy, ident);
  }
}

class IfExprBlock {
  IfExprBlock(this.expr, this.block);

  final Expr expr;
  final Block block;
  IfExprBlock? child;
  Block? elseBlock;

  IfExprBlock clone() {
    return IfExprBlock(expr.clone(), block.clone());
  }

  void incLvel([int count = 1]) {
    block.incLevel(count);
  }

  @override
  String toString() {
    return '$expr$block';
  }

  AnalysisVariable? analysis(AnalysisContext context) {
    expr.analysis(context);
    block.analysis(context);
    return retFromBlock(block, context);
  }

  static AnalysisVariable? retFromBlock(Block block, AnalysisContext context) {
    if (block.stmts.isNotEmpty) {
      final last = block.stmts.last;
      if (last is ExprStmt) {
        final expr = last.expr;
        if (expr is! RetExpr) {
          return expr.analysis(context);
        }
      }
    }
    return null;
  }
}

class IfExpr extends Expr {
  IfExpr(this.ifExpr, this.elseIfExpr, this.elseBlock) {
    IfExprBlock last = ifExpr;
    if (elseIfExpr != null) {
      for (var e in elseIfExpr!) {
        last.child = e;
        last = e;
      }
    }
    last.elseBlock = elseBlock;
  }

  @override
  Expr clone() {
    return IfExpr(ifExpr.clone(), elseIfExpr?.map((e) => e.clone()).toList(),
        elseBlock?.clone())
      .._variable = _variable;
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    elseBlock?.incLevel(count);
    ifExpr.incLvel(count);
    elseIfExpr?.forEach((element) {
      element.incLvel(count);
    });
  }

  final IfExprBlock ifExpr;
  final List<IfExprBlock>? elseIfExpr;
  final Block? elseBlock;

  @override
  String toString() {
    final el = elseBlock == null ? '' : ' else$elseBlock';
    final elIf =
        elseIfExpr == null ? '' : ' else if ${elseIfExpr!.join(' else if ')}';

    return 'if $ifExpr$elIf$el';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v =
        createIfBlock(ifExpr, context, LiteralExpr.letTy ?? _variable?.ty);
    if (v == null) return null;
    return ExprTempValue(v, v.ty, Identifier.none);
  }

  StoreVariable? createIfBlock(IfExprBlock ifb, BuildContext context, Ty? ty) {
    StoreVariable? variable;
    if (ty != null) {
      variable = ty.llvmType.createAlloca(context, Identifier.none, null);
    }
    buildIfExprBlock(ifb, context, variable);

    return variable;
  }

  static void _blockRetValue(
      Block block, BuildContext context, StoreVariable? variable) {
    if (variable == null) return;
    if (block.stmts.isNotEmpty) {
      final lastStmt = block.stmts.last;
      if (lastStmt is ExprStmt) {
        final expr = lastStmt.expr;
        if (expr is! RetExpr) {
          // 获取缓存的value
          final temp = expr.build(context);
          final val = temp?.variable;
          if (val == null) {
            // error
          } else {
            if (val is LLVMAllocaDelayVariable) {
              val.create(context, variable);
            } else {
              final v = val.load(context, temp!.currentIdent.offset);
              variable.store(context, v, Offset.zero);
            }
          }
        }
      }
    }
  }

  void buildIfExprBlock(
      IfExprBlock ifEB, BuildContext c, StoreVariable? variable) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = c.buildSubBB(name: 'then');
    final afterBB = c.buildSubBB(name: 'after');
    LLVMBasicBlock? elseBB;

    final conTemp = ifEB.expr.build(c);
    final con = conTemp?.variable;
    if (con == null) return;

    final conv = c
        .math(con, (context) => null, OpKind.Ne)
        .load(c, conTemp!.currentIdent.offset);

    c.appendBB(then);
    ifEB.block.build(then.context);

    if (onlyIf) {
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, afterBB.bb);
    } else {
      elseBB = c.buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, elseBB.bb);
      c.appendBB(elseBB);

      if (elseifBlock != null) {
        buildIfExprBlock(elseifBlock, elseBB.context, variable);
      } else if (elseBlock != null) {
        elseBlock.build(elseBB.context);
      }
    }
    var canBr = then.context.canBr;
    if (canBr) {
      _blockRetValue(ifEB.block, then.context, variable);
      then.context.br(afterBB.context);
    }

    if (elseBB != null) {
      final elseCanBr = elseBB.context.canBr;
      // canBr |= elseCanBr;
      if (elseCanBr) {
        if (elseBlock != null) {
          _blockRetValue(elseBlock, elseBB.context, variable);
        } else if (elseifBlock != null) {
          _blockRetValue(elseifBlock.block, elseBB.context, variable);
        }
        elseBB.context.br(afterBB.context);
      }
    }

    c.insertPointBB(afterBB);
  }

  AnalysisVariable? _variable;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    _variable = ifExpr.analysis(context.childContext());
    if (elseIfExpr != null) {
      for (var e in elseIfExpr!) {
        e.analysis(context.childContext());
      }
    }
    elseBlock?.analysis(context.childContext());
    return _variable;
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
  ExprTempValue? buildExpr(BuildContext context) {
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
  ExprTempValue? buildExpr(BuildContext context) {
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
  ExprTempValue? buildExpr(BuildContext context) {
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
  ExprTempValue? buildExpr(BuildContext context) {
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

class RetExpr extends Expr {
  RetExpr(this.expr, this.ident);
  final Identifier ident;
  final Expr? expr;
  @override
  Expr clone() {
    return RetExpr(expr?.clone(), ident);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final e = expr?.build(context);

    context.ret(
        e?.variable, e?.currentIdent.offset ?? Offset.zero, ident.offset);
    return e;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    if (expr == null) return null;
    return analysisAll(context, expr!, ident);
  }

  static AnalysisVariable? analysisAll(AnalysisContext context, Expr expr,
      [Identifier? currentIdent]) {
    final val = expr.analysis(context);
    final current = context.getLastFnContext();
    if (val != null && current != null) {
      final valLife = val.lifecycle.fnContext;
      if (valLife != null) {
        if (val.kind.isRef) {
          if (val.lifecycle.isInner && current.isChildOrCurrent(valLife)) {
            final ident = currentIdent ?? val.lifeIdent ?? val.ident;
            Log.e('lifecycle Error: (${context.currentPath}'
                ':${ident.offset.pathStyle})\n${ident.light}');
          }
        }
      }
    }

    if (val != null) {
      final vals = current?.currentFn?.sretVariables;
      if (vals != null) {
        final all = val.allParent;
        all.insert(0, val);

        // 判断是否同源， 用于`sret`, struct ret
        //
        // let y = Foo { 1, 2}
        // if condition {
        //  return y;
        // } else {
        //  let x = y;
        //  return x; // 与 `y` 同源
        // }
        final isSameRoot =
            vals.isEmpty || all.any((e) => vals.contains(e.ident.toRawIdent));
        if (isSameRoot) {
          for (var val in all) {
            final ident = val.ident.toRawIdent;
            vals.add(ident);
          }
        }
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'return $expr [Ret]';
  }
}

// struct: CS{ name: "struct" }
class StructExpr extends Expr {
  StructExpr(this.ident, this.fields, this.generics);
  final Identifier ident;
  final List<FieldExpr> fields;
  final List<PathTy> generics;

  @override
  Expr clone() {
    return StructExpr(ident, fields.map((e) => e.clone()).toList(), generics);
  }

  @override
  String toString() {
    return '$ident${generics.str}{${fields.join(',')}}';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    var struct = context.getStruct(ident);
    var genericsInst = generics;
    if (struct == null) {
      final cty = context.getAliasTy(ident);
      final t = cty?.getTy(context, genericsInst);
      if (t is! StructTy) return null;

      genericsInst = const [];
      struct = t;
    }

    return buildTupeOrStruct(struct, context, ident, fields, genericsInst);
  }

  static T resolveGeneric<T extends Ty>(NewInst<T> t, Tys context,
      List<FieldExpr> params, List<PathTy> genericsInst) {
    final fields = t.fields;
    final generics = t.generics;
    var nt = t as T;
    if (genericsInst.isNotEmpty) {
      nt = t.newInstWithGenerics(context, genericsInst, generics, extra: t.tys);
    } else if (t.tys.length < generics.length) {
      final gMap = <Identifier, Ty>{}..addAll(t.tys);

      final sg = generics;

      // 从上下文中获取具体类型
      for (var g in sg) {
        final tyVal = context.getTy(g.ident);
        if (tyVal != null) {
          gMap.putIfAbsent(g.ident, () => tyVal);
        }
      }
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));

      // x: Arc<Gen<T>> => first fdTy => Arc<Gen<T>>
      // child fdTy:  Gen<T> => T => real type
      void visitor(Ty ty, PathTy fdTy) {
        final index = sg.indexWhere((e) => e.ident == fdTy.ident);
        if (index != -1) {
          final gen = sg[index];
          if (gen.rawTy.generics.isNotEmpty && ty is PathInterFace) {
            for (var f in gen.rawTy.generics) {
              final tyg = (ty as PathInterFace).tys[f.ident];
              visitor(tyg!, f);
            }
          }
          gMap.putIfAbsent(fdTy.ident, () => ty);
        }

        if (fdTy.generics.isNotEmpty && ty is PathInterFace) {
          for (var i = 0; i < fdTy.generics.length; i += 1) {
            final fdIdent = fdTy.generics[i];
            final tyg = (ty as PathInterFace).tys[fdIdent.ident];
            visitor(tyg!, fdIdent);
          }
        }
      }

      bool isBuild = context is BuildContext;
      Ty? gen(Identifier ident) {
        return gMap[ident];
      }

      for (var i = 0; i < sortFields.length; i += 1) {
        final f = sortFields[i];
        final fd = fields[i].rawTy;

        Ty? ty;
        if (isBuild) {
          ty = LiteralExpr.run(() => f.build(context)?.variable,
                  fd.grtOrT(context, gen: gen))
              ?.ty;
        } else {
          ty = LiteralExpr.run(() => f.analysis(context as AnalysisContext),
                  fd.grtOrT(context, gen: gen))
              ?.ty;
        }
        if (ty != null) {
          final fd = fields[i];
          visitor(ty, fd.rawTy);
        }
      }

      nt = t.newInst(gMap, context);
    }
    return nt;
  }

  static ExprTempValue? buildTupeOrStruct(StructTy struct, BuildContext context,
      Identifier ident, List<FieldExpr> params, List<PathTy> genericsInst) {
    struct = resolveGeneric(struct, context, params, genericsInst);
    final structType = struct.llvmType.createType(context);
    LLVMValueRef create([StoreVariable? alloca, Identifier? nIdent]) {
      var value = alloca;
      // final min = struct.llvmType.getMaxSize(context);
      var fields = struct.fields;
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));
      // final size = min > 4 ? 8 : 4;

      value ??= struct.llvmType
          .createAlloca(context, nIdent ?? Identifier.none, null);

      context.diSetCurrentLoc(ident.offset);

      if (value is LLVMAllocaDelayVariable) {
        value.create(context, null, nIdent);
      }

      if (sortFields.length != fields.length) {
        value.store(context, llvm.LLVMConstNull(structType), Offset.zero);
        // final base = value.getBaseValue(context);
        // final len = struct.llvmType.getBytes(context);
        // final align = llvm.LLVMGetAlignment(base);
        // // final vb = llvm.LLVMBuildBitCast(
        // //     context.builder, base, context.pointer(), unname);
        // llvm.LLVMBuildMemSet(context.builder, base, context.constI8(0),
        //     BuiltInTy.constUsize(context, len), align);
      }
      if (value is LLVMAllocaDelayVariable) {
        value.create(context, null, nIdent ?? ident);
      }
      for (var i = 0; i < sortFields.length; i++) {
        final f = sortFields[i];
        final fd = fields[i];

        final temp = LiteralExpr.run(() => f.build(context), fd.grt(context));
        final v = temp?.variable;
        if (v == null) continue;
        final vv = struct.llvmType.getField(value, context, fd.ident)!;
        if (v is LLVMAllocaDelayVariable) {
          final result = v.create(context, vv);
          if (result) {
            continue;
          }
        }

        final loadOffset = temp!.currentIdent.offset;
        var offset = f.ident?.offset ?? loadOffset;

        vv.store(context, v.load(context, loadOffset), offset);
        // llvm.LLVMSetAlignment(store, size);
      }
      return value.alloca;
    }

    final value = LLVMAllocaDelayVariable(struct, null, create, structType);

    return ExprTempValue(value, value.ty, ident);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var struct = context.getStruct(ident);
    if (struct == null) return null;
    struct = resolveGeneric(struct, context, fields, generics);

    final sortFields = alignParam(
        fields, (p) => struct!.fields.indexWhere((e) => e.ident == p.ident));

    final all = <Identifier, AnalysisVariable>{};
    for (var i = 0; i < sortFields.length; i++) {
      final f = sortFields[i];
      final structF = struct.fields[i];
      final v = f.expr.analysis(context);
      if (v == null) continue;
      all[structF.ident] = v;
    }
    return context.createStructVal(struct, ident, all);
  }
}

// class StructExprField {
//   StructExprField(this.ident, this.expr);
//   final Identifier? ident;
//   final Expr expr;
//   StructExprField clone() {
//     return StructExprField(ident, expr.clone());
//   }

//   @override
//   String toString() {
//     return '$ident: $expr';
//   }

//   ExprTempValue? build(BuildContext context) {
//     return expr.build(context);
//   }
// }

class AssignExpr extends Expr {
  AssignExpr(this.ref, this.expr);
  final Expr ref;
  final Expr expr;
  @override
  Expr clone() {
    return AssignExpr(ref.clone(), expr.clone());
  }

  @override
  bool get hasUnknownExpr => ref.hasUnknownExpr || expr.hasUnknownExpr;

  @override
  String toString() {
    return '$ref = $expr';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final lhs = ref.build(context);
    final rhs = LiteralExpr.run(() => expr.build(context), lhs?.ty);

    final lVariable = lhs?.variable;
    final rVariable = rhs?.variable;

    if (lVariable is StoreVariable && rVariable != null) {
      lVariable.store(
          context,
          rVariable.load(context, rhs!.currentIdent.offset),
          lhs!.currentIdent.offset);
    }

    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final lhs = ref.analysis(context);
    final rhs = expr.analysis(context);
    if (lhs != null) {
      if (rhs != null) {
        if (rhs.kind.isRef) {
          if (rhs.lifecycle.isInner && lhs.lifecycle.isOut) {
            final ident = rhs.lifeIdent ?? rhs.ident;
            Log.e('lifecycle Error: (${context.currentPath}'
                ':${ident.offset.pathStyle})\n${ident.light}');
          }
        }
      }

      return lhs;
    }
    return null;
  }
}

class AssignOpExpr extends AssignExpr {
  AssignOpExpr(this.op, this.opIdent, super.ref, super.expr);
  final OpKind op;
  final Identifier opIdent;
  @override
  Expr clone() {
    return AssignOpExpr(op, opIdent, ref.clone(), expr.clone());
  }

  @override
  String toString() {
    return '$ref ${op.op}= $expr';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final lhs = ref.build(context);
    final lVariable = lhs?.variable;

    if (lVariable is StoreVariable) {
      final val = LiteralExpr.run(
          () => OpExpr.math(
              context, op, lVariable, expr, opIdent, lhs!.currentIdent),
          lVariable.ty);
      final rValue = val?.variable;
      if (rValue != null) {
        lVariable.store(context, rValue.load(context, val!.currentIdent.offset),
            lhs!.currentIdent.offset);
      }
    }

    return null;
  }
}

class FieldExpr extends Expr {
  FieldExpr(this.expr, this.ident);
  final Identifier? ident;
  final Expr expr;

  @override
  FieldExpr clone() {
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
  ExprTempValue? buildExpr(BuildContext context) {
    return expr.build(context);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return expr.analysis(context);
  }

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;
}

List<F> alignParam<F>(List<F> src, int Function(F) test) {
  final sortFields = <F>[];
  final fieldMap = <int, F>{};

  for (var i = 0; i < src.length; i++) {
    final p = src[i];
    final index = test(p);
    if (index != -1) {
      fieldMap[index] = p;
    } else {
      sortFields.add(p);
    }
  }

  var index = 0;
  for (var i = 0; i < sortFields.length; i++) {
    final p = sortFields[i];
    while (true) {
      if (fieldMap.containsKey(index)) {
        index++;
        continue;
      }
      fieldMap[index] = p;
      break;
    }
  }

  sortFields.clear();
  final keys = fieldMap.keys.toList()..sort();
  for (var k in keys) {
    final v = fieldMap[k];
    if (v != null) {
      sortFields.add(v);
    }
  }

  return sortFields;
}

class FnExpr extends Expr {
  FnExpr(this.fn);
  final Fn fn;
  @override
  Expr clone() {
    return FnExpr(fn.cloneDefault());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    fn.incLevel(count);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final fnV = fn.build();
    if (fnV == null) return null;

    return ExprTempValue(fnV, fn, Identifier.none);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    fn.analysis(context);
    return context.createVal(fn, fn.fnSign.fnDecl.ident);
  }

  @override
  String toString() {
    return '$fn';
  }
}

mixin FnCallMixin {
  Map<Identifier, Set<AnalysisVariable>> get childrenVariables {
    return _catchMapFns.map((key, value) => MapEntry(key, value()));
  }

  Set<AnalysisVariable> get catchVariables {
    final cache = <AnalysisVariable>{};
    for (var v in _catchFns) {
      cache.addAll(v());
    }
    return cache;
  }

  final _catchFns = <Set<AnalysisVariable> Function()>[];
  final _catchMapFns = <Identifier, Set<AnalysisVariable> Function()>{};

  void addChild(Identifier ident, Fn fnty) {
    ff() => fnty.variables;
    _catchFns.add(ff);
    _catchMapFns[ident] = ff;
  }

  void autoAddChild(Fn fn, List<FieldExpr> params, AnalysisContext context) {
    // ignore: invalid_use_of_protected_member
    final fields = fn.fnSign.fnDecl.params;
    final sortFields =
        alignParam(params, (p) => fields.indexWhere((e) => e.ident == p.ident));
    for (var f in sortFields) {
      Ty? vty;
      Identifier? ident;
      final index = sortFields.indexOf(f);
      if (index < fields.length) {
        final rf = fields[index];
        ident = rf.ident;
        final v = f.analysis(context);
        vty = v?.ty;
      } else {
        final fpv = f.analysis(context);
        vty = fpv?.ty;
        ident = fpv?.ident;
      }
      if (vty is Fn && ident != null) {
        addChild(ident, vty);
      }
    }
  }

  ExprTempValue? fnCall(
    BuildContext context,
    Fn fn,
    List<FieldExpr> params,
    Identifier currentIdent, {
    Variable? struct,
  }) {
    return AbiFn.fnCallInternal(context, fn, params, struct, catchVariables,
        childrenVariables, currentIdent);
  }
}

extension GenericsPathTy on List<PathTy> {
  String get str {
    if (isEmpty) return '';
    return '<${join(',')}>';
  }
}

class FnCallExpr extends Expr with FnCallMixin {
  FnCallExpr(this.expr, this.params);
  final Expr expr;
  final List<FieldExpr> params;

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;

  @override
  Expr clone() {
    final f = FnCallExpr(expr.clone(), params.map((e) => e.clone()).toList());
    f._catchFns.addAll(_catchFns);
    f._catchMapFns.addAll(_catchMapFns);
    return f;
  }

  @override
  String toString() {
    return '$expr(${params.join(',')})';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final fnV = expr.build(context);
    final variable = fnV?.variable;
    final fn = variable?.ty ?? fnV?.ty;
    if (fn is StructTy) {
      return StructExpr.buildTupeOrStruct(
          fn, context, Identifier.none, params, const []);
    }

    if (fn is SizeOfFn) {
      if (params.isEmpty) {
        return null;
      }
      final first = params.first;
      final e = first.expr.build(context);
      Ty? ty = e?.ty;
      if (ty == null) {
        var e = first.expr;
        if (e is RefExpr) {
          e = e.current;
        }
        if (e is VariableIdentExpr) {
          final p = PathTy(e.ident, e.generics);
          ty = p.grt(context);
        }
      }
      if (ty == null) return null;

      final v = fn.llvmType.build(context, ty);
      return ExprTempValue(v, BuiltInTy.i32, fnV!.currentIdent);
    }
    if (fn is! Fn) return null;

    final fnInst = StructExpr.resolveGeneric(fn, context, params, []);

    return fnCall(context, fnInst, params, fnV!.currentIdent);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final fn = expr.analysis(context);
    if (fn == null) return null;
    final fnty = fn.ty;
    if (fnty is StructTy) {
      final struct = StructExpr.resolveGeneric(fnty, context, params, []);
      final sortFields = alignParam(
          params, (p) => struct.fields.indexWhere((e) => e.ident == p.ident));

      final all = <Identifier, AnalysisVariable>{};
      for (var i = 0; i < sortFields.length; i++) {
        final f = sortFields[i];
        final structF = struct.fields[i];
        final v = f.expr.analysis(context);
        if (v == null) continue;
        all[structF.ident] = v;
      }
      return context.createStructVal(struct, struct.ident, all);
    }
    if (fn.ty is SizeOfFn) {
      return context.createVal(BuiltInTy.usize, Identifier.none);
    }
    if (fnty is! Fn) return null;
    final fnnn = StructExpr.resolveGeneric(fnty, context, params, []);
    fnnn.analysis(context);
    autoAddChild(fnnn, params, context);

    return context.createVal(
        fnnn.fnSign.fnDecl.returnTy.grt(context), Identifier.none);
  }
}

class MethodCallExpr extends Expr with FnCallMixin {
  MethodCallExpr(this.ident, this.receiver, this.params);
  final Identifier ident;
  final Expr receiver;
  final List<FieldExpr> params;

  @override
  bool get hasUnknownExpr => receiver.hasUnknownExpr;

  @override
  Expr clone() {
    return MethodCallExpr(
        ident, receiver.clone(), params.map((e) => e.clone()).toList())
      .._catchFns.addAll(_catchFns)
      .._paramFn = _paramFn
      .._catchMapFns.addAll(_catchMapFns);
  }

  @override
  String toString() {
    if (receiver is OpExpr) {
      return '($receiver).$ident(${params.join(',')})';
    }
    return '$receiver.$ident(${params.join(',')})';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final variable = receiver.build(context);
    final fnName = ident.src;

    var val = variable?.variable;

    if (val is Deref) {
      val = val.getDeref(context);
    }
    var valTy = val?.ty ?? variable?.ty;
    if (valTy == null) return null;

    if (valTy is RefTy) {
      valTy = valTy.parent;
    }

    /// TODO: 将内部实现迁移到[GlobalContext]
    if (valTy is ArrayTy && variable != null && val != null) {
      if (fnName == 'elementAt' && params.isNotEmpty) {
        final first = LiteralExpr.run(
            () => params.first.build(context)?.variable, BuiltInTy.usize);

        if (first != null && first.ty is BuiltInTy) {
          final element = valTy.llvmType.getElement(
              context, val, first.load(context, variable.currentIdent.offset));
          return ExprTempValue(element, element.ty, ident);
        }
      } else if (fnName == 'getSize') {
        final size = BuiltInTy.usize.llvmType
            .createValue(ident: Identifier.builtIn('${valTy.size}'));
        return ExprTempValue(size, size.ty, ident);
      } else if (fnName == 'toStr') {
        final element = valTy.llvmType.toStr(context, val);
        return ExprTempValue(element, element.ty, ident);
      }
    }

    if (valTy is StructTy && variable != null && val != null) {
      if (valTy.ident.src == 'CArray') {
        if (fnName == 'elementAt' && params.isNotEmpty) {
          final param = LiteralExpr.run(
              () => params.first.build(context), BuiltInTy.usize);
          final paramValue = param?.variable;
          if (paramValue != null && paramValue.ty is BuiltInTy) {
            final ty = valTy.tys.values.first;
            Variable getElement(
                BuildContext c, Variable value, LLVMValueRef index) {
              final indics = <LLVMValueRef>[index];

              final p = value.load(c, variable.currentIdent.offset);
              final elementTy = ty.llvmType.createType(c);
              var ety = ty;
              if (ty is RefTy) {
                ety = ty.parent;
              }

              c.diSetCurrentLoc(ident.offset);

              var v = llvm.LLVMBuildInBoundsGEP2(c.builder, elementTy, p,
                  indics.toNative(), indics.length, unname);
              v = llvm.LLVMBuildLoad2(c.builder, c.pointer(), v, unname);
              final vv = ety.llvmType.createAlloca(c, Identifier.none, v);
              return vv;
            }

            final v = valTy.llvmType
                .getField(val, context, Identifier.builtIn('ptr'));
            final element = getElement(context, v!,
                paramValue.load(context, param!.currentIdent.offset));
            return ExprTempValue(element, element.ty, ident);
          }
        }
      }
    }

    var structTy = valTy;
    final ty = LiteralExpr.letTy;

    if (structTy is StructTy) {
      if (structTy.tys.isEmpty) {
        if (ty is StructTy && structTy.ident == ty.ident) {
          structTy = ty;
        }
      }
    }

    final impl = context.getImplForStruct(structTy, ident);

    var implFn = impl?.getFn(ident);
    implFn = implFn?.copyFrom(structTy);
    Fn? fn = implFn;

    if (structTy is StructTy) {
      if (structTy.ident.src == 'Array') {
        if (fnName == 'new') {
          if (params.isNotEmpty) {
            final first = LiteralExpr.run(
                () => params.first.build(context)?.variable, BuiltInTy.usize);

            if (first is LLVMLitVariable) {
              if (structTy.tys.isNotEmpty) {
                final arr =
                    ArrayTy(structTy.tys.values.first, first.value.iValue);
                final element =
                    arr.llvmType.createAlloca(context, Identifier.none, null);

                return ExprTempValue(element, element.ty, ident);
              }
            }
          }
          return null;
        }
      }
    }

    // 字段有可能是一个函数指针
    if (fn == null) {
      if (val is StoreVariable && structTy is StructTy) {
        final field = structTy.llvmType.getField(val, context, ident);
        if (field != null) {
          // 匿名函数作为参数要处理捕捉的变量
          if (field.ty is FnTy) {
            assert(_paramFn is Fn, 'ty: ${field.ty}, _paramFn: $_paramFn');
            fn = _paramFn ?? field.ty as FnTy;
          }
        }
      }
    }
    if (fn == null) return null;

    return fnCall(context, fn, params, ident, struct: val);
  }

  Fn? _paramFn;

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var variable = receiver.analysis(context);
    if (variable == null) return null;
    var structTy = variable.ty;
    if (structTy is! StructTy) return null;

    final ty = LiteralExpr.letTy;

    if (structTy.tys.isEmpty) {
      if (ty is StructTy && structTy.ident == ty.ident) {
        structTy = ty;
      }
    }

    if (variable is AnalysisStructVariable) {
      final p = variable.getParam(ident);
      final pp = p?.ty;
      if (pp is Fn) {
        _paramFn = pp;
        autoAddChild(pp, params, context);
      }
      if (p != null) return p;
    }

    final impl = context.getImplForStruct(structTy, ident);

    Fn? fn = impl?.getFn(ident)?.copyFrom(structTy);
    if (fn == null) {
      final field =
          structTy.fields.firstWhereOrNull((element) => element.ident == ident);
      final ty = field?.grtOrT(context);
      if (ty is FnTy) {
        fn = ty;
        autoAddChild(fn, params, context);
      }
    }
    if (fn == null) return null;
    fn = StructExpr.resolveGeneric(fn, context, params, []);

    fn.analysis(context.getLastFnContext() ?? context);

    // final fnContext = context.getLastFnContext();
    // fnContext?.addChild(fn.fnSign.fnDecl.ident, fn.variables);
    return context.createVal(fn.getRetTy(context), Identifier.none);
  }
}

class StructDotFieldExpr extends Expr {
  StructDotFieldExpr(this.struct, this.ident);
  final Identifier ident;
  final Expr struct;

  @override
  bool get hasUnknownExpr => struct.hasUnknownExpr;

  @override
  Expr clone() {
    return StructDotFieldExpr(struct.clone(), ident);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final structVal = struct.build(context);
    final val = structVal?.variable;
    var newVal = val;

    // while (true) {
    //   if (newVal is! Deref) {
    //     break;
    //   }
    //   final v = newVal.getDeref(context);
    //   if (v == newVal) break;
    //   newVal = v;
    // }
    if (newVal is Deref) {
      newVal = newVal.getDeref(context);
    }
    var ty = newVal?.ty;

    if (ty is! StructTy) return null;
    final v = ty.llvmType.getField(newVal!, context, ident);
    if (v == null) return null;
    return ExprTempValue(v, v.ty, ident);
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
    if (variable is AnalysisStructVariable) {
      final p = variable.getParam(ident);
      return p;
    }
    // error

    final v =
        structTy.fields.firstWhereOrNull((element) => element.ident == ident);
    if (v == null) {
      return null;
    }

    final vv = context.createVal(v.grt(context), ident);
    vv.lifecycle.fnContext = variable.lifecycle.fnContext;
    return vv;
  }
}

enum OpKind {
  /// The `+` operator (addition)
  Add('+', 70),

  /// The `-` operator (subtraction)
  Sub('-', 70),

  /// The `*` operator (multiplication)
  Mul('*', 80),

  /// The `/` operator (division)
  Div('/', 80),

  /// The `%` operator (modulus)
  Rem('%', 80),

  /// The `&&` operator (logical and)
  And('&&', 31),

  /// The `||` operator (logical or)
  Or('||', 30),

  // /// The `!` operator (not)
  // Not('!', 100),

  /// The `^` operator (bitwise xor)
  BitXor('^', 41),

  /// The `&` operator (bitwise and)
  BitAnd('&', 52),

  /// The `|` operator (bitwise or)
  BitOr('|', 50),

  /// The `<<` operator (shift left)
  Shl('<<', 60),

  /// The `>>` operator (shift right)
  Shr('>>', 60),

  /// The `==` operator (equality)
  Eq('==', 40),

  /// The `<` operator (less than)
  Lt('<', 41),

  /// The `<=` operator (less than or equal to)
  Le('<=', 41),

  /// The `!=` operator (not equal to)
  Ne('!=', 40),

  /// The `>=` operator (greater than or equal to)
  Ge('>=', 41),

  /// The `>` operator (greater than)
  Gt('>', 41),
  ;

  final String op;
  const OpKind(this.op, this.level);
  final int level;

  static OpKind? from(String src) {
    return values.firstWhereOrNull((element) => element.op == src);
  }

  int? getICmpId(bool isSigned) {
    if (index < Eq.index) return null;
    int? i;
    switch (this) {
      case Eq:
        return LLVMIntPredicate.LLVMIntEQ;
      case Ne:
        return LLVMIntPredicate.LLVMIntNE;
      case Gt:
        i = LLVMIntPredicate.LLVMIntUGT;
        break;
      case Ge:
        i = LLVMIntPredicate.LLVMIntUGE;
        break;
      case Lt:
        i = LLVMIntPredicate.LLVMIntULT;
        break;
      case Le:
        i = LLVMIntPredicate.LLVMIntULE;
        break;
      default:
    }
    if (i != null && isSigned) {
      return i + 4;
    }
    return i;
  }

  int? getFCmpId(bool isSigned) {
    if (index < Eq.index) return null;
    int? i;

    switch (this) {
      case Eq:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOEQ
            : LLVMRealPredicate.LLVMRealUEQ;
        break;
      case Ne:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealONE
            : LLVMRealPredicate.LLVMRealUNE;
        break;
      case Gt:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOGT
            : LLVMRealPredicate.LLVMRealUGT;
        break;
      case Ge:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOGE
            : LLVMRealPredicate.LLVMRealUGE;
        break;
      case Lt:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOLT
            : LLVMRealPredicate.LLVMRealULT;
        break;
      case Le:
        i = isSigned
            ? LLVMRealPredicate.LLVMRealOLE
            : LLVMRealPredicate.LLVMRealULE;
        break;
      default:
    }

    return i;
  }
}

class OpExpr extends Expr {
  OpExpr(this.op, this.lhs, this.rhs, this.opIdent);
  final OpKind op;
  final Expr lhs;
  final Expr rhs;

  final Identifier opIdent;

  @override
  bool get hasUnknownExpr => lhs.hasUnknownExpr || rhs.hasUnknownExpr;

  @override
  Expr clone() {
    return OpExpr(op, lhs.clone(), rhs.clone(), opIdent);
  }

  @override
  String toString() {
    var rs = '$rhs';
    var ls = '$lhs';

    var rc = rhs;
    if (rc is RefExpr) {
      if (rc.current is OpExpr) {
        rc = rc.current;
      }
    }

    if (rc is OpExpr) {
      if (op.level > rc.op.level) {
        rs = '($rs)';
      }
    }
    var lc = lhs;
    if (lc is RefExpr) {
      if (lc.current is OpExpr) {
        lc = lc.current;
      }
    }
    if (lc is OpExpr) {
      if (op.level > lc.op.level) {
        ls = '($ls)';
      }
    }

    var ss = '$ls ${op.op} $rs';
    return ss;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    var l = lhs.build(context);
    var r = LiteralExpr.run(() => rhs.clone().build(context), l?.ty);
    if (l == null || r == null) return null;
    if (l.ty != r.ty) {
      final nl = LiteralExpr.run(() => lhs.clone().build(context), r.ty);
      if (nl == null) return null;
      l = nl;
    }

    return math(context, op, l.variable, rhs, opIdent, l.currentIdent);
  }

  static ExprTempValue? math(BuildContext context, OpKind op, Variable? l,
      Expr? rhs, Identifier opIdent, Identifier lhsIdent) {
    if (l == null) return null;

    final v = context.math(l, (context) {
      return LiteralExpr.run(() => rhs?.build(context), l.ty);
    }, op, lhsOffset: lhsIdent.offset, opOffset: opIdent.offset);

    return ExprTempValue(v, v.ty, lhsIdent);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final l = lhs.analysis(context);
    // final r = lhs.analysis(context);
    if (l == null) return null;
    if (op.index >= OpKind.Eq.index && op.index <= OpKind.Gt.index ||
        op.index >= OpKind.And.index && op.index <= OpKind.Or.index) {
      return context.createVal(BuiltInTy.kBool, Identifier.none);
    }
    return context.createVal(l.ty, Identifier.none);
  }
}

enum PointerKind {
  deref('*'),
  none(''),
  ref('&');

  final String char;
  const PointerKind(this.char);

  static PointerKind? from(TokenKind kind) {
    if (kind == TokenKind.and) {
      return PointerKind.ref;
    } else if (kind == TokenKind.star) {
      return PointerKind.deref;
    }
    return null;
  }

  Variable? refDeref(Variable? val, BuildContext c) {
    if (this == PointerKind.none) return val;
    Variable? inst;
    if (val != null) {
      if (val is Deref && this == PointerKind.deref) {
        inst = val.getDeref(c);
      } else if (this == PointerKind.ref) {
        inst = val.getRef(c);
      }
    }
    return inst ?? val;
  }

  static Variable? refDerefs(Variable? val, BuildContext c, PointerKind kind) {
    if (val == null) return val;
    Variable? vv = val;
    // for (var k in kind.reversed) {
    vv = kind.refDeref(vv, c);
    // }
    return vv;
  }

  @override
  String toString() => char == '' ? '$runtimeType' : char;
}

extension ListPointerKind on List<PointerKind> {
  bool get isRef {
    var refCount = 0;
    for (var k in reversed) {
      if (k == PointerKind.ref) {
        refCount += 1;
      } else {
        refCount -= 1;
      }
    }
    return refCount > 0;
  }

  List<PointerKind> drefRef() {
    final list = <PointerKind>[];
    for (var v in this) {
      if (v == PointerKind.ref) {
        list.add(PointerKind.deref);
      } else if (v == PointerKind.deref) {
        list.add(PointerKind.ref);
      } else {
        list.add(v);
      }
    }
    return list;
  }

  Ty resolveTy(Ty baseTy) {
    for (var kind in this) {
      if (kind == PointerKind.ref || kind == PointerKind.deref) {
        baseTy = RefTy(baseTy);
      } else {
        if (baseTy is RefTy) {
          baseTy = baseTy.parent;
        }
      }
    }
    return baseTy;
  }
}

class VariableIdentExpr extends Expr {
  VariableIdentExpr(this.ident, this.generics);
  final Identifier ident;
  final List<PathTy> generics;
  @override
  String toString() {
    return '$ident${generics.str}';
  }

  @override
  Expr clone() {
    return VariableIdentExpr(ident, generics).._isCatch = _isCatch;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    if (ident.src == 'print') {
      Log.w('....');
    }
    if (ident.src == 'null') {
      final letTy = LiteralExpr.letTy;
      final ty = letTy?.llvmType.createType(context);

      if (ty == null) {
        return ExprTempValue(null, BuiltInTy.kVoid, ident);
      }
      final v = LLVMConstVariable(llvm.LLVMConstNull(ty), letTy!);
      return ExprTempValue(v, v.ty, ident);
    }
    // if (ident.src == 'nullptr') {
    //   final letTy = LiteralExpr.letTy;
    //   final ty = letTy?.llvmType.createType(context);

    //   if (ty == null) {
    //     return ExprTempValue(null, BuiltInTy.kVoid);
    //   }

    //   final v = LLVMConstVariable(llvm.LLVMConstPointerNull(ty), letTy!);
    //   return ExprTempValue(v, v.ty);
    // }
    final val = context.getVariable(ident);
    if (val != null) {
      if (val is Deref) {
        if (ident.src == 'self') {
          final newVal = val.getDeref(context);
          return ExprTempValue(newVal, newVal.ty, ident);
        }
      }
      return ExprTempValue(val, val.ty, ident);
    }

    final typeAlias = context.getAliasTy(ident);
    var struct = context.getStruct(ident);
    var localGenerics = generics;
    if (struct == null) {
      struct = typeAlias?.getTy(context, generics);
      if (struct != null) {
        localGenerics = const [];
      }
    }

    if (struct != null) {
      if (localGenerics.isNotEmpty) {
        struct =
            struct.newInstWithGenerics(context, localGenerics, struct.generics);
      }
      return ExprTempValue(null, struct, ident);
    }

    var fn = context.getFn(ident);
    if (fn == null) {
      fn = typeAlias?.getTy(context, generics);
      if (fn != null) {
        localGenerics = const [];
      }
    }
    if (fn != null) {
      if (fn is SizeOfFn) {
        return ExprTempValue(null, fn, ident);
      }

      var enableBuild = false;
      if (localGenerics.isNotEmpty) {
        fn = fn.newInstWithGenerics(context, localGenerics, fn.generics);
        enableBuild = true;
      }

      if (fn.generics.isEmpty) {
        enableBuild = true;
      }

      if (enableBuild) {
        // final fnContext = context.getFnContext(ident);
        final value = fn.build();
        if (value != null) {
          return ExprTempValue(value, value.ty, ident);
        }
      }
      return ExprTempValue(null, fn, ident);
    }
    return null;
  }

  bool _isCatch = false;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final v = context.getVariable(ident);
    final fnContext = context.getLastFnContext();
    if (fnContext != null) {
      _isCatch = fnContext.catchVariables.contains(v);
    }

    if (v != null) return v.copy(ident: ident);

    var struct = context.getStruct(ident);
    if (struct != null) {
      if (generics.isNotEmpty) {
        final gg = <Identifier, Ty>{};
        for (var i = 0; i < generics.length; i += 1) {
          final g = generics[i];
          final gName = struct.generics[i];
          gg[gName.ident] = g.grt(context);
        }
        struct = struct.newInst(gg, context);
      }
      return context.createVal(struct, ident);
    }
    var fn = context.getFn(ident);
    if (fn != null) {
      context.addChild(fn);
      if (generics.isNotEmpty) {
        final gg = <Identifier, Ty>{};
        for (var i = 0; i < generics.length; i += 1) {
          final g = generics[i];
          final gName = fn.generics[i];
          gg[gName.ident] = g.grt(context);
        }
        fn = fn.newInst(gg, context);
      }
      return context.createVal(fn, ident);
    }

    return null;
  }
}

class RefExpr extends Expr {
  RefExpr(this.current, this.pointerIdent, this.kind);
  final Expr current;
  final PointerKind kind;
  final Identifier pointerIdent;
  @override
  bool get hasUnknownExpr => current.hasUnknownExpr;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    current.incLevel(count);
  }

  @override
  Expr clone() {
    return RefExpr(current.clone(), pointerIdent, kind);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final val = current.build(context);
    var vv = PointerKind.refDerefs(val?.variable, context, kind);
    if (vv != null) {
      // if (kind.isEmpty) {
      //   return ExprTempValue(vv, vv.ty, val!.currentIdent);
      // }
      return ExprTempValue(vv, vv.ty, pointerIdent);
    }
    return val;
  }

  @override
  String toString() {
    return '$kind$current';
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final vv = current.analysis(context);
    if (vv == null) return null;
    return vv.copy(ident: pointerIdent)..kind.add(kind);
  }
}

class BlockExpr extends Expr {
  BlockExpr(this.block);

  final Block block;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final child = context.childContext();
    block.analysis(child);
    return null;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final child = context.clone();
    block.build(child);
    return null;
  }

  @override
  Expr clone() {
    return BlockExpr(block.clone());
  }

  @override
  String toString() {
    return '$block'.replaceFirst(' ', '');
  }
}

class MatchItemExpr extends BuildMixin {
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
          final ident = p.ident ?? Identifier.none;
          child.pushVariable(ident, child.createVal(f.grt(child), ident));
        }
      }
    } else {
      expr.analysis(child);
    }
    block.analysis(child);

    return IfExprBlock.retFromBlock(block, context);
  }

  bool get isValIdent {
    var e = expr;
    if (e is RefExpr) {
      e = e.current;
    }
    return op == null && e is VariableIdentExpr;
  }

  bool get isOther {
    var e = expr;
    if (e is RefExpr) {
      e = e.current;
    }
    if (e is VariableIdentExpr) {
      if (e.ident.src == '_') {
        return true;
      }
    }
    return false;
  }

  void build4(BuildContext context, ExprTempValue parrern) {
    final child = context;
    var e = expr;
    if (e is RefExpr) {
      e = e.current;
    }
    e = e as VariableIdentExpr;
    child.pushVariable(e.ident, parrern.variable!);
    block.build(child);
  }

  ExprTempValue? build3(BuildContext context, ExprTempValue pattern) {
    return OpExpr.math(context, op ?? OpKind.Eq, pattern.variable, expr,
        Identifier.none, pattern.currentIdent);
  }

  int? build2(BuildContext context, ExprTempValue pattern) {
    final child = context;
    var e = expr;
    int? value;
    if (e is RefExpr) {
      e = e.current;
    }
    List<FieldExpr> params = const [];

    if (e is FnCallExpr) {
      params = e.params;
      e = e.expr;
    }

    final enumVariable = e.build(child);
    final enumTy = enumVariable?.ty;
    final val = pattern.variable;
    if (val != null) {
      if (enumTy is EnumItem) {
        value = enumTy.llvmType.load(child, val, params);
      }
    }

    block.build(child);
    return value;
  }

  MatchItemExpr clone() {
    return MatchItemExpr(expr.clone(), block.clone(), op);
  }

  @override
  String toString() {
    final o = op == null ? '' : '${op!.op} ';
    return '$pad$o$expr =>$block';
  }
}

class MatchExpr extends Expr {
  MatchExpr(this.expr, this.items) {
    for (var item in items) {
      item.incLevel();
    }
  }

  final Expr expr;
  final List<MatchItemExpr> items;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var item in items) {
      item.incLevel(count);
    }
  }

  AnalysisVariable? _variable;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    expr.analysis(context);
    for (var item in items) {
      _variable ??= item.analysis(context);
    }
    return null;
  }

  ExprTempValue? commonExpr(BuildContext context, ExprTempValue variable) {
    // match 表达式
    MatchItemExpr? last;
    MatchItemExpr? valIdentItem =
        items.firstWhereOrNull((element) => element.isValIdent);
    for (var item in items) {
      if (last == null) {
        last = item;
        continue;
      }
      if (item == valIdentItem) continue;
      last.child = item;
      last = item;
    }
    last?.child = valIdentItem;
    last = valIdentItem;

    StoreVariable? retVariable;
    final retTy = LiteralExpr.letTy;
    if (retTy != null) {
      retVariable = retTy.llvmType.createAlloca(context, Identifier.none, null);
    }
    void buildItem(MatchItemExpr item, BuildContext context) {
      final then = context.buildSubBB(name: 'm_then');
      final after = context.buildSubBB(name: 'm_after');
      LLVMBasicBlock elseBB;
      final child = item.child;
      if (child != null) {
        elseBB = context.buildSubBB(name: 'm_else');
      } else {
        elseBB = after;
      }

      context.appendBB(then);
      final exprTempValue = item.build3(context, variable);
      final val = exprTempValue?.variable;
      item.block.build(then.context);
      IfExpr._blockRetValue(item.block, then.context, retVariable);
      if (then.context.canBr) {
        then.context.br(after.context);
      }

      if (val != null) {
        llvm.LLVMBuildCondBr(
            context.builder,
            val.load(context, exprTempValue!.currentIdent.offset),
            then.bb,
            elseBB.bb);
      }

      if (child != null) {
        context.appendBB(elseBB);
        if (child.isValIdent) {
          child.build4(elseBB.context, variable);
          IfExpr._blockRetValue(child.block, elseBB.context, retVariable);
        } else if (child.isOther) {
          child.build2(elseBB.context, variable);
          IfExpr._blockRetValue(child.block, elseBB.context, retVariable);
        } else {
          buildItem(child, elseBB.context);
        }

        if (elseBB.context.canBr) {
          elseBB.context.br(after.context);
        }
      }

      context.insertPointBB(after);
    }

    buildItem(items.first, context);

    if (retVariable == null) {
      return null;
    }
    return ExprTempValue(retVariable, retVariable.ty, Identifier.none);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final variable = expr.build(context);
    if (variable == null) return null;
    final ty = variable.ty;
    if (ty is! EnumItem) {
      return commonExpr(context, variable);
    }

    final itemLength = ty.parent.variants.length;

    final parent = variable.variable;
    if (parent == null) return null;

    StoreVariable? retVariable;
    final retTy = LiteralExpr.letTy ?? _variable?.ty;
    if (retTy != null) {
      retVariable = retTy.llvmType.createAlloca(context, Identifier.none, null);
    }

    var indexValue = ty.llvmType.loadIndex(context, parent);

    final hasOther = items.any((e) => e.isOther);
    var length = items.length;

    if (length <= 2) {
      void buildItem(MatchItemExpr item, BuildContext context) {
        final then = context.buildSubBB(name: 'm_then');
        final after = context.buildSubBB(name: 'm_after');
        LLVMBasicBlock elseBB;
        final child = item.child;
        if (child != null) {
          elseBB = context.buildSubBB(name: 'm_else');
        } else {
          elseBB = after;
        }

        context.appendBB(then);
        final itemIndex = item.build2(then.context, variable);
        IfExpr._blockRetValue(item.block, then.context, retVariable);
        if (then.context.canBr) {
          then.context.br(after.context);
        }
        if (itemIndex != null) {
          final con = llvm.LLVMBuildICmp(
              context.builder,
              LLVMIntPredicate.LLVMIntEQ,
              indexValue,
              ty.parent.llvmType.getIndexValue(context, itemIndex),
              unname);
          llvm.LLVMBuildCondBr(context.builder, con, then.bb, elseBB.bb);
        }

        if (child != null) {
          context.appendBB(elseBB);
          if (child.isOther || itemLength == 2) {
            child.build2(elseBB.context, variable);
            IfExpr._blockRetValue(child.block, elseBB.context, retVariable);
          } else {
            buildItem(child, elseBB.context);
          }
          if (elseBB.context.canBr) {
            elseBB.context.br(after.context);
          }
        }

        context.insertPointBB(after);
      }

      MatchItemExpr? last;
      for (var item in items) {
        if (last == null) {
          last = item;
          continue;
        }
        last.child = item;
        last = item;
      }
      buildItem(items.first, context);
    } else {
      final elseBb = context.buildSubBB(name: 'match_else');
      LLVMBasicBlock after = elseBb;

      if (hasOther) {
        length -= 1;
        context.appendBB(elseBb);
        after = context.buildSubBB(name: 'match_after');
      }

      final ss =
          llvm.LLVMBuildSwitch(context.builder, indexValue, elseBb.bb, length);
      var index = 0;
      final llPty = ty.parent.llvmType;
      for (var item in items) {
        LLVMBasicBlock childBb;
        if (item.isOther) {
          childBb = elseBb;
        } else {
          childBb = context.buildSubBB(name: 'match_bb_$index');
          context.appendBB(childBb);
        }
        final v = item.build2(childBb.context, variable);
        if (v != null) {
          llvm.LLVMAddCase(ss, llPty.getIndexValue(context, v), childBb.bb);
        }
        IfExpr._blockRetValue(item.block, childBb.context, retVariable);
        childBb.context.br(after.context);
        index += 1;
      }
      if (after != elseBb) {
        context.insertPointBB(after);
      }
    }

    if (retVariable == null) {
      return null;
    }
    return ExprTempValue(retVariable, retVariable.ty, Identifier.none);
  }

  @override
  Expr clone() {
    return MatchExpr(expr.clone(), items.map((e) => e.clone()).toList())
      .._variable = _variable;
  }

  @override
  String toString() {
    return 'match $expr {\n${items.join(',\n')}\n$pad}';
  }
}

class AsExpr extends Expr {
  AsExpr(this.lhs, this.rhs);
  final Expr lhs;
  final PathTy rhs;

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final r = rhs.grt(context);
    final l = lhs.analysis(context);

    if (l == null) return l;
    return context.createVal(r, l.ident);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final r = rhs.grt(context);
    final l = lhs.build(context);
    final lv = l?.variable;
    final lty = l?.ty;
    if (lv == null) return l;
    if (r is BuiltInTy && lty is BuiltInTy) {
      final val = context.castLit(
          lty.ty, lv.load(context, l!.currentIdent.offset), r.ty);
      return ExprTempValue(LLVMConstVariable(val, r), r, l.currentIdent);
    }
    return l;
  }

  @override
  Expr clone() {
    return AsExpr(lhs.clone(), rhs);
  }

  @override
  String toString() {
    return '$lhs as $rhs';
  }
}

class ImportExpr extends Expr {
  ImportExpr(this.path, {this.name});
  final Identifier? name;
  final ImportPath path;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    context.pushImport(path, name: name);
    return null;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.pushImport(path, name: name);
    return null;
  }

  @override
  Expr clone() {
    return ImportExpr(path, name: name);
  }

  @override
  String toString() {
    final n = name == null ? '' : ' as $name';
    return 'import $path$n';
  }
}

class ArrayExpr extends Expr {
  ArrayExpr(this.elements);

  final List<Expr> elements;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    Ty? ty;
    for (var element in elements) {
      final v = element.analysis(context);
      if (v != null) {
        ty ??= v.ty;
      }
    }
    ty ??= LiteralExpr.letTy;
    if (ty == null) return null;
    return context.createVal(ArrayTy(ty, elements.length), Identifier.none);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final values = <LLVMValueRef>[];
    Ty? arrTy = LiteralExpr.letTy;

    Ty? ty;
    if (arrTy is ArrayTy) {
      ty = arrTy.elementType;
    }

    final elementTy = LiteralExpr.run(() {
      Ty? ty;
      for (var element in elements) {
        final v = element.build(context);
        final variable = v?.variable;
        if (variable != null) {
          ty ??= variable.ty;
          values.add(variable.load(context, v!.currentIdent.offset));
        }
      }
      return ty;
    }, ty);

    ty ??= elementTy;

    if (arrTy == null && ty != null) {
      arrTy = ArrayTy(ty, elements.length);
    }
    if (arrTy is ArrayTy) {
      final v = arrTy.llvmType.createArray(context, values);
      return ExprTempValue(v, v.ty, Identifier.none);
    }

    return null;
  }

  @override
  ArrayExpr clone() {
    return ArrayExpr(elements.map((e) => e.clone()).toList());
  }

  @override
  String toString() {
    return '[${elements.join(',')}]';
  }
}

enum UnaryKind {
  /// The `!` operator (not)
  Not('!'),
  Neg('-'),
  ;

  final String op;
  const UnaryKind(this.op);

  static UnaryKind? from(String src) {
    return values.firstWhereOrNull((element) => element.op == src);
  }
}

class UnaryExpr extends Expr {
  UnaryExpr(this.op, this.expr, this.opIdent);
  final UnaryKind op;
  final Expr expr;

  final Identifier opIdent;

  @override
  bool get hasUnknownExpr => expr.hasUnknownExpr;

  @override
  UnaryExpr clone() {
    return UnaryExpr(op, expr.clone(), opIdent);
  }

  @override
  String toString() {
    return '${op.op}$expr';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final temp = expr.build(context);
    var val = temp?.variable;
    if (val == null) return null;
    if (op == UnaryKind.Not) {
      if (val.ty == BuiltInTy.kBool) {
        final value = val.load(context, temp!.currentIdent.offset);
        final notValue = llvm.LLVMBuildNot(context.builder, value, unname);
        final variable = LLVMConstVariable(notValue, val.ty);
        return ExprTempValue(variable, variable.ty, opIdent);
      }

      return OpExpr.math(
          context, OpKind.Eq, val, null, opIdent, temp!.currentIdent);
    } else if (op == UnaryKind.Neg) {
      final va = val.load(context, Offset.zero);
      final t = llvm.LLVMTypeOf(va);
      final tyKind = llvm.LLVMGetTypeKind(t);
      final isFloat = tyKind == LLVMTypeKind.LLVMFloatTypeKind ||
          tyKind == LLVMTypeKind.LLVMDoubleTypeKind ||
          tyKind == LLVMTypeKind.LLVMBFloatTypeKind;
      LLVMValueRef llvmValue;
      if (isFloat) {
        llvmValue = llvm.LLVMBuildFNeg(context.builder, va, unname);
      } else {
        llvmValue = llvm.LLVMBuildNeg(context.builder, va, unname);
      }
      final variable = LLVMConstVariable(llvmValue, val.ty);
      return ExprTempValue(variable, variable.ty, opIdent);
    }
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    // todo
    final temp = expr.analysis(context);
    // final r = lhs.analysis(context);
    if (temp == null) return null;

    return context.createVal(temp.ty, Identifier.none);
  }
}
