import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'abi_arm64.dart';
import 'abi_win_x86_64.dart';
import 'abi_x86_64.dart';

enum Abi {
  winx86_64('x86_64', true),
  arm64('arm64', false),
  x86_64('x86_64', false);

  final String name;
  final bool isWindows;
  const Abi(this.name, this.isWindows);

  @override
  String toString() {
    return name;
  }
}

abstract interface class AbiFn {
  ExprTempValue? fnCall(
      FnBuildMixin context, Fn fn, Identifier ident, List<FieldExpr> params);

  LLVMConstVariable createFunctionAbi(
      StoreLoadMixin c, Fn fn, void Function(LLVMConstVariable fnValue) after);

  static final _instances = <Abi, AbiFn>{};

  factory AbiFn.get(Abi abi) {
    return _instances.putIfAbsent(abi, () {
      return switch (abi) {
        Abi.x86_64 => AbiFnx86_64(),
        Abi.winx86_64 => AbiFnWinx86_64(),
        _ => AbiFnArm64(),
      };
    });
  }

  bool isSret(StoreLoadMixin c, Fn fn);

  LLVMValueRef classifyFnRet(StoreLoadMixin context, Variable src);

  static ExprTempValue? fnCallInternal(
      FnBuildMixin context,
      Fn fn,
      Identifier ident,
      List<FieldExpr> params,
      Variable? struct,
      Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>>? map) {
    if (fn.extern) {
      return AbiFn.get(context.abi).fnCall(context, fn, ident, params);
    }

    fn = StructExpr.resolveGeneric(fn, context, params, []);

    final fnParams = fn.fnSign.fnDecl.params;
    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    if (fn is ImplStaticFn &&
        fn.fnName.src == 'new' &&
        context.compileRunMode(fn)) {
      final newParams = <Variable>[];
      for (var i = 0; i < sortFields.length; i++) {
        final p = sortFields[i];
        Ty? baseTy;
        if (i < fnParams.length) {
          baseTy = fn.getRty(context, fnParams[i]);
        }
        baseTy ??= p.getTy(context);
        final temp = p.build(context, baseTy: baseTy);
        var v = temp?.variable;
        if (v != null) {
          v = v.newIdent(fnParams[i].ident);
          newParams.add(v);
        }
      }

      final variable = context.compileRun(fn, newParams);
      if (variable == null) return null;
      return ExprTempValue(variable);
    }

    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    if (struct != null && fn is ImplFn) {
      // fixme: remove
      if (struct.ty is BuiltInTy) {
        args.add(struct.load(context));
      } else {
        args.add(struct.getBaseValue(context));
      }
    }
    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fnParams.length) {
        c = fn.getRty(context, fnParams[i]);
      }
      final temp = p.build(context, baseTy: c);
      final v = temp?.variable;
      if (v != null) {
        final value = v.load(context);

        args.add(value);
      }
    }

    void addArg(Variable? v, Identifier ident) {
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
      addArg(v, variable.ident);
    }

    if (extra != null) {
      for (var variable in extra) {
        var v = context.getVariable(variable.ident);
        addArg(v, variable.ident);
      }
    }

    if (fn is FnTy) {
      final params = fn.fnSign.fnDecl.params;
      for (var p in params) {
        var v = context.getVariable(p.ident);
        addArg(v, p.ident);
      }
    }

    final fnType = fn.llty.createFnType(context, extra);

    final fnAlloca = fn.genFn(extra, map);
    if (fnAlloca == null) return null;
    final fnValue = fnAlloca.load(context);

    context.diSetCurrentLoc(ident.offset);
    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    if (retTy == BuiltInTy.kVoid) {
      return null;
    }

    // 这里还是一个零时变量
    final v = LLVMConstVariable(ret, retTy, Identifier.none);
    context.autoAddFreeHeap(v);

    return ExprTempValue(v);
  }

  static LLVMConstVariable createFunction(
      FnBuildMixin c,
      Fn fn,
      Set<AnalysisVariable>? variables,
      void Function(LLVMConstVariable fnValue) after) {
    if (fn.extern) {
      return fn.llty.getOrCreate(() {
        return AbiFn.get(c.abi).createFunctionAbi(c, fn, after);
      });
    }
    return fn.llty.createFunction(c, variables, after);
  }

  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnty);

  static StoreVariable? initFnParams(FnBuildMixin context, LLVMValueRef fn,
      FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    if (fnty.extern) {
      return AbiFn.get(context.abi).initFnParamsImpl(context, fn, fnty);
    }
    context.initFnParams(fn, decl, fnty, extra, map: map);
    return context.sret;
  }

  static LLVMValueRef fnRet(BuildContext context, Fn fn, Variable src) {
    if (fn.extern) {
      return AbiFn.get(context.abi).classifyFnRet(context, src);
    }
    return src.load(context);
  }
}
