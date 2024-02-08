import '../ast/ast.dart';
import '../ast/builders/builders.dart';
import '../ast/expr.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_dart.dart';
import 'abi_fn.dart';

// ignore: camel_case_types
class AbiFnx86_64 implements AbiFn {
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

    final fnParams = decl.fields;
    final args = <LLVMValueRef>[];
    final retTy = decl.getRetTy(context);

    StoreVariable? sret;
    if (isSret(context, decl)) {
      sret = retTy.llty.createAlloca(context, 'sret'.ident);

      args.add(sret.alloca);
    }

    final sortFields = alignParam(
        params, (p) => fnParams.indexWhere((e) => e.ident == p.ident));

    final listByvals = <(int, LLVMTypeRef)>[];
    for (var i = 0; i < sortFields.length; i++) {
      final p = sortFields[i];
      Ty? c;
      if (i < fnParams.length) {
        c = decl.getFieldTy(context, fnParams[i]);
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

    for (var (index, ty) in listByvals) {
      context.setCallLLVMAttr(ret, index, LLVMAttr.NoUndef);
      context.setCallTypeAttr(ret, index, LLVMAttr.ByVal, ty);
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

    final list = <LLVMTypeRef>[];
    final map = ty.llty.getFieldsSize(context).map;

    var hasFloat = true;

    bool checkFloat(Ty ty) {
      if (ty is StructTy) {
        return ty.fields.every((e) => checkFloat(e.grt(context)));
      }
      return ty is BuiltInTy && ty.literal.isFp;
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
      StoreLoadMixin context, StructTy struct, Variable variable) {
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

  Variable fromFnParamsOrRet(StoreLoadMixin context, StructTy struct,
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

    var index = 0;
    if (isSret(c, decl)) {
      c.setFnLLVMAttr(v, 1, LLVMAttr.StructRet);
      index += 1;
    }

    for (var p in decl.fields) {
      index += 1;
      final realTy = decl.getFieldTy(c, p);
      if (realTy is StructTy) {
        final size = realTy.llty.getBytes(c);
        if (size > 16) {
          final ty = realTy.typeOf(c);
          c.setFnLLVMAttr(v, index, LLVMAttr.NoUndef);
          c.setFnTypeAttr(v, index, LLVMAttr.ByVal, ty);
        }
      }
    }

    c.setFnLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.NoInline); // Function
    return LLVMConstVariable(v, decl, decl.ident);
  }

  @override
  LLVMAllocaVariable? initFnParamsImpl(
      StoreLoadMixin context, LLVMValueRef fn, Fn fnty) {
    var index = 0;
    assert(context.isFnBBContext);

    LLVMAllocaVariable? sret;

    var retTy = fnty.fnDecl.getRetTy(context);

    if (isSret(context, fnty.fnDecl)) {
      final first = llvm.LLVMGetParam(fn, index);
      final alloca = LLVMAllocaVariable(
          first, retTy, retTy.typeOf(context), Identifier.none);
      index += 1;
      sret = alloca;
    }

    final params = fnty.fnDecl.fields;
    for (var i = 0; i < params.length; i++) {
      final p = params[i];

      final fnParam = llvm.LLVMGetParam(fn, i + index);
      var realTy = fnty.fnDecl.getFieldTy(context, p);
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
