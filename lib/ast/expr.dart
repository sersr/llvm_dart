// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

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
    final isStr = ty.ty == LitKind.kString;
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
      return r;
    }
    return ty;
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final v = realTy.llvmType.createValue(str: ident.src);

    return ExprTempValue(v, ty);
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
    return ExprTempValue(v, v.ty);
  }

  StoreVariable? createIfBlock(IfExprBlock ifb, BuildContext context, Ty? ty) {
    StoreVariable? variable;
    if (ty != null) {
      variable = ty.llvmType.createAlloca(context, Identifier.none);
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
          final val = expr.build(context)?.variable;
          if (val == null) {
            // error
          } else {
            if (val is LLVMAllocaDelayVariable) {
              val.create(variable);
            } else {
              final v = val.load(context);
              variable.store(context, v);
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

    final con = ifEB.expr.build(c)?.variable;
    if (con == null) return;

    c.appendBB(then);
    ifEB.block.build(then.context);
    if (onlyIf) {
      llvm.LLVMBuildCondBr(c.builder, con.load(c), then.bb, afterBB.bb);
    } else {
      elseBB = c.buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
      llvm.LLVMBuildCondBr(c.builder, con.load(c), then.bb, elseBB.bb);
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
    context.contine();
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

    context.ret(e?.variable);
    return e;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final val = expr?.analysis(context);
    final current = context.getLastFnContext();
    if (val != null && current != null) {
      final valLife = val.lifeCycle.fnContext;
      if (valLife != null) {
        if (val.kind.isRef) {
          if (val.lifeCycle.isInner && current.isChildOrCurrent(valLife)) {
            Log.e('lifeCycle Error: ${val.ident}');
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

  bool isNew = false;

  @override
  Expr clone() {
    return StructExpr(ident, fields.map((e) => e.clone()).toList(), generics)
      ..isNew = isNew;
  }

  @override
  String toString() {
    return '$ident${generics.str}{${fields.join(',')}}';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final struct = context.getStruct(ident);
    if (struct == null) return null;

    return buildTupeOrStruct(struct, context, ident, fields, generics, isNew);
  }

  static T genStruct<T>(NewInst<T> t, Tys context, List<FieldExpr> params,
      List<PathTy> genericsInst) {
    final fields = t.fields;
    final generics = t.generics;
    var nt = t as T;
    if (genericsInst.isNotEmpty) {
      final gMap = <Identifier, Ty>{};
      for (var i = 0; i < genericsInst.length; i += 1) {
        final gg = genericsInst[i];
        final g = generics[i];
        Log.w('$g $gg ${gg.generics}');
        gMap[g.ident] = gg.grt(context);
      }
      // Log.w('gg $gMap');
      nt = t.newInst(gMap, context);
    } else if (generics.isNotEmpty) {
      final gMap = <Identifier, Ty>{};

      final sg = generics;
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));

      // x: Arc<Gen<T>> => first fdTy => Arc<Gen<T>>
      // child fdTy:  Gen<T> => T => real type
      void fa(Ty ty, PathTy fdTy) {
        final index = sg.indexWhere((e) => e.ident == fdTy.ident);
        if (index != -1) {
          final gen = sg[index];
          if (gen.rawTy.generics.isNotEmpty && ty is PathInterFace) {
            for (var f in gen.rawTy.generics) {
              final tyg = (ty as PathInterFace).tys[f.ident];
              fa(tyg!, f);
            }
          }
          gMap.putIfAbsent(fdTy.ident, () => ty);
        }

        if (fdTy.generics.isNotEmpty && ty is PathInterFace) {
          for (var i = 0; i < fdTy.generics.length; i += 1) {
            final fdIdent = fdTy.generics[i];
            final tyg = (ty as PathInterFace).tys[fdIdent.ident];
            fa(tyg!, fdIdent);
          }
        }
      }

      bool isBuild = context is BuildContext;
      for (var i = 0; i < sortFields.length; i += 1) {
        final f = sortFields[i];
        final fd = fields[i].rawTy;

        Ty? ty;
        if (isBuild) {
          ty = LiteralExpr.run(
                  () => f.build(context)?.variable, fd.grtOrT(context))
              ?.ty;
        } else {
          ty = LiteralExpr.run(() => f.analysis(context as AnalysisContext),
                  fd.grtOrT(context))
              ?.ty;
        }
        if (ty != null) {
          final fd = fields[i];
          fa(ty, fd.rawTy);
        }
      }

      // Log.w('${struct.ident}: $gMap');
      nt = t.newInst(gMap, context);
    }
    return nt;
  }

  static ExprTempValue? buildTupeOrStruct(
      StructTy struct,
      BuildContext context,
      Identifier ident,
      List<FieldExpr> params,
      List<PathTy> genericsInst,
      bool isNew) {
    struct = genStruct(struct, context, params, genericsInst);
    final structType = struct.llvmType.createType(context);
    LLVMValueRef create([StoreVariable? alloca]) {
      var value = alloca;
      final min = struct.llvmType.getMaxSize(context);
      var fields = struct.fields;
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));
      final size = min > 4 ? 8 : 4;

      if (value == null) {
        if (isNew) {
          value = struct.llvmType.createMalloc(context, ident);
          final fnContext = context.getLastFnContext();
          fnContext?.addFree(value);
        } else {
          value = struct.llvmType.createAlloca(context, ident);
        }
      }

      for (var i = 0; i < sortFields.length; i++) {
        final f = sortFields[i];
        final fd = fields[i];

        final v =
            LiteralExpr.run(() => f.build(context)?.variable, fd.grt(context));
        if (v == null) continue;
        final vv = struct.llvmType.getField(value, context, fd.ident)!;
        if (v is LLVMAllocaDelayVariable) {
          final result = v.create(vv);
          if (result) {
            continue;
          }
        }

        final store = vv.store(context, v.load(context));
        llvm.LLVMSetAlignment(store, size);
      }
      return value.alloca;
    }

    final value = LLVMAllocaDelayVariable(struct, create, structType);

    return ExprTempValue(value, value.ty);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var struct = context.getStruct(ident);
    if (struct == null) return null;
    struct = genStruct(struct, context, fields, generics);

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
      lVariable.store(context, rVariable.load(context));
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
          if (rhs.lifeCycle.isInner && lhs.lifeCycle.isOut) {
            Log.e('lifeCycle Error: ${rhs.ident}');
          }
        }
      }

      return lhs;
    }
    return null;
  }
}

class AssignOpExpr extends AssignExpr {
  AssignOpExpr(this.op, super.ref, super.expr);
  final OpKind op;
  @override
  Expr clone() {
    return AssignOpExpr(op, ref.clone(), expr.clone());
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
          () => OpExpr.math(context, op, lVariable, expr), lVariable.ty);
      final rValue = val?.variable;
      if (rValue != null) {
        lVariable.store(context, rValue.load(context));
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
    final fnV = fn.build(context);
    if (fnV == null) return null;

    return ExprTempValue(fnV, fn);
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

  static ExprTempValue? _fnCall(
      BuildContext context,
      Fn fn,
      List<FieldExpr> params,
      Variable? fnVariable,
      Variable? struct,
      GenTy? gen,
      Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>>? map) {
    fn = StructExpr.genStruct(fn, context, params, []);
    // ignore: invalid_use_of_protected_member
    final fnParams = fn.fnSign.fnDecl.params;
    final fnExtern = fn.extern;
    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);
    final isSret = fn.llvmType.isSret(context);

    StoreVariable? sret;
    if (isSret) {
      sret = retTy.llvmType.createAlloca(context, Identifier.builtIn('sret'));

      args.add(sret.alloca);
    }

    if (struct != null) {
      if (struct.ty is BuiltInTy) {
        args.add(struct.load(context));
      } else {
        args.add(struct.getBaseValue(context));
      }
    }
    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fnParams.length) {
        c = fn.getRty(context, fnParams[i]);
      }
      final v = LiteralExpr.run(() {
        return p.build(context)?.variable;
      }, c);
      if (v != null) {
        LLVMValueRef value;
        final vty = v.ty;
        if (vty is StructTy) {
          value = vty.llvmType.load2(context, v, fnExtern);
          // }
          // if (v is LLVMRefAllocaVariable) {
          //   value = v.load(context);
        } else {
          value = v.load(context);
        }

        args.add(value);
      }
    }

    void addArg(Variable? v) {
      if (v != null) {
        LLVMValueRef value;
        if (v is StoreVariable) {
          value = v.alloca;
        } else {
          value = v.load(context);
        }
        args.add(value);
      }
    }

    for (var variable in fn.variables) {
      var v = context.getVariable(variable.ident);
      addArg(v);
    }

    if (extra != null) {
      for (var variable in extra) {
        var v = context.getVariable(variable.ident);
        addArg(v);
      }
    }

    if (fn is FnTy) {
      // ignore: invalid_use_of_protected_member
      final params = fn.fnSign.fnDecl.params;
      for (var p in params) {
        var v = context.getVariable(p.ident);
        addArg(v);
      }
    }

    final fnType = fn.llvmType.createFnType(context, extra);

    final fnAlloca = fn.build(context, extra, map);
    final fnValue = fnAlloca?.load(context) ?? fnVariable?.load(context);
    if (fnValue == null) return null;

    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    if (sret != null) {
      return ExprTempValue(sret, retTy);
    }
    if (retTy is BuiltInTy) {
      if (retTy.ty == LitKind.kVoid) {
        return null;
      }
    }

    if (retTy is RefTy) {
      final v = LLVMRefAllocaVariable.from(ret, retTy.parent, context);
      v.isTemp = false;
      return ExprTempValue(v, v.ty);
    } else if (retTy is StructTy) {
      final v = retTy.llvmType.createAlloca(context, Identifier.none);
      v.store(context, ret);
      v.isTemp = false;
      return ExprTempValue(v, v.ty);
    }
    final v = LLVMConstVariable(ret, retTy);

    return ExprTempValue(v, v.ty);
  }

  ExprTempValue? fnCall(
    BuildContext context,
    Fn fn,
    List<FieldExpr> params,
    Variable? fnVariable, {
    Variable? struct,
    GenTy? gen,
  }) {
    return _fnCall(context, fn, params, fnVariable, struct, gen, catchVariables,
        childrenVariables);
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

  bool isNew = false;
  @override
  Expr clone() {
    final f = FnCallExpr(expr.clone(), params.map((e) => e.clone()).toList());
    f._catchFns.addAll(_catchFns);
    f._catchMapFns.addAll(_catchMapFns);
    f.isNew = isNew;
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
          fn, context, Identifier.none, params, const [], isNew);
    }

    if (fn is SizeOfFn) {
      if (params.isEmpty) {
        return null;
      }
      final first = params.first;
      final e = first.expr.build(context);
      Ty? ty = e?.ty;
      if (ty == null) {
        final e = first.expr;
        if (e is VariableIdentExpr) {
          final p = PathTy(e.ident, e.generics);
          ty = p.grt(context);
        }
      }
      if (ty == null) return null;

      final v = fn.llvmType.createFunction(context, null, ty);
      return ExprTempValue(v, BuiltInTy.int);
    }
    if (fn is! Fn) return null;

    final fnnn = StructExpr.genStruct(fn, context, params, []);

    return fnCall(context, fnnn, params, variable);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final fn = expr.analysis(context);
    if (fn == null) return null;
    final fnty = fn.ty;
    if (fnty is StructTy) {
      final struct = StructExpr.genStruct(fnty, context, params, []);
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
      return context.createVal(BuiltInTy.lit(LitKind.usize), Identifier.none);
    }
    if (fnty is! Fn) return null;
    final fnnn = StructExpr.genStruct(fnty, context, params, []);

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
    if (variable == null) return null;
    // while (true) {
    //   if (val is! Deref) {
    //     break;
    //   }
    //   final v = val.getDeref(context);
    //   if (v == val) break;
    //   val = v;
    // }
    if (val is Deref) {
      val = val.getDeref(context);
    }
    if (val == null) return null;

    var valTy = val.ty;

    if (valTy is ArrayTy) {
      if (fnName == 'elementAt' && params.isNotEmpty) {
        final first = params.first.build(context)?.variable;
        if (first != null && first.ty is BuiltInTy) {
          final element =
              valTy.llvmType.getElement(context, val, first.load(context));
          return ExprTempValue(element, element.ty);
        }
      } else if (fnName == 'getSize') {
        final size = BuiltInTy.usize.llvmType.createValue(str: '${valTy.size}');
        return ExprTempValue(size, size.ty);
      } else if (fnName == 'toStr') {
        final element = valTy.llvmType.toStr(context, val);
        return ExprTempValue(element, element.ty);
      }
    }

    var structTy = valTy;
    final ty = LiteralExpr.letTy;

    PathInterFace? letTy;
    if (ty is PathInterFace) {
      letTy = ty as PathInterFace;
    }
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
                () => params.first.build(context)?.variable,
                BuiltInTy.lit(LitKind.usize));

            if (first is LLVMLitVariable) {
              if (structTy.tys.isNotEmpty) {
                final arr =
                    ArrayTy(structTy.tys.values.first, first.value.iValue);
                final element =
                    arr.llvmType.createAlloca(context, Identifier.none);

                return ExprTempValue(element, element.ty);
              }
            }
          }
          return null;
        }
      }
    }

    Variable? fnVariable;
    // 字段有可能是一个函数指针
    if (fn == null) {
      if (val is StoreVariable && structTy is StructTy) {
        final field = structTy.llvmType.getField(val, context, ident);
        if (field != null) {
          // 匿名函数作为参数要处理捕捉的变量
          if (field.ty is FnTy) {
            assert(_paramFn is Fn, 'ty: ${field.ty}, _paramFn: $_paramFn');
            fnVariable = field;
            fn = _paramFn ?? field.ty as FnTy;
          }
        }
      }
    }
    if (fn == null) return null;

    return fnCall(context, fn, params, fnVariable, struct: val, gen: (ident) {
      if (structTy is StructTy) return structTy.tys[ident] ?? letTy?.tys[ident];
      return null;
    });
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
    fn = StructExpr.genStruct(fn, context, params, []);

    fn.analysis(context.getLastFnContext() ?? context);

    // final fnContext = context.getLastFnContext();
    // fnContext?.addChild(fn.fnSign.fnDecl.ident, fn.variables);
    return context.createVal(fn.getRetTy(context), Identifier.none);
  }
}

