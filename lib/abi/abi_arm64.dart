import 'dart:ffi';

import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/memory.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'abi_fn.dart';

class AbiFnArm64 implements AbiFn {
  @override
  bool isSret(BuildContext c, Fn fn) {
    var retTy = fn.getRetTy(c);
    if (retTy is StructTy) {
      final size = retTy.llvmType.getBytes(c);
      if (size > 16) return true;
    }
    return false;
  }

  @override
  ExprTempValue? fnCall(
    BuildContext context,
    Fn fn,
    List<FieldExpr> params,
    Identifier currentIdent,
  ) {
    final fnAlloca = fn.build(const {}, const {});
    final fnValue = fnAlloca?.getBaseValue(context);
    if (fnValue == null) return null;

    final fnParams = fn.fnSign.fnDecl.params;
    final args = <LLVMValueRef>[];
    final retTy = fn.getRetTy(context);

    StoreVariable? sret;
    if (isSret(context, fn)) {
      sret = retTy.llvmType
          .createAlloca(context, Identifier.builtIn('sret'), null);

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
      final temp = LiteralExpr.run(() => p.build(context), c);
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
          value = v.load(context, temp!.currentIdent.offset);
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
      args.add(v.load(context, variable.ident.offset));
    }

    final fnType = createFnType(context, fn);

    context.diSetCurrentLoc(currentIdent.offset);
    final ret = llvm.LLVMBuildCall2(
        context.builder, fnType, fnValue, args.toNative(), args.length, unname);

    for (var index in listNoundefs) {
      final attr = llvm.LLVMCreateEnumAttribute(
          context.llvmContext, LLVMAttr.NoUndef, 0);
      llvm.LLVMAddCallSiteAttribute(ret, index, attr);
    }

    if (sret != null) {
      return ExprTempValue(sret, retTy, currentIdent);
    }
    if (retTy == BuiltInTy.kVoid) {
      return null;
    }

    Variable v;
    if (retTy is StructTy) {
      v = fromFnParamsOrRet(context, retTy, ret);
    } else {
      v = LLVMConstVariable(ret, retTy);
    }

    return ExprTempValue(v, v.ty, currentIdent);
  }

  LLVMTypeRef getCStructFnParamTy(BuildContext context, StructTy ty) {
    var count = ty.llvmType.getBytes(context);
    if (count > 16) {
      return context.pointer();
    }
    final onlyFloat = ty.fields.every((e) => e.grt(context) == BuiltInTy.f32);
    final onlyDouble = ty.fields.every((e) => e.grt(context) == BuiltInTy.f64);
    if (onlyFloat) {
      final d = count / 4;
      count = d.ceil();
      return context.arrayType(context.f32, count);
    } else if (onlyDouble) {
      final d = count / 8;
      count = d.ceil();
      return context.arrayType(context.f64, count);
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
      BuildContext context, StructTy struct, Variable variable) {
    final byteSize = struct.llvmType.getBytes(context);
    if (byteSize > 16) {
      final llType = struct.llvmType.createType(context);
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

  Variable fromFnParamsOrRet(
      BuildContext context, StructTy struct, LLVMValueRef src) {
    final byteSize = struct.llvmType.getBytes(context);
    final llType = struct.llvmType.createType(context);

    if (byteSize <= 16) {
      return struct.llvmType.createAlloca(context, Identifier.none, src);
    }

    // ptr
    return LLVMAllocaVariable(struct, src, llType);
  }

  @override
  LLVMValueRef classifyFnRet(
      BuildContext context, Variable src, Offset offset) {
    final ty = src.ty;
    if (ty is! StructTy) return src.load(context, offset);
    final byteSize = ty.llvmType.getBytes(context);

    if (byteSize > 16) {
      /// error: 已经经过sret 处理了
      throw StateError('should use sret.');
    }

    final llType = getCStructFnParamTy(context, ty);
    return llvm.LLVMBuildLoad2(
        context.builder, llType, src.getBaseValue(context), unname);
  }

  late final _cacheFns = <Fn, LLVMConstVariable>{};

  LLVMTypeRef createFnType(BuildContext c, Fn fn) {
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];
    var retTy = fn.getRetTy(c);

    var retIsSret = isSret(c, fn);
    if (retIsSret) {
      list.add(c.typePointer(retTy.llvmType.createType(c)));
    }

    LLVMTypeRef cType(Ty tty) {
      LLVMTypeRef ty;
      if (tty is StructTy) {
        ty = getCStructFnParamTy(c, tty);
      } else {
        ty = tty.llvmType.createType(c);
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
    return _cacheFns.putIfAbsent(fn, () {
      final ty = createFnType(c, fn);
      var ident = fn.fnName.src;
      if (ident.isEmpty) {
        ident = '_fn';
      }

      final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
      llvm.LLVMSetLinkage(v, LLVMLinkage.LLVMExternalLinkage);

      var retTy = fn.getRetTy(c);
      if (isSret(c, fn)) {
        c.setLLVMAttr(v, 1, LLVMAttr.StructRet);
      }

      final offset = fn.fnSign.fnDecl.ident.offset;

      final dBuilder = c.dBuilder;
      if (dBuilder != null && fn.block?.stmts.isNotEmpty == true) {
        final file = llvm.LLVMDIScopeGetFile(c.unit);
        final params = <Pointer>[];
        params.add(retTy.llvmType.createDIType(c));

        for (var p in fn.fnSign.fnDecl.params) {
          final realTy = fn.getRty(c, p);
          final ty = realTy.llvmType.createDIType(c);
          params.add(ty);
        }

        final fnTy = llvm.LLVMDIBuilderCreateSubroutineType(
            dBuilder, file, params.toNative(), params.length, 0);
        final fnScope = llvm.LLVMDIBuilderCreateFunction(
            dBuilder,
            c.unit,
            ident.toChar(),
            ident.nativeLength,
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

      c.setLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
      c.setLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
      c.setLLVMAttr(v, -1, LLVMAttr.NoInline); // Function
      final fnVaraible = LLVMConstVariable(v, fn);
      after(fnVaraible);
      return fnVaraible;
    });
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
      final alloca =
          LLVMAllocaVariable(retTy, first, retTy.llvmType.createType(context));
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
      final a = ty.llvmType.createAlloca(context, ident, fnParam);
      a.create(context);
      context.setName(a.alloca, ident.src);
      alloca = a;
    }
    if (alloca is StoreVariable) alloca.isTemp = false;
    context.pushVariable(ident, alloca);
  }
}

enum Reg {
  none,
  byval,
}

abstract class StructParamBase {
  void toParam(BuildContext context, StructTy ty, Variable src);

  Variable fromParam(BuildContext context, Struct ty, LLVMValueRef src);
}

// class StructParamArray implements StructParamBase {
//   StructParamArray(this.ty, this.count);
//   final LLVMValueRef ty;
//   final int count;
//   @override
//   Variable fromParam(BuildContext context, Struct ty, LLVMValueRef src) {

//   }

//   @override
//   void toParam(BuildContext context, StructTy ty, Variable src) {
//     // TODO: implement toParam
//   }
// }
