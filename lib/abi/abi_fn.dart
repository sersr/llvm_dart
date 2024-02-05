import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/builders/builders.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/coms.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_dart.dart';
import 'abi_arm64.dart';
import 'abi_win_x86_64.dart';
import 'abi_x86_64.dart';

enum Abi {
  winx86_64('x86_64', true),
  wini686('i686', true),
  arm64('arm64', false),
  x86_64('x86_64', false);

  final String name;
  final bool isWindows;
  const Abi(this.name, this.isWindows);

  static Abi? from(String text, bool isWin) {
    return values
        .firstWhereOrNull((e) => e.name == text && e.isWindows == isWin);
  }

  @override
  String toString() {
    return name;
  }
}

abstract interface class AbiFn {
  ExprTempValue? fnCall(
      FnBuildMixin context, Fn fn, Identifier ident, List<FieldExpr> params);

  LLVMConstVariable createFunctionAbi(StoreLoadMixin c, Fn fn);

  static final _instances = <Abi, AbiFn>{};

  factory AbiFn.get(Abi abi) {
    return _instances.putIfAbsent(abi, () {
      return switch (abi) {
        Abi.x86_64 => AbiFnx86_64(),
        Abi.winx86_64 || Abi.wini686 => AbiFnWinx86_64(),
        _ => AbiFnArm64(),
      };
    });
  }

  bool isSret(StoreLoadMixin c, Fn fn);

  LLVMValueRef classifyFnRet(StoreLoadMixin context, Variable src);

  static ExprTempValue? fnCallInternal({
    required FnBuildMixin context,
    required Fn fn,
    Variable? struct,
    Identifier? ident,
    List<FieldExpr> params = const [],
    List<Variable> valArgs = const [],
    Set<AnalysisVariable>? extra,
    Map<Identifier, Set<AnalysisVariable>>? map,
    bool ignoreFree = false,
  }) {
    ident ??= Identifier.none;
    if (fn.extern) {
      return AbiFn.get(context.abi).fnCall(context, fn, ident, params);
    }

    fn = fn.resolveGeneric(context, params);

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
          baseTy = fn.getFieldTy(context, fnParams[i]);
        }
        baseTy ??= p.getTy(context);
        final temp = p.build(context, baseTy: baseTy);
        var v = temp?.variable;
        if (v != null) {
          v = v.newIdent(fnParams[i].ident);
          newParams.add(v);
        }
      }

      var variable = context.compileRun(fn, newParams);
      if (variable == null) return null;

      return ExprTempValue(variable);
    }

    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    if (struct != null && fn is ImplFn) {
      if (struct.ty is BuiltInTy) {
        args.add(struct.load(context));
      } else {
        args.add(struct.getBaseValue(context));
      }
    }

    void addArg(Variable? v) {
      if (v != null) {
        if (!ignoreFree) ImplStackTy.addStack(context, v);
        args.add(v.load(context));
      }
    }

    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fnParams.length) {
        final p = fnParams[i];
        c = fn.getFieldTy(context, p);
      }
      final temp = p.build(context, baseTy: c);
      addArg(temp?.variable);
    }

    void addCatchArg(Variable? v) {
      if (v != null) {
        args.add(v.getBaseValue(context));
      }
    }

    for (var variable in fn.variables) {
      var v = context.getVariable(variable.ident);
      addCatchArg(v);
    }

    if (extra != null) {
      for (var variable in extra) {
        var v = context.getVariable(variable.ident);
        addCatchArg(v);
      }
    }

    if (fn is FnTy) {
      final params = fn.fnSign.fnDecl.params;
      for (var p in params) {
        var v = context.getVariable(p.ident);
        addCatchArg(v);
      }
    }

    if (valArgs.isNotEmpty) {
      assert(params.isEmpty);
      for (var arg in valArgs) {
        addArg(arg);
      }
    }

    final fnType = fn.llty.createFnType(context, extra);

    final fnAlloca = fn.genFn(extra, map, ignoreFree);
    if (fnAlloca == null) return null;
    final fnValue = fnAlloca.load(context);

    context.diSetCurrentLoc(ident.offset);
    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    if (retTy.isTy(LiteralKind.kVoid.ty)) {
      return null;
    }

    final retIdent = '_ret'.ident;

    if (retTy is EnumItem) {
      Log.e('return type error:\nuse enum type: ${retTy.parent.ident}.');
      return null;
    }

    final v = switch (retTy) {
      StructTy() ||
      EnumTy() =>
        LLVMAllocaProxyVariable(context, (StoreVariable? value, _) {
          if (ImplStackTy.hasStack(context, retTy)) {
            /// com Stack 需要一个地址空间
            value ??= retTy.llty.createAlloca(context, retIdent);
          }

          value?.store(context, ret);
        }, retTy, retTy.typeOf(context), retIdent),
      RefTy(parent: var ty, isPointer: false) =>
        LLVMAllocaVariable(ret, ty, ty.typeOf(context), retIdent),
      _ => LLVMConstVariable(ret, retTy, retIdent),
    };

    return ExprTempValue(v);
  }

  static LLVMConstVariable createFunction(
      FnBuildMixin c, Fn fn, Set<AnalysisVariable>? variables) {
    if (fn.extern) {
      return fn.llty.getOrCreate(() {
        return AbiFn.get(c.abi).createFunctionAbi(c, fn);
      });
    }
    return fn.llty.createFunction(c, variables);
  }

  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnty);

  static StoreVariable? initFnParams(FnBuildMixin context, LLVMValueRef fn,
      Fn fnty, Set<AnalysisVariable>? extra,
      {bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    if (fnty.extern) {
      return AbiFn.get(context.abi).initFnParamsImpl(context, fn, fnty);
    }
    context.initFnParams(fn, fnty, extra, ignoreFree: ignoreFree, map: map);
    return null;
  }

  static LLVMValueRef fnRet(BuildContext context, Fn fn, Variable src) {
    if (fn.extern) {
      return AbiFn.get(context.abi).classifyFnRet(context, src);
    }
    return src.load(context);
  }
}