class StructDotFieldExpr extends Expr {
  StructDotFieldExpr(this.struct, this.kind, this.ident);
  final Identifier ident;
  final Expr struct;

  final List<PointerKind> kind;

  @override
  bool get hasUnknownExpr => struct.hasUnknownExpr;

  @override
  Expr clone() {
    return StructDotFieldExpr(struct.clone(), kind, ident);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final structVal = struct.build(context);
    final val = structVal?.variable;
    var newVal = PointerKind.refDerefs(val, context, kind);

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
    return ExprTempValue(v, v.ty);
  }

  @override
  String toString() {
    var e = struct;
    if (e is RefExpr) {
      if (e.kind.isNotEmpty) {
        return '${kind.join('')}($struct).$ident';
      }
    }
    return '${kind.join('')}$struct.$ident';
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
    vv.lifeCycle.fnContext = variable.lifeCycle.fnContext;
    return vv;
  }
}

enum OpKind {
  /// The `+` operator (addition)
  Add('+', 60),

  /// The `-` operator (subtraction)
  Sub('-', 60),

  /// The `*` operator (multiplication)
  Mul('*', 110),

  /// The `/` operator (division)
  Div('/', 110),

  /// The `%` operator (modulus)
  Rem('%', 110),

  /// The `&&` operator (logical and)
  And('&&', 0),

