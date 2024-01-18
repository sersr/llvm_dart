// ignore_for_file: constant_identifier_names
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
import 'llvm/build_methods.dart';
import 'llvm/coms.dart';
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

  @override
  Ty? getTy(StoreLoadMixin context) {
    return ty;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    if (baseTy is! BuiltInTy) {
      baseTy = ty;
    }
    final v = baseTy.llty.createValue(ident: ident);

    return ExprTempValue(v);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return context.createVal(ty, ident);
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
    if (block.isNotEmpty) {
      final last = block.lastOrNull;
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final v = createIfBlock(ifExpr, context, baseTy ?? _variable?.ty);
    if (v == null) return null;
    return ExprTempValue(v);
  }

  StoreVariable? createIfBlock(IfExprBlock ifb, FnBuildMixin context, Ty? ty) {
    StoreVariable? variable;
    if (ty != null) {
      variable = ty.llty.createAlloca(context, Identifier.none);
      context.autoAddFreeHeap(variable);
    }
    buildIfExprBlock(ifb, context, variable);

    return variable;
  }

  static void _blockRetValue(
      Block block, FnBuildMixin context, StoreVariable? variable) {
    if (variable == null) return;
    if (block.isNotEmpty) {
      final lastStmt = block.lastOrNull;
      if (lastStmt is ExprStmt) {
        final expr = lastStmt.expr;
        if (expr is! RetExpr) {
          // 获取缓存的value
          final temp = expr.build(context);
          final val = temp?.variable;
          if (val == null) {
            // error
          } else {
            context.removeFreeVariable(val);
            if (val is LLVMAllocaDelayVariable && !val.created) {
              val.initProxy(proxy: variable);
            } else {
              variable.storeVariable(context, val);
            }
          }
        }
      }
    }
  }

  void buildIfExprBlock(
      IfExprBlock ifEB, FnBuildMixin c, StoreVariable? variable) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = c.buildSubBB(name: 'then');
    late final afterBB = c.buildSubBB(name: 'after');
    LLVMBasicBlock? elseBB;

    bool hasAfterBb = false;

    final conTemp = ifEB.expr.build(c);
    final con = conTemp?.variable;
    if (con == null) return;

    LLVMValueRef conv;
    if (con.ty == BuiltInTy.kBool) {
      conv = con.load(c);
    } else {
      conv = c.math(con, null, OpKind.Ne, Identifier.none).load(c);
    }

    c.appendBB(then);
    ifEB.block.build(then.context, free: false);

    if (onlyIf) {
      hasAfterBb = true;
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, afterBB.bb);
      c.setBr();
    } else {
      elseBB = c.buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, elseBB.bb);
      c.appendBB(elseBB);
      c.setBr();
      if (elseifBlock != null) {
        buildIfExprBlock(elseifBlock, elseBB.context, variable);
      } else if (elseBlock != null) {
        elseBlock.build(elseBB.context, free: false);
      }
    }
    var canBr = then.context.canBr;
    if (canBr) {
      hasAfterBb = true;
      _blockRetValue(ifEB.block, then.context, variable);
      then.context.freeHeap();
      then.context.br(afterBB.context);
    }

    if (elseBB != null) {
      final elseCanBr = elseBB.context.canBr;
      if (elseCanBr) {
        hasAfterBb = true;
        if (elseBlock != null) {
          _blockRetValue(elseBlock, elseBB.context, variable);
          elseBB.context.freeHeap();
        } else if (elseifBlock != null) {
          _blockRetValue(elseifBlock.block, elseBB.context, variable);
          elseBB.context.freeHeap();
        }
        elseBB.context.br(afterBB.context);
      }
    }
    if (hasAfterBb) c.insertPointBB(afterBB);
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

