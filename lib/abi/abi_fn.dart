import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/builders/builders.dart';
import '../ast/builders/coms.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/llvm_types.dart';
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
      FnBuildMixin context, Variable fn, FnDecl decl, List<FieldExpr> params);

  LLVMConstVariable createFunctionAbi(StoreLoadMixin c, FnDecl decl);

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

  bool isSret(StoreLoadMixin c, FnDecl fn);

  LLVMValueRef classifyFnRet(StoreLoadMixin context, Variable src);

  static ExprTempValue? fnCallInternal({
    required FnBuildMixin context,
    required Variable fn,
    required FnDecl decl,
    bool extern = false,
    Variable? struct,
    List<FieldExpr> params = const [],
    List<Variable> valArgs = const [],
    bool ignoreFree = false,
  }) {
    decl = decl.resolveGeneric(context, params);
    if (extern) {
      return AbiFn.get(context.abi).fnCall(context, fn, decl, params);
    }

    if (decl.isDyn) {
      decl = decl.toDyn();
    }

    final ident = fn.ident;
    final fields = decl.fields;
    final sortFields = alignParam(params, fields);

    final args = <LLVMValueRef>[];
    final retTy = decl.getRetTy(context);

    final fnAddr = decl is FnClosure
        ? LLVMFnClosureType.callClosure(context, fn, args)
        : fn.load(context);

    if (struct != null) {
      if (struct.ty is BuiltInTy) {
        args.add(struct.load(context));
      } else {
        args.add(struct.getBaseValue(context));
      }
    }

    void addArg(Variable v) {
      if (!ignoreFree) ImplStackTy.addStack(context, v);

      final ty = v.ty;
      if (ty.llty.getBytes(context) > 8) {
        final newVal = ty.llty.createAlloca(context, Identifier.none);
        newVal.store(context, v.load(context));
        v = newVal;

        args.add(newVal.alloca);
      } else {
        args.add(v.load(context));
      }
    }

    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? fieldTy;

      if (i < fields.length) {
        final p = fields[i];
        fieldTy = decl.getFieldTy(context, p);
      }
      final temp = p.build(context, baseTy: fieldTy);

      var variable = temp?.variable;
      if (variable == null) continue;

      final v = FnCatch.toFnClosure(context, fieldTy, variable);

      if (v != null) {
        args.add(v.getBaseValue(context));
        continue;
      }
      addArg(variable);
    }

    if (valArgs.isNotEmpty) {
      assert(params.isEmpty);
      for (var arg in valArgs) {
        addArg(arg);
      }
    }

    if (decl is FnCatch) {
      final variables = decl.getVariables();
      for (var val in variables) {
        args.add(val.getBaseValue(context));
      }
    }

    for (var field in fields) {
      if (decl.getFieldTy(context, field) case FnCatch ty) {
        final variables = ty.getVariables();
        for (var val in variables) {
          args.add(val.getBaseValue(context));
        }
      }
    }

    final fnType = decl.llty.createFnType(context);

    if (retTy.llty.getBytes(context) > 8) {
      final ret = LLVMAllocaProxyVariable(context, (variable, isProxy) {
        final sret = variable ?? retTy.llty.createAlloca(context, 'sret'.ident);
        args.insert(0, sret.alloca);

        context.diSetCurrentLoc(ident.offset);
        llvm.LLVMBuildCall2(context.builder, fnType, fnAddr, args.toNative(),
            args.length, unname);
      }, retTy, retTy.typeOf(context), 'sret'.ident);

      return ExprTempValue(ret);
    }

    context.diSetCurrentLoc(ident.offset);
    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnAddr, args.toNative(), args.length, unname);

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

  static LLVMConstVariable createFunction(FnBuildMixin c, Fn fn) {
    if (fn.fnDecl.extern) {
      return fn.llty.getOrCreate(c, () {
        return AbiFn.get(c.abi).createFunctionAbi(c, fn.fnDecl);
      });
    }
    return fn.llty.createFunction(c);
  }

  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnTy);

  static StoreVariable? initFnParams(
      FnBuildMixin context, LLVMValueRef fn, Fn fnTy,
      {bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    if (fnTy.fnDecl.extern) {
      return AbiFn.get(context.abi).initFnParamsImpl(context, fn, fnTy);
    }
    context.initFnParams(fn, fnTy, ignoreFree: ignoreFree);
    return null;
  }

  static LLVMValueRef fnRet(BuildContext context, Fn fn, Variable src) {
    if (fn.fnDecl.extern) {
      return AbiFn.get(context.abi).classifyFnRet(context, src);
    }
    return src.load(context);
  }
}