  /// The `||` operator (logical or)
  Or('||', 0),

  /// The `^` operator (bitwise xor)
  BitXor('^', 1000),

  /// The `&` operator (bitwise and)
  BitAnd('&', 50),

  /// The `|` operator (bitwise or)
  BitOr('|', 50),

  /// The `<<` operator (shift left)
  Shl('<<', 50),

  /// The `>>` operator (shift right)
  Shr('>>', 50),

  /// The `==` operator (equality)
  Eq('==', 10),

  /// The `<` operator (less than)
  Lt('<', 10),

  /// The `<=` operator (less than or equal to)
  Le('<=', 10),

  /// The `!=` operator (not equal to)
  Ne('!=', 10),

  /// The `>=` operator (greater than or equal to)
  Ge('>=', 10),

  /// The `>` operator (greater than)
  Gt('>', 10),
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
  OpExpr(this.op, this.lhs, this.rhs);
  final OpKind op;
  final Expr lhs;
  final Expr rhs;

  @override
  bool get hasUnknownExpr => lhs.hasUnknownExpr || rhs.hasUnknownExpr;

  @override
  Expr clone() {
    return OpExpr(op, lhs.clone(), rhs.clone());
  }

  @override
  String toString() {
    var rs = '$rhs';
    var ls = '$lhs';

    var rc = rhs;
    if (rc is RefExpr) {
      if (rc.kind.isEmpty) {
        if (rc.current is OpExpr) {
          rc = rc.current;
        }
      }
    }

    if (rc is OpExpr) {
      if (op.level > rc.op.level) {
        rs = '($rs)';
      }
    }
    var lc = lhs;
    if (lc is RefExpr) {
      if (lc.kind.isEmpty) {
        if (lc.current is OpExpr) {
          lc = lc.current;
        }
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
    final l = lhs.build(context);

    if (l == null) return null;
    return math(context, op, l.variable, rhs);
  }

  static ExprTempValue? math(
      BuildContext context, OpKind op, Variable? l, Expr rhs) {
    if (l == null) return null;
    var isFloat = false;
    var signed = false;
    // final RValue = r.variable;
    if (l is LLVMTempOpVariable) {
      isFloat = l.isFloat;
      signed = l.isSigned;
    } else {
      var lty = l.ty;
      if (lty is BuiltInTy) {
        final kind = lty.ty;
        if (kind.isFp) {
          isFloat = true;
        } else if (kind.isInt) {
          signed = kind.signed;
        }
      }
    }

    final v = context.math(l, (context) {
      final r = LiteralExpr.run(() => rhs.build(context)?.variable, l.ty);
      return r;
    }, op, isFloat, signed: signed);
    return ExprTempValue(v, v.ty);
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
  neg('-'),
  ref('&');

  final String char;
  const PointerKind(this.char);

  static PointerKind? from(TokenKind kind) {
    if (kind == TokenKind.and) {
      return PointerKind.ref;
    } else if (kind == TokenKind.star) {
      return PointerKind.deref;
    } else if (kind == TokenKind.minus) {
      return PointerKind.neg;
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
      } else if (this == PointerKind.neg) {
        final va = val.load(c);
        final t = llvm.LLVMTypeOf(va);
        final tyKind = llvm.LLVMGetTypeKind(t);
        final isFloat = tyKind == LLVMTypeKind.LLVMFloatTypeKind ||
            tyKind == LLVMTypeKind.LLVMDoubleTypeKind ||
            tyKind == LLVMTypeKind.LLVMBFloatTypeKind;
        LLVMValueRef llvmValue;
        if (isFloat) {
          llvmValue = llvm.LLVMBuildFNeg(c.builder, va, unname);
        } else {
          llvmValue = llvm.LLVMBuildNeg(c.builder, va, unname);
        }
        return LLVMTempVariable(llvmValue, val.ty);
      }
    }
    return inst ?? val;
  }

  static Variable? refDerefs(
      Variable? val, BuildContext c, List<PointerKind> kind) {
    if (val == null) return val;
    Variable? vv = val;
    for (var k in kind.reversed) {
      vv = k.refDeref(vv, c);
    }
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
      if (kind == PointerKind.ref) {
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
    final val = context.getVariable(ident);
    if (val != null) {
      if (val is Deref) {
        if (ident.src == 'self') {
          final newVal = val.getDeref(context);
          return ExprTempValue(newVal, newVal.ty);
        }
      }
      return ExprTempValue(val, val.ty);
    }

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
      return ExprTempValue(TyVariable(struct), struct);
    }

    final fn = context.getFn(ident);
    if (fn != null) {
      if (fn is SizeOfFn) {
        return ExprTempValue(null, fn);
      }
      return ExprTempValue(null, fn);
      // final fnContext = context.getFnContext(ident);
      // final value = fn.build(fnContext!);
      // if (value != null) {
      //   return ExprTempValue(value, value.ty);
      // }
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

    if (v != null) return v;

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
    final fn = context.getFn(ident);
    if (fn != null) {
      context.addChild(fn);

      return context.createVal(fn, ident);
    }

    return null;
  }
}

class RefExpr extends Expr {
  RefExpr(this.current, this.kind);
  final Expr current;
  final List<PointerKind> kind;

  @override
  bool get hasUnknownExpr => current.hasUnknownExpr;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    current.incLevel(count);
  }

  @override
  Expr clone() {
    return RefExpr(current.clone(), kind);
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final val = current.build(context);
    var vv = PointerKind.refDerefs(val?.variable, context, kind);
    if (vv != null) {
      return ExprTempValue(vv, vv.ty);
    }
    return val;
  }

  @override
  String toString() {
    var s = kind.join('');
    if (kind.isNotEmpty) {
      var e = current;
      if (e is RefExpr) {
        e = e.current;
      }
      if (e is OpExpr) {
        return '$s($current)';
      }
    }
    return '$s$current';
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final vv = current.analysis(context);
    if (vv == null) return null;
    final newV = vv.copy()..kind.insertAll(0, kind);
    return newV;
    // return AnalysisVariable(vv.ty, vv.ident, [...kind, ...vv.kind]);
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
  MatchItemExpr(this.expr, this.block);
  final Expr expr;
  final Block block;

  MatchItemExpr? child;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block.incLevel(count);
  }

  @override
  void build(BuildContext context) {}

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

  int? build2(BuildContext context, ExprTempValue pattern) {
    final child = context;
    var e = expr;
    int? value;
    if (e is RefExpr) {
      e = e.current;
    }
    if (e is FnCallExpr) {
      final enumVariable = e.expr.build(child);
      final params = e.params;
      final enumTy = enumVariable?.ty;
      final val = pattern.variable;
      if (val != null) {
        if (enumTy is EnumItem) {
          value = enumTy.llvmType.load(child, val, params);
        }
      }
    } else {
      expr.build(child)?.variable;
    }
    block.build(child);
    return value;
  }

  MatchItemExpr clone() {
    return MatchItemExpr(expr.clone(), block.clone());
  }

  @override
  String toString() {
    return '$pad$expr =>$block';
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

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    final variable = expr.build(context);
    if (variable == null) return null;
    final ty = variable.ty;
    if (ty is! EnumItem) return null;
    final allCount = ty.parent.variants.length;

    final parent = variable.variable;
    if (parent == null) return null;

    StoreVariable? retVariable;
    final retTy = LiteralExpr.letTy ?? _variable?.ty;
    if (retTy != null) {
      retVariable = retTy.llvmType.createAlloca(context, Identifier.none);
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
          if (child.isOther || allCount == 2) {
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
    return ExprTempValue(retVariable, retVariable.ty);
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
      final val = context.castLit(lty.ty, lv.load(context), r.ty);
      return ExprTempValue(LLVMTempVariable(val, r), r);
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
        final v = element.build(context)?.variable;
        if (v != null) {
          ty ??= v.ty;
          values.add(v.load(context));
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
      return ExprTempValue(v, v.ty);
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
