import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'abi_arm64.dart';
import 'abi_x86_64.dart';

enum Abi {
  arm64('arm64'),
  x86_64('x86_64');

  final String name;
  const Abi(this.name);

  @override
  String toString() {
    return name;
  }
}

abstract interface class AbiFn {
  ExprTempValue? fnCall(
    BuildContext context,
    Fn fn,
    List<FieldExpr> params,
    Identifier currentIdent,
  );

  LLVMConstVariable createFunctionAbi(
      BuildContext c, Fn fn, void Function(LLVMConstVariable fnValue) after);

  static final _instances = <Abi, AbiFn>{};

  factory AbiFn.get(Abi abi) {
    return _instances.putIfAbsent(abi, () {
      return switch (abi) {
        Abi.x86_64 => AbiFnx86_64(),
        _ => AbiFnArm64(),
      };
    });
  }

  bool isSret(BuildContext c, Fn fn);

  LLVMValueRef classifyFnRet(BuildContext context, Variable src, Offset offset);

  static ExprTempValue? fnCallInternal(
      BuildContext context,
      Fn fn,
      List<FieldExpr> params,
      Variable? struct,
      Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>>? map,
      Identifier currentIdent) {
    if (fn.extern) {
      return AbiFn.get(context.abi).fnCall(context, fn, params, currentIdent);
    }

    fn = StructExpr.resolveGeneric(fn, context, params, []);

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    if (struct != null && fn is ImplFn) {
      if (struct.ty is BuiltInTy) {
        args.add(struct.load(context, Offset.zero));
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
      final temp = p.build(context, baseTy: c);
      final v = temp?.variable;
      if (v != null) {
        final value = v.load(context, temp!.currentIdent.offset);

        args.add(value);
      }
    }

    void addArg(Variable? v, Identifier ident) {
      if (v != null) {
        LLVMValueRef value;
        if (v is StoreVariable) {
          value = v.alloca;
        } else {
          value = v.load(context, ident.offset);
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

    final fnType = fn.llvmType.createFnType(context, extra);

    final fnAlloca = fn.build(extra, map);
    final fnValue = fnAlloca?.load(context, Offset.zero);
    if (fnValue == null) return null;

    context.diSetCurrentLoc(currentIdent.offset);
    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    if (retTy == BuiltInTy.kVoid) {
      return null;
    }

    final v = LLVMConstVariable(ret, retTy);
    context.autoAddFreeHeap(v);

    return ExprTempValue(v, v.ty, currentIdent);
  }

  static LLVMConstVariable createFunction(
      BuildContext c,
      Fn fn,
      Set<AnalysisVariable>? variables,
      void Function(LLVMConstVariable fnValue) after) {
    if (fn.extern) {
      return fn.llvmType.getOrCreate(() {
        return AbiFn.get(c.abi).createFunctionAbi(c, fn, after);
      });
    }
    return fn.llvmType.createFunction(c, variables, after);
  }

  LLVMAllocaVariable? initFnParamsImpl(
      BuildContext context, LLVMValueRef fn, Fn fnty);

  static StoreVariable? initFnParams(BuildContext context, LLVMValueRef fn,
      FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    if (fnty.extern) {
      return AbiFn.get(context.abi).initFnParamsImpl(context, fn, fnty);
    }
    context.initFnParams(fn, decl, fnty, extra, map: map);
    return context.sret;
  }

  static LLVMValueRef fnRet(
      BuildContext context, Fn fn, Variable src, Offset offset) {
    if (fn.extern) {
      return AbiFn.get(context.abi).classifyFnRet(context, src, offset);
    }
    return src.load(context, offset);
  }
}
