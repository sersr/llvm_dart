import 'dart:ffi';

import '../ast/ast.dart';
import '../ast/builders/builders.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'abi_fn.dart';

class AbiFnArm64 implements AbiFn {
  @override
  bool isSret(StoreLoadMixin c, Fn fn) {
    var retTy = fn.getRetTy(c);
    if (retTy is StructTy) {
      final size = retTy.llty.getBytes(c);
      if (size > 16) return true;
    }
    return false;
  }

  @override
  ExprTempValue? fnCall(
    FnBuildMixin context,
    Fn fn,
    Identifier ident,
    List<FieldExpr> params,
  ) {
    final fnAlloca = fn.genFn();
    if (fnAlloca == null) return null;
    final fnValue = fnAlloca.getBaseValue(context);

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    StoreVariable? sret;
    if (isSret(context, fn)) {
      sret = retTy.llty.createAlloca(context, Identifier.builtIn('sret'));

      args.add(sret.alloca);
    }

    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    final listNoundefs = <int>[];
    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fnParams.length) {
        c = fn.getRty(context, fnParams[i]);
      }
      final temp = p.build(context, baseTy: c);
      final v = temp?.variable;
      if (v != null) {
        LLVMValueRef value;
        final vty = v.ty;
        if (vty is StructTy) {
          final (sfp, tyValue) = toFnParams(context, vty, v);
          if (sfp == Reg.byval) {
            listNoundefs.add(i + 1);
          }
          value = tyValue;
        } else {
          value = v.load(context);
        }

        args.add(value);
      }
    }

    for (var variable in fn.variables) {
      var v = context.getVariable(variable.ident);
      if (v == null) {
        // error
        continue;
      }
      args.add(v.load(context));
    }

    final fnType = createFnType(context, fn);

    context.diSetCurrentLoc(ident.offset);

    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    for (var index in listNoundefs) {
      final attr = llvm.LLVMCreateEnumAttribute(
          context.llvmContext, LLVMAttr.NoUndef, 0);
      llvm.LLVMAddCallSiteAttribute(ret, index, attr);
    }

    if (sret != null) {
      return ExprTempValue(sret);
    }
    if (retTy == BuiltInTy.kVoid) {
      return null;
    }

    Variable v;
    if (retTy is StructTy) {
      v = fromFnParamsOrRet(context, retTy, ret, Identifier.none);
    } else {
      v = LLVMAllocaDelayVariable((proxy) {
        final alloca =
            proxy ?? retTy.llty.createAlloca(context, Identifier.none);
        alloca.store(context, ret);
        return alloca.alloca;
      }, retTy, retTy.typeOf(context), Identifier.none);
    }

    return ExprTempValue(v);
  }

  LLVMTypeRef getCStructFnParamTy(StoreLoadMixin context, StructTy ty) {
    var count = ty.llty.getBytes(context);
    if (count > 16) {
      return context.pointer();
    }

    final onlyFloat = ty.fields.every((e) => e.grt(context) == BuiltInTy.f32);
    if (onlyFloat) {
      final size = (count / 4).ceil();
      return context.arrayType(context.f32, size);
    }

    final onlyDouble = ty.fields.every((e) => e.grt(context) == BuiltInTy.f64);
    if (onlyDouble) {
      final size = (count / 8).ceil();
      return context.arrayType(context.f64, size);
    }

    final arrayCount = count ~/ 8;

    final extra = count % 8;
    final loadTy = context.i64;
    final list = <LLVMTypeRef>[];
    for (var i = 0; i < arrayCount; i++) {
      list.add(loadTy);
    }

    if (extra > 0) {
      list.add(context.i32);
    }

    return context.typeStruct(list, null);
  }

  (Reg, LLVMValueRef) toFnParams(
      StoreLoadMixin context, StructTy struct, Variable variable) {
    final byteSize = struct.llty.getBytes(context);
    if (byteSize > 16) {
      final llType = struct.typeOf(context);
      final copyValue = context.alloctor(llType);
      llvm.LLVMBuildMemCpy(context.builder, copyValue, 0,
          variable.getBaseValue(context), 0, context.usizeValue(byteSize));
      return (Reg.byval, copyValue);
    }
    final cTy = getCStructFnParamTy(context, struct);
    final align = context.getBaseAlignSize(struct);
    final llValue = llvm.LLVMBuildLoad2(
        context.builder, cTy, variable.getBaseValue(context), unname);
    llvm.LLVMSetAlignment(llValue, align);
    return (Reg.none, llValue);
  }

  LLVMAllocaVariable fromFnParamsOrRet(StoreLoadMixin context, StructTy struct,
      LLVMValueRef src, Identifier ident) {
    final byteSize = struct.llty.getBytes(context);
    final llType = struct.typeOf(context);

    if (byteSize <= 16) {
      return struct.llty.createAlloca(context, ident)..store(context, src);
    }

    context.setName(src, ident.src);
    // ptr
    return LLVMAllocaVariable(src, struct, llType, ident);
  }

  @override
  LLVMValueRef classifyFnRet(StoreLoadMixin context, Variable src) {
    final ty = src.ty;
    if (ty is! StructTy) return src.load(context);
    final byteSize = ty.llty.getBytes(context);

    if (byteSize > 16) {
      /// error: 已经经过sret 处理了
      throw StateError('should use sret.');
    }

    final llType = getCStructFnParamTy(context, ty);
    return llvm.LLVMBuildLoad2(
        context.builder, llType, src.getBaseValue(context), unname);
  }

  LLVMTypeRef createFnType(StoreLoadMixin c, Fn fn) {
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];
    var retTy = fn.getRetTy(c);

    var retIsSret = isSret(c, fn);
    if (retIsSret) {
      list.add(c.typePointer(retTy.typeOf(c)));
    }

    LLVMTypeRef cType(Ty tty) {
      LLVMTypeRef ty;
      if (tty is StructTy) {
        ty = getCStructFnParamTy(c, tty);
      } else {
        ty = tty.typeOf(c);
      }
      return ty;
    }

    for (var p in params) {
      final realTy = fn.getRty(c, p);
      LLVMTypeRef ty = cType(realTy);
      list.add(ty);
    }

    LLVMTypeRef ret;

    if (retIsSret) {
      ret = c.typeVoid;
    } else {
      ret = cType(retTy);
    }

    return c.typeFn(list, ret, fn.fnSign.fnDecl.isVar);
  }

  @override
  LLVMConstVariable createFunctionAbi(
      StoreLoadMixin c, Fn fn, void Function(LLVMConstVariable fnValue) after) {
    final ty = createFnType(c, fn);
    var ident = fn.fnName.src;
    if (ident.isEmpty) {
      ident = '_fn';
    }

    final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
    llvm.LLVMSetLinkage(v, LLVMLinkage.LLVMExternalLinkage);

    var retTy = fn.getRetTy(c);
    if (isSret(c, fn)) {
      c.setFnLLVMAttr(v, 1, LLVMAttr.StructRet);
    }

    final offset = fn.fnSign.fnDecl.ident.offset;

    final dBuilder = c.dBuilder;
    if (dBuilder != null && fn.block?.isNotEmpty == true) {
      final file = llvm.LLVMDIScopeGetFile(c.unit);
      final params = <Pointer>[];
      params.add(retTy.llty.createDIType(c));

      for (var p in fn.fnSign.fnDecl.params) {
        final realTy = fn.getRty(c, p);
        final ty = realTy.llty.createDIType(c);
        params.add(ty);
      }
      final (namePointer, nameLength) = ident.toNativeUtf8WithLength();

      final fnTy = llvm.LLVMDIBuilderCreateSubroutineType(
          dBuilder, file, params.toNative(), params.length, 0);
      final fnScope = llvm.LLVMDIBuilderCreateFunction(
          dBuilder,
          c.unit,
          namePointer,
          nameLength,
          unname,
          0,
          file,
          offset.row,
          fnTy,
          LLVMFalse,
          LLVMTrue,
          offset.row,
          0,
          LLVMFalse);

      llvm.LLVMSetSubprogram(v, fnScope);

      c.diSetCurrentLoc(offset);
    }

    c.setFnLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.NoInline); // Function
    final fnVaraible = LLVMConstVariable(v, fn, fn.fnName);
    after(fnVaraible);
    return fnVaraible;
  }

  @override
  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnty) {
    var index = 0;
    assert(context.isFnBBContext);

    LLVMAllocaVariable? sret;

    var retTy = fnty.getRetTy(context);

    if (isSret(context, fnty)) {
      final first = llvm.LLVMGetParam(fn, index);
      final alloca = LLVMAllocaVariable(
          first, retTy, retTy.typeOf(context), Identifier.none);
      index += 1;
      sret = alloca;
    }

    final params = fnty.fnSign.fnDecl.params;
    for (var i = 0; i < params.length; i++) {
      final p = params[i];

      final fnParam = llvm.LLVMGetParam(fn, i + index);
      var realTy = fnty.getRty(context, p);
      resolveParam(context, realTy, fnParam, p.ident);
    }

    return sret;
  }

  void resolveParam(
      StoreLoadMixin context, Ty ty, LLVMValueRef fnParam, Identifier ident) {
    Variable alloca;
    if (ty is StructTy) {
      alloca = fromFnParamsOrRet(context, ty, fnParam, ident);
    } else {
      final a = ty.llty.createAlloca(context, ident);
      a.store(context, fnParam);
      alloca = a;
    }

    context.pushVariable(alloca);
  }
}

enum Reg {
  none,
  byval,
}