class RetExpr extends Expr {
  RetExpr(this.expr, this.ident);
  final Identifier ident;
  final Expr? expr;
  @override
  Expr clone() {
    return RetExpr(expr?.clone(), ident);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final e = expr?.build(context);

    context.ret(e?.variable);
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
      final vals = current?.currentFn?.returnVariables;
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
        for (var val in all) {
          final ident = val.ident.toRawIdent;
          // Log.w(val.ident.light, onlyDebug: false);
          vals.add(ident);
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
  StructTy? getTy(StoreLoadMixin context, {void Function()? gen}) {
    var struct = context.getStruct(ident);

    if (struct == null) {
      final cty = context.getAliasTy(ident);
      final t = cty?.getTy(context, generics);
      if (t is! StructTy) return null;

      gen?.call();
      struct = t;
    }
    return struct;
  }

  @override
  Expr clone() {
    return StructExpr(ident, fields.map((e) => e.clone()).toList(), generics);
  }

  @override
  String toString() {
    return '$ident${generics.str}{${fields.join(',')}}';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    var genericsInst = generics;
    final struct = getTy(context, gen: () {
      genericsInst = const [];
    });

    if (struct == null) return null;

    return buildTupeOrStruct(struct, context, ident, fields, genericsInst);
  }

  static T resolveGeneric<T extends Ty>(NewInst<T> t, Tys context,
      List<FieldExpr> params, List<PathTy> genericsInst,
      {List<FieldDef> others = const []}) {
    final generics = [...t.generics, ...others];
    var nt = t as T;

    if (genericsInst.isNotEmpty) {
      return t.newInstWithGenerics(context, genericsInst, generics,
          extra: t.tys);
    }

    final fields = t.fields;
    if (t.tys.length < generics.length) {
      final genMapTy = <Identifier, Ty>{}..addAll(t.tys);

      final genList = generics;

      // 从上下文中获取具体类型
      for (var g in genList) {
        final tyVal = context.getTy(g.ident);
        if (tyVal != null) {
          genMapTy.putIfAbsent(g.ident, () => tyVal);
        }
      }
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));

      // x: Arc<Gen<T>> => first fdTy => Arc<Gen<T>>
      // child fdTy:  Gen<T> => T => real type
      //
      // fn hello<T>(y: T);
      //
      // hello(y: 1000);
      // ==> exactTy: i32; fieldTy: T
      //
      // fn foo<T>(x: Gen<T>);
      //
      // foo(x: Gen<i32> { foo: 1000 } );
      // ==> exactTy: Gen<i32>; fieldTy: Gen<T>
      //
      void visitor(Ty exactTy, PathTy fieldTy) {
        void checkTy(Ty exactTy, PathTy fieldTy) {
          if (exactTy case NewInst(tys: var tys, generics: var gBase)) {
            assert(gBase.length == exactTy.generics.length, "generic error.");

            for (var i = 0; i < fieldTy.generics.length; i += 1) {
              final fdIdent = fieldTy.generics[i];
              // 内部与外部名称不一致，从内部获取具体内省
              final tyg = tys[gBase[i].ident];
              visitor(tyg!, fdIdent);
            }
          }
        }

        exactTy = fieldTy.kind.unWrapRefTy(exactTy);

        final currentGenField =
            genList.firstWhereOrNull((e) => e.ident == fieldTy.ident);
        if (currentGenField != null) {
          // fn bar<T, X: Bar<T>>(x: X);
          // 处理泛型内部依赖，X已知晓，处理T

          genMapTy.putIfAbsent(fieldTy.ident, () {
            checkTy(exactTy, currentGenField.rawTy);
            return exactTy;
          });
        }

        if (genMapTy.length == genList.length) {
          return;
        }

        // Gen<i32> : Gen<T>
        // 泛型在下一级中
        checkTy(exactTy, fieldTy);
      }

      bool isBuild = context is FnBuildMixin;
      Ty? gen(Identifier ident) {
        return genMapTy[ident];
      }

      for (var i = 0; i < sortFields.length; i += 1) {
        final f = sortFields[i];
        final fd = fields[i];

        Ty? ty;
        if (isBuild) {
          ty = f.build(context, baseTy: fd.grtOrT(context, gen: gen))?.ty;
        } else {
          // fd.grtOrT(context, gen: gen)
          ty = f.analysis(context as AnalysisContext)?.ty;
        }
        if (ty != null) {
          visitor(ty, fd.rawTy);
        }
      }

      nt = t.newInst(genMapTy, context);
    }

    return nt;
  }

