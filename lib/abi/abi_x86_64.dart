import 'dart:ffi';

import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'abi_fn.dart';

// ignore: camel_case_types
class AbiFnx86_64 implements AbiFn {
  @override
  bool isSret(BuildContext c, Fn fn) {
    var retTy = fn.getRetTy(c);
    if (retTy is StructTy) {
      final size = retTy.llty.getBytes(c);
      if (size > 16) return true;
    }
    return false;
  }

  @override
  ExprTempValue? fnCall(
    BuildContext context,
    Fn fn,
    List<FieldExpr> params,
  ) {
    final fnAlloca = fn.build(const {}, const {});
    if (fnAlloca == null) return null;
    final fnValue = fnAlloca.getBaseValue(context);

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    StoreVariable? sret;
    if (isSret(context, fn)) {
      sret = retTy.llty.createAlloca(context, Identifier.builtIn('sret'), null);

      args.add(sret.alloca);
    }

    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    final listByvals = <(int, LLVMTypeRef)>[];
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
            listByvals.add((i + 1, vty.typeOf(context)));
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

    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    for (var (index, ty) in listByvals) {
      context.setCallLLVMAttr(ret, index, LLVMAttr.NoUndef);
      context.setCallTypeAttr(ret, index, LLVMAttr.ByVal, ty);
    }

    if (sret != null) {
      context.autoAddFreeHeap(sret);
      return ExprTempValue(sret);
    }
    if (retTy == BuiltInTy.kVoid) {
      return null;
    }

    Variable v;
    if (retTy is StructTy) {
      v = fromFnParamsOrRet(context, retTy, ret);
    } else {
      v = LLVMConstVariable(ret, retTy, Identifier.none);
    }
    context.autoAddFreeHeap(v);

    return ExprTempValue(v);
  }

  LLVMTypeRef getCStructFnParamTy(BuildContext context, StructTy ty) {
    var count = ty.llty.getBytes(context);
    if (count > 16) {
      return context.pointer();
    }

    final list = <LLVMTypeRef>[];
    final map = ty.llty.getFieldsSize(context).map;

    var hasFloat = true;

    bool checkFloat(Ty ty) {
      if (ty is StructTy) {
        return ty.fields.every((e) => checkFloat(e.grt(context)));
      }
      return ty is BuiltInTy && ty.ty.isFp;
    }

    var num = 8;
    var currentOffset = 0;

    for (var item in ty.fields) {
      final index = map[item]!;
      if (index.diOffset >= num) {
        list.add(hasFloat ? context.f64 : context.i64);
        hasFloat = true;
        currentOffset = index.diOffset;
        num += 8;
      }

      hasFloat &= checkFloat(item.grt(context));
    }

    final extra = count - currentOffset;
    if (extra > 0) {
      if (extra <= 4) {
        list.add(hasFloat ? context.f32 : context.i32);
      } else {
        list.add(hasFloat ? context.f64 : context.i64);
      }
    }

    return context.typeStruct(list, null);
  }

  (Reg, LLVMValueRef) toFnParams(
      BuildContext context, StructTy struct, Variable variable) {
    final byteSize = struct.llty.getBytes(context);
    if (byteSize > 16) {
      return (Reg.byval, variable.getBaseValue(context));
    }
    final cTy = getCStructFnParamTy(context, struct);
    final align = context.getBaseAlignSize(struct);
    final llValue = llvm.LLVMBuildLoad2(
        context.builder, cTy, variable.getBaseValue(context), unname);
    llvm.LLVMSetAlignment(llValue, align);
    return (Reg.none, llValue);
  }

  Variable fromFnParamsOrRet(
      BuildContext context, StructTy struct, LLVMValueRef src,
      {Identifier? ident}) {
    ident ??= Identifier.none;
    final byteSize = struct.llty.getBytes(context);
    final llType = struct.typeOf(context);

    if (byteSize <= 16) {
      return struct.llty.createAlloca(context, ident, src)..initProxy(context);
    }

    // ptr
    return LLVMAllocaVariable(src, struct, llType, ident);
  }

  @override
  LLVMValueRef classifyFnRet(BuildContext context, Variable src) {
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

  LLVMTypeRef createFnType(BuildContext c, Fn fn) {
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
      BuildContext c, Fn fn, void Function(LLVMConstVariable fnValue) after) {
    final ty = createFnType(c, fn);
    var ident = fn.fnName.src;
    if (ident.isEmpty) {
      ident = '_fn';
    }

    final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
    llvm.LLVMSetLinkage(v, LLVMLinkage.LLVMExternalLinkage);

    var retTy = fn.getRetTy(c);
    var index = 0;
    if (isSret(c, fn)) {
      c.setFnLLVMAttr(v, 1, LLVMAttr.StructRet);
      index += 1;
    }

    for (var p in fn.fnSign.fnDecl.params) {
      index += 1;
      final realTy = fn.getRty(c, p);
      if (realTy is StructTy) {
        final size = realTy.llty.getBytes(c);
        if (size > 16) {
          final ty = realTy.typeOf(c);
          c.setFnLLVMAttr(v, index, LLVMAttr.NoUndef);
          c.setFnTypeAttr(v, index, LLVMAttr.ByVal, ty);
        }
      }
    }
    final offset = fn.fnSign.fnDecl.ident.offset;

    final dBuilder = c.dBuilder;
    if (dBuilder != null && fn.block?.stmts.isNotEmpty == true) {
      final file = llvm.LLVMDIScopeGetFile(c.unit);
      final params = <Pointer>[];
      params.add(retTy.llty.createDIType(c));

      for (var p in fn.fnSign.fnDecl.params) {
        index += 1;
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
      BuildContext context, LLVMValueRef fn, Fn fnty) {
    var index = 0;
    assert(context.isFnBBContext);

    LLVMAllocaVariable? sret;

    var retTy = fnty.getRetTy(context);

    if (isSret(context, fnty)) {
      final first = llvm.LLVMGetParam(fn, index);
      final alloca = LLVMAllocaVariable(
          first, retTy, retTy.typeOf(context), Identifier.none);
      alloca.isTemp = false;
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
      BuildContext context, Ty ty, LLVMValueRef fnParam, Identifier ident) {
    Variable alloca;
    if (ty is StructTy) {
      alloca = fromFnParamsOrRet(context, ty, fnParam);
    } else {
      final a = ty.llty.createAlloca(context, ident, fnParam);
      a.initProxy(context);
      context.setName(a.alloca, ident.src);
      alloca = a;
    }
    if (alloca is StoreVariable) alloca.isTemp = false;
    context.pushVariable(alloca);
  }
}

enum Reg {
  none,
  byval,
}
