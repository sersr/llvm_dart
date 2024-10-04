import '../ast/ast.dart';
import '../ast/builders/builders.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_dart.dart';
import 'abi_fn.dart';

class AbiFnArm64 implements AbiFn {
  @override
  bool isSret(StoreLoadMixin c, FnDecl decl) {
    var retTy = decl.getRetTy(c);
    if (retTy is StructTy) {
      final size = retTy.llty.getBytes(c);
      if (size > 16) return true;
    }
    return false;
  }

  @override
  ExprTempValue? fnCall(
      FnBuildMixin context, Variable fn, FnDecl decl, List<FieldExpr> params) {
    final fnValue = fn.load(context);

    final fields = decl.fields;
    final args = <LLVMValueRef>[];
    final retTy = decl.getRetTy(context);

    StoreVariable? sret;
    if (isSret(context, decl)) {
      sret = retTy.llty.createAlloca(context, 'sret'.ident);

      args.add(sret.alloca);
    }

    final sortFields = alignParam(params, fields);

    final listNoundefs = <int>[];
    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fields.length) {
        c = decl.getFieldTy(context, fields[i]);
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

    // for (var variable in fn.variables) {
    //   var v = context.getVariable(variable.ident);
    //   if (v == null) {
    //     // error
    //     continue;
    //   }
    //   args.add(v.load(context));
    // }

    final fnType = createFnType(context, decl);

    context.diSetCurrentLoc(fn.ident.offset);

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
    if (retTy.isTy(LiteralKind.kVoid.ty)) {
      return null;
    }

    final retIdent = '_ret'.ident;

    final v = switch (retTy) {
      StructTy() => fromFnParamsOrRet(context, retTy, ret, Identifier.none),
      RefTy(parent: var ty, isPointer: false) =>
        LLVMAllocaVariable(ret, ty, ty.typeOf(context), retIdent),
      _ => LLVMConstVariable(ret, retTy, retIdent)
    };

    return ExprTempValue(v);
  }

  LLVMTypeRef getCStructFnParamTy(StoreLoadMixin context, StructTy ty) {
    var count = ty.llty.getBytes(context);
    if (count > 16) {
      return context.pointer();
    }

    final onlyFloat =
        ty.fields.every((e) => e.grt(context).isTy(LiteralKind.f32.ty));
    if (onlyFloat) {
      final size = (count / 4).ceil();
      return context.arrayType(context.f32, size);
    }

    final onlyDouble =
        ty.fields.every((e) => e.grt(context).isTy(LiteralKind.f64.ty));

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

    if (ident.isValid) context.setName(src, ident.src);
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

  LLVMTypeRef createFnType(StoreLoadMixin c, FnDecl decl) {
    final params = decl.fields;
    final list = <LLVMTypeRef>[];
    var retTy = decl.getRetTy(c);

    var retIsSret = isSret(c, decl);
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
      final realTy = decl.getFieldTy(c, p);
      LLVMTypeRef ty = cType(realTy);
      list.add(ty);
    }

    LLVMTypeRef ret;

    if (retIsSret) {
      ret = c.typeVoid;
    } else {
      ret = cType(retTy);
    }

    return c.typeFn(list, ret, decl.isVar);
  }

  @override
  LLVMConstVariable createFunctionAbi(StoreLoadMixin c, FnDecl decl) {
    final ty = createFnType(c, decl);
    var ident = decl.ident.src;
    if (ident.isEmpty) {
      ident = '_fn';
    }

    final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
    llvm.LLVMSetLinkage(v, LLVMLinkage.LLVMExternalLinkage);

    if (isSret(c, decl)) {
      c.setFnLLVMAttr(v, 1, LLVMAttr.StructRet);
    }

    c.setFnLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.NoInline); // Function
    return LLVMConstVariable(v, decl, decl.ident);
  }

  @override
  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnTy, FnDecl fnDecl) {
    var index = 0;
    final decl = fnDecl;
    assert(context.isFnBBContext);

    LLVMAllocaVariable? sret;

    var retTy = decl.getRetTy(context);

    if (isSret(context, decl)) {
      final first = llvm.LLVMGetParam(fn, index);
      final alloca = LLVMAllocaVariable(
          first, retTy, retTy.typeOf(context), Identifier.none);
      index += 1;
      sret = alloca;
    }

    final params = decl.fields;
    for (var i = 0; i < params.length; i++) {
      final p = params[i];

      final fnParam = llvm.LLVMGetParam(fn, i + index);
      var realTy = decl.getFieldTy(context, p);
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