  static ExprTempValue? buildTupeOrStruct(StructTy struct, FnBuildMixin context,
      Identifier ident, List<FieldExpr> params, List<PathTy> genericsInst) {
    struct = resolveGeneric(struct, context, params, genericsInst);
    final structType = struct.typeOf(context);

    LLVMValueRef create(StoreVariable? proxy) {
      StoreVariable? value = proxy;
      // final min = struct.llvmType.getMaxSize(context);
      var fields = struct.fields;
      final sortFields = alignParam(
          params, (p) => fields.indexWhere((e) => e.ident == p.ident));
      // final size = min > 4 ? 8 : 4;
      value ??= struct.llty.createAlloca(context, ident);

      context.diSetCurrentLoc(ident.offset);

      if (sortFields.length != fields.length) {
        value.store(context, llvm.LLVMConstNull(structType));
        // final base = value.getBaseValue(context);
        // final len = struct.llvmType.getBytes(context);
        // final align = llvm.LLVMGetAlignment(base);
        // // final vb = llvm.LLVMBuildBitCast(
        // //     context.builder, base, context.pointer(), unname);
        // llvm.LLVMBuildMemSet(context.builder, base, context.constI8(0),
        //     BuiltInTy.constUsize(context, len), align);
      }

      for (var i = 0; i < sortFields.length; i++) {
        final f = sortFields[i];
        final fd = fields[i];

        final temp = f.build(context, baseTy: fd.grt(context));
        final v = temp?.variable;
        if (v == null) continue;
        final vv = struct.llty.getField(value, context, f.ident ?? fd.ident)!;
        // if (v is LLVMAllocaDelayVariable && !v.created) {
        //   v.initProxy(context, vv);
        //   continue;
        // }

        vv.storeVariable(context, v);
        // llvm.LLVMSetAlignment(store, size);
      }
      return value.alloca;
    }

    final value = LLVMAllocaDelayVariable(create, struct, structType, ident);

    context.autoAddStackCom(value);
    return ExprTempValue(value);
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final lhs = ref.build(context);
    final rhs = expr.build(context, baseTy: lhs?.ty);

    final lv = lhs?.variable;
    final rv = rhs?.variable;

    if (lv is StoreVariable && rv != null) {
      var cav = rv;
      if (lv.ty != rv.ty) {
        cav = AsExpr.asType(context, rv, Identifier.none, lv.ty);
      }
      if (cav is LLVMAllocaDelayVariable && !cav.created) {
        cav.initProxy(proxy: lv);
      } else {
        lv.storeVariable(context, cav);
      }
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final lhs = ref.build(context);
    final lVariable = lhs?.variable;

    if (lVariable is StoreVariable) {
      final val = OpExpr.math(context, op, lVariable, expr, opIdent);
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

  Identifier? get pattern {
    if (ident != null) return ident;
    final e = expr;
    if (e is VariableIdentExpr) {
      return e.ident;
    }
    return null;
  }

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
  FnExpr clone() {
    return FnExpr(fn.cloneDefault());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    fn.incLevel(count);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    assert(fn.currentContext == null);
    fn.currentContext ??= context;
    fn.build();
    return ExprTempValue.ty(fn);
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
    FnBuildMixin context,
    Fn fn,
    Identifier ident,
    List<FieldExpr> params, {
    Variable? struct,
  }) {
    return AbiFn.fnCallInternal(
        context, fn, ident, params, struct, catchVariables, childrenVariables);
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final fnV = expr.build(context);
    final variable = fnV?.variable;
    final fn = variable?.ty ?? fnV?.ty;
    if (fn is StructTy) {
      return StructExpr.buildTupeOrStruct(
          fn, context, Identifier.none, params, const []);
    }
    final builtinFn = doBuiltFns(context, fn, params);
    if (builtinFn != null) {
      return builtinFn;
    }

    if (fn is! Fn) return null;

    return fnCall(context, fn, variable?.ident ?? Identifier.none, params);
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
    if (fn.ty == sizeOfFn) {
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = receiver.build(context);
    final variable = temp?.variable;
    final fnName = ident.src;

    final val = variable?.defaultDeref(context, variable.ident);

    var valTy = val?.ty ?? temp?.ty;
    if (valTy == null) return null;

    var structTy = valTy;

    if (structTy is StructTy && structTy.tys.isEmpty) {
      if (baseTy is StructTy && structTy.ident == baseTy.ident) {
        structTy = baseTy;
      }
    }

    if (temp != null) {
      final builiin = context.global
          .arrayBuiltin(context, ident, fnName, val, structTy, params);
      if (builiin != null) return builiin;
    }

    var implFn = context.getImplFnForStruct(structTy, ident);

    if (structTy is StructTy) {
      /// 对于类方法(静态方法)，struct 中存在泛型，并且没有指定时，从静态方法中的参数列表
      /// 自动获取

      if (implFn is ImplStaticFn) {
        implFn = StructExpr.resolveGeneric(implFn, context, params, [],
            others: structTy.generics) as ImplFnMixin;
        if (structTy.tys.length != structTy.generics.length) {
          final newTys = <Identifier, Ty>{}..addAll(structTy.tys);
          for (var g in structTy.generics) {
            final ty = implFn.tys[g.ident];
            if (ty != null) {
              newTys[g.ident] = ty;
            }
          }
          structTy = structTy.newInst(newTys, context);
        }
      }
    }

    // 上面已经确定了structTy的具体类型了
    Fn? fn = implFn?.copyFrom(structTy);

    // 字段有可能是一个函数指针
    if (fn == null) {
      if (val != null && structTy is StructTy) {
        final field = structTy.llty.getField(val, context, ident);
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

    return fnCall(context, fn, ident, params, struct: val);
  }

  Fn? _paramFn;

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    var variable = receiver.analysis(context);
    if (variable == null) return null;
    var structTy = variable.ty;
    if (structTy is! StructTy) return null;

    if (variable is AnalysisStructVariable) {
      final p = variable.getParam(ident);
      final pp = p?.ty;
      if (pp is Fn) {
        _paramFn = pp;
        autoAddChild(pp, params, context);
      }
      if (p != null) return p;
    }

    structTy = StructExpr.resolveGeneric(structTy, context, params, []);
    var implFn = context.getImplFnForStruct(structTy, ident);

    if (implFn != null) {
      implFn = StructExpr.resolveGeneric(implFn, context, params, [],
          others: structTy.generics) as ImplFnMixin;
      if (structTy.tys.length != structTy.generics.length) {
        final newTys = <Identifier, Ty>{};
        for (var g in structTy.generics) {
          final ty = implFn.tys[g.ident];
          if (ty != null) {
            newTys[g.ident] = ty;
          }
        }
        structTy = structTy.newInst(newTys, context);
      }
    }
    Fn? fn = implFn?.copyFrom(structTy);

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

  int? getFCmpId(bool ordered) {
    if (index < Eq.index) return null;
    int? i;

    switch (this) {
      case Eq:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOEQ
            : LLVMRealPredicate.LLVMRealUEQ;
        break;
      case Ne:
        i = ordered
            ? LLVMRealPredicate.LLVMRealONE
            : LLVMRealPredicate.LLVMRealUNE;
        break;
      case Gt:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOGT
            : LLVMRealPredicate.LLVMRealUGT;
        break;
      case Ge:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOGE
            : LLVMRealPredicate.LLVMRealUGE;
        break;
      case Lt:
        i = ordered
            ? LLVMRealPredicate.LLVMRealOLT
            : LLVMRealPredicate.LLVMRealULT;
        break;
      case Le:
        i = ordered
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

    if (rc is OpExpr) {
      if (op.level > rc.op.level) {
        rs = '($rs)';
      }
    }
    var lc = lhs;

    if (lc is OpExpr) {
      if (op.level > lc.op.level) {
        ls = '($ls)';
      }
    }

    var ss = '$ls ${op.op} $rs';
    return ss;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final lty = lhs.getTy(context);
    final rty = rhs.getTy(context);
    Ty? bestTy = lty ?? rty;
    if (lty != null && rty != null) {
      final lsize = lty.llty.getBytes(context);
      final rsize = rty.llty.getBytes(context);
      bestTy = lsize > rsize ? lty : rty;
    }

    var l = lhs.build(context, baseTy: bestTy);
    var r = rhs.build(context, baseTy: bestTy);
    if (l == null || r == null) return null;

    final value = math(context, op, l.variable, rhs, opIdent);
    var val = value?.variable;
    final valTy = val?.ty;
    if (baseTy is BuiltInTy && baseTy != valTy && valTy is BuiltInTy) {
      final v = context.castLit(valTy.ty, val!.load(context), baseTy.ty);
      val = LLVMConstVariable(v, baseTy, Identifier.none);
      return ExprTempValue(val);
    } else if (l.ty is RefTy && valTy is BuiltInTy && valTy.ty.isInt) {
      return ExprTempValue(
          LLVMConstVariable(val!.getBaseValue(context), l.ty, Identifier.none));
    }

    return value;
  }

  static ExprTempValue? math(FnBuildMixin context, OpKind op, Variable? l,
      Expr? rhs, Identifier opIdent) {
    if (l == null) return null;
    final rhsExp = rhs?.build(context, baseTy: l.ty);

    final v = context.math(l, rhsExp?.variable, op, opIdent);

    return ExprTempValue(v);
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
  pointer('*'),
  none(''),
  ref('&');

  final String char;
  const PointerKind(this.char);

  static PointerKind? from(TokenKind kind) {
    if (kind == TokenKind.and) {
      return PointerKind.ref;
    } else if (kind == TokenKind.star) {
      return PointerKind.pointer;
    }
    return null;
  }

  Variable? refDeref(Variable? val, StoreLoadMixin c, Identifier id) {
    if (this == PointerKind.none) return val;
    Variable? inst;
    if (val != null) {
      if (this == PointerKind.pointer) {
        inst = val.defaultDeref(c, id);
      } else if (this == PointerKind.ref) {
        inst = val.getRef(c, id);
      }
    }
    return inst ?? val;
  }

  @override
  String toString() => char == '' ? '$runtimeType' : char;
}

extension ListPointerKind on List<PointerKind> {
  bool get isRef {
    return firstOrNull == PointerKind.ref;
  }

  Ty wrapRefTy(Ty baseTy) {
    for (var kind in this) {
      baseTy = RefTy.from(baseTy, kind == PointerKind.pointer);
    }
    return baseTy;
  }

  Ty unWrapRefTy(Ty baseTy) {
    for (var kind in this) {
      if (kind != PointerKind.none && baseTy is RefTy) {
        baseTy = baseTy.parent;
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
  Ty? getTy(StoreLoadMixin context) {
    return context.getVariable(ident)?.ty;
  }

  @override
  Expr clone() {
    return VariableIdentExpr(ident, generics).._isCatch = _isCatch;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    if (ident.src == 'null') {
      final ty = baseTy?.typeOf(context);

      if (ty == null) {
        return ExprTempValue.ty(BuiltInTy.kVoid);
      }
      final v = LLVMConstVariable(llvm.LLVMConstNull(ty), baseTy!, ident);
      return ExprTempValue(v);
    }

    final val = context.getVariable(ident);
    if (val != null) {
      return ExprTempValue(val.newIdent(ident));
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
      return ExprTempValue.ty(struct);
    }

    var fn = context.getFn(ident);
    if (fn == null) {
      fn = typeAlias?.getTy(context, generics);
      if (fn != null) {
        localGenerics = const [];
      }
    }
    if (fn != null) {
      var enableBuild = false;
      if (localGenerics.isNotEmpty) {
        fn = fn.newInstWithGenerics(context, localGenerics, fn.generics);
        enableBuild = true;
      }

      if (fn.generics.isEmpty) {
        enableBuild = true;
      }

      if (enableBuild) {
        final value = fn.genFn();
        if (value != null) {
          return ExprTempValue(value.newIdent(ident));
        }
      }
      return ExprTempValue.ty(fn);
    }

    final builtinFn = context.getBuiltinFn(ident);
    if (builtinFn != null) return ExprTempValue.ty(builtinFn);

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
    final builtinFn = context.getBuiltinFn(ident);
    if (builtinFn != null) return context.createVal(builtinFn, ident);

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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final val = current.build(context);
    var variable = val?.variable;
    if (variable == null) return val;

    var vv = kind.refDeref(val?.variable, context, pointerIdent);
    if (vv != null) {
      return ExprTempValue(vv.newIdent(pointerIdent));
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    throw StateError('use block.build(context) instead.');
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
          final ident = p.pattern;
          if (ident != null) {
            child.pushVariable(child.createVal(f.grt(child), ident));
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

  void build4(FnBuildMixin context, ExprTempValue parrern) {
    final child = context;
    final e = expr as VariableIdentExpr;
    child.pushVariable(parrern.variable!.newIdent(e.ident));
    block.build(child);
  }

  ExprTempValue? build3(FnBuildMixin context, ExprTempValue pattern) {
    return OpExpr.math(
        context, op ?? OpKind.Eq, pattern.variable, expr, Identifier.none);
  }

  int? build2(FnBuildMixin context, ExprTempValue pattern) {
    final child = context;
    var e = expr;
    int? value;
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
        value = enumTy.llty.load(child, val, params);
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

  ExprTempValue? commonExpr(
      FnBuildMixin context, ExprTempValue variable, Ty? baseTy) {
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

    if (baseTy != null) {
      retVariable = baseTy.llty.createAlloca(context, Identifier.none);
    }
    void buildItem(MatchItemExpr item, FnBuildMixin context) {
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
            context.builder, val.load(context), then.bb, elseBB.bb);
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
    return ExprTempValue(retVariable);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final variable = expr.build(context);
    if (variable == null) return null;
    final ty = variable.ty;
    if (ty is! EnumItem) {
      return commonExpr(context, variable, baseTy);
    }

    final itemLength = ty.parent.variants.length;

    final parent = variable.variable;
    if (parent == null) return null;

    StoreVariable? retVariable;
    final retTy = baseTy ?? _variable?.ty;
    if (retTy != null) {
      retVariable = retTy.llty.createAlloca(context, Identifier.none);
    }

    var indexValue = ty.llty.loadIndex(context, parent);

    final hasOther = items.any((e) => e.isOther);
    var length = items.length;

    if (length <= 2) {
      void buildItem(MatchItemExpr item, FnBuildMixin context) {
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
              ty.parent.llty.getIndexValue(context, itemIndex),
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
      final llPty = ty.parent.llty;
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
    return ExprTempValue(retVariable);
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
  Ty? getTy(StoreLoadMixin context) {
    return rhs.grt(context);
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    final r = rhs.grt(context);
    final l = lhs.analysis(context);

    if (l == null) return l;
    return context.createVal(r, l.ident);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final r = rhs.grt(context);
    final l = lhs.build(context, baseTy: r);
    final lv = l?.variable;
    if (l == null || lv == null) return null;

    final value = asType(context, lv, rhs.ident, r);
    return ExprTempValue(value);
  }

  static Variable asType(
      FnBuildMixin context, Variable lv, Identifier asId, Ty asTy) {
    final lty = lv.ty;

    if (asTy is BuiltInTy && lty is BuiltInTy) {
      final val = context.castLit(lty.ty, lv.load(context), asTy.ty);
      return LLVMConstVariable(val, asTy, asId);
    }
    Variable? asValue;

    final lValue = lv.load(context);

    if (lty is RefTy && asTy is BuiltInTy && asTy.ty.isInt) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildPtrToInt(context.builder, lValue, type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else if (lty is BuiltInTy && lty.ty.isInt && asTy is RefTy) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildIntToPtr(context.builder, lValue, type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else {
      asValue = LLVMConstVariable(lValue, asTy, asId);
    }

    return asValue;
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
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
  ArrayExpr(this.elements, this.identStart, this.identEnd);

  final Identifier identStart;
  final Identifier identEnd;

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

    if (ty == null) return null;
    return context.createVal(ArrayTy(ty, elements.length), Identifier.none);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final values = <LLVMValueRef>[];
    Ty? arrTy = baseTy;

    Ty? ty;
    if (arrTy is ArrayTy) {
      ty = arrTy.elementTy;
    }

    Ty? elementTy;
    for (var element in elements) {
      final v = element.build(context, baseTy: ty);
      final variable = v?.variable;
      if (variable != null) {
        elementTy ??= variable.ty;
        values.add(variable.load(context));
      }
    }

    ty ??= elementTy;

    if (arrTy == null && ty != null) {
      arrTy = ArrayTy(ty, elements.length);
    }
    if (arrTy is ArrayTy) {
      final extra = arrTy.size - values.length;
      if (extra > 0) {
        final zero =
            values.lastOrNull ?? llvm.LLVMConstNull(ty!.typeOf(context));
        values.addAll(List.generate(extra, (index) => zero));
      }
      final v = arrTy.llty.createArray(context, values);
      return ExprTempValue(v);
    }

    return null;
  }

  @override
  ArrayExpr clone() {
    return ArrayExpr(
        elements.map((e) => e.clone()).toList(), identStart, identEnd);
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
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final temp = expr.build(context);
    var val = temp?.variable;
    if (val == null) return null;
    if (op == UnaryKind.Not) {
      if (val.ty == BuiltInTy.kBool) {
        final value = val.load(context);
        final notValue = llvm.LLVMBuildNot(context.builder, value, unname);
        final variable = LLVMConstVariable(notValue, val.ty, opIdent);
        return ExprTempValue(variable);
      }

      return OpExpr.math(context, OpKind.Eq, val, null, opIdent);
    } else if (op == UnaryKind.Neg) {
      final va = val.load(context);
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
      final variable = LLVMConstVariable(llvmValue, val.ty, opIdent);
      return ExprTempValue(variable);
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

class ArrayOpExpr extends Expr {
  ArrayOpExpr(this.ident, this.arrayOrPtr, this.expr);
  final Identifier ident;
  final Expr arrayOrPtr;
  final Expr expr;
  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    final array = arrayOrPtr.build(context);
    if (array == null) return null;
    final arrVal = array.variable;
    final ty = arrVal?.ty;

    if (ty is StructTy) {
      final elIdent = Identifier.builtIn('elementAt');
      final implFn = context.getImplFnForStruct(ty, elIdent);

      if (implFn != null) {
        return AbiFn.fnCallInternal(context, implFn, ident,
            [FieldExpr(expr, ident)], arrVal, null, null);
      }
    }

    final loc = expr.build(context);
    final locVal = loc?.variable;
    if (arrVal == null || locVal == null || loc == null) return null;

    if (ty is ArrayTy) {
      final element =
          ty.llty.getElement(context, arrVal, locVal.load(context), ident);
      return ExprTempValue(element);
    } else if (ty is RefTy) {
      final offset = ident.offset;
      final index = locVal.load(context);
      final indics = <LLVMValueRef>[index];

      final p = arrVal.load(context);

      final elementTy = ty.parent.typeOf(context);

      final vv = LLVMAllocaVariable.delay(() {
        context.diSetCurrentLoc(offset);
        return llvm.LLVMBuildInBoundsGEP2(context.builder, elementTy, p,
            indics.toNative(), indics.length, unname);
      }, ty.parent, elementTy, ident);

      return ExprTempValue(vv);
    }

    return null;
  }

  @override
  ArrayOpExpr clone() {
    return ArrayOpExpr(ident, arrayOrPtr.clone(), expr.clone());
  }

  @override
  String toString() {
    return "$arrayOrPtr[$expr]";
  }
}
