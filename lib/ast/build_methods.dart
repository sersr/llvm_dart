import 'package:characters/characters.dart';
import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/memory.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';

mixin BuildMethods {
  LLVMModuleRef get module;
  LLVMContextRef get llvmContext;
  LLVMBuilderRef get builder;
  BuildMethods? get parent;

  LLVMTypeRef get typeVoid {
    return llvm.LLVMVoidTypeInContext(llvmContext);
  }

  LLVMTypeRef get i1 {
    return llvm.LLVMInt1TypeInContext(llvmContext);
  }

  LLVMTypeRef get i8 {
    return llvm.LLVMInt8TypeInContext(llvmContext);
  }

  LLVMTypeRef get i16 {
    return llvm.LLVMInt16TypeInContext(llvmContext);
  }

  LLVMTypeRef get i32 {
    return llvm.LLVMInt32TypeInContext(llvmContext);
  }

  LLVMTypeRef get i64 {
    return llvm.LLVMInt64TypeInContext(llvmContext);
  }

  LLVMTypeRef get i128 {
    return llvm.LLVMInt128TypeInContext(llvmContext);
  }

  LLVMTypeRef get f32 {
    return llvm.LLVMFloatTypeInContext(llvmContext);
  }

  LLVMTypeRef get f64 {
    return llvm.LLVMDoubleTypeInContext(llvmContext);
  }

  LLVMTypeRef arrayType(LLVMTypeRef type, int count) {
    return llvm.LLVMArrayType(type, count);
  }

  LLVMTypeRef vectorType(LLVMTypeRef type, int count) {
    return llvm.LLVMVectorType(type, count);
  }

  LLVMTypeRef typeFn(List<LLVMTypeRef> params, LLVMTypeRef ret) {
    final type =
        llvm.LLVMFunctionType(ret, params.toNative(), params.length, LLVMFalse);
    return type;
  }

  LLVMTypeRef typeStruct(List<LLVMTypeRef> types, Identifier? ident) {
    if (ident == null) {
      return llvm.LLVMStructTypeInContext(
          llvmContext, types.toNative(), types.length, LLVMFalse);
    }
    final struct =
        llvm.LLVMStructCreateNamed(llvmContext, 'struct_$ident'.toChar());
    llvm.LLVMStructSetBody(struct, types.toNative(), types.length, LLVMFalse);

    return struct;
  }

  LLVMTypeRef pointer() {
    return llvm.LLVMPointerTypeInContext(llvmContext, 0);
  }

  LLVMTypeRef typePointer(LLVMTypeRef type) {
    return llvm.LLVMPointerType(type, 0);
  }

  int pointerSize() {
    final td = llvm.LLVMGetModuleDataLayout(module);
    return llvm.LLVMPointerSize(td);
  }

  int typeSize(LLVMTypeRef type) {
    final td = llvm.LLVMGetModuleDataLayout(module);
    return llvm.LLVMABISizeOfType(td, type);
  }

  LLVMTypeRef getStructExternType(int count) {
    LLVMTypeRef loadTy;
    var size = pointerSize();
    if (count > size) {
      final d = count / size;
      count = d.ceil();
      loadTy = arrayType(i64, count);
    } else {
      if (size > 4) {
        loadTy = i64;
      } else {
        loadTy = i32;
      }
    }
    return loadTy;
  }

  bool isFnBBContext = false;
  LLVMValueRef? _allocaInst;
  BuildMethods? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  LLVMValueRef get fnValue;

  LLVMBuilderRef? get allocaBuilder {
    final fnContext = getLastFnContext();
    if (fnContext != null) {
      final alloca = fnContext._allocaInst;
      final b = llvm.LLVMCreateBuilderInContext(llvmContext);
      final fnEntry = llvm.LLVMGetFirstBasicBlock(fnValue);
      if (alloca != null) {
        // 在 entry 中分配
        final next = llvm.LLVMGetNextInstruction(alloca);
        llvm.LLVMPositionBuilder(b, fnEntry, next);
      } else {
        final first = llvm.LLVMGetFirstInstruction(fnEntry);
        llvm.LLVMPositionBuilder(b, fnEntry, first);
      }
      return b;
    }
    return null;
  }

  void setLastAlloca(LLVMValueRef val) {
    final fnContext = getLastFnContext();
    if (fnContext != null) {
      fnContext._allocaInst = val;
    }
  }

  LLVMValueRef alloctor(LLVMTypeRef type, String name) {
    final nb = allocaBuilder;
    final alloca = llvm.LLVMBuildAlloca(nb ?? builder, type, name.toChar());
    setLastAlloca(alloca);
    if (nb != null) {
      llvm.LLVMDisposeBuilder(nb);
    }
    return alloca;
  }

  void setName(LLVMValueRef ref, String name) {
    llvm.LLVMSetValueName(ref, name.toChar());
  }
}

mixin Consts on BuildMethods {
  LLVMValueRef constI1(int v) {
    return llvm.LLVMConstInt(i1, v, LLVMFalse);
  }

  LLVMValueRef constI8(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i8, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI16(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i16, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI32(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i32, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI64(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i64, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI128(String v, [bool signed = false]) {
    return llvm.LLVMConstIntOfString(
        i128, v.toChar(), signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constF32(double v) {
    return llvm.LLVMConstReal(f32, v);
  }

  LLVMValueRef constF64(double v) {
    return llvm.LLVMConstReal(f64, v);
  }

  LLVMValueRef constStr(String str) {
    final buf = StringBuffer();
    var lastChar = '';
    final isSingle = str.characters.first == "'";
    final src = str.substring(1, str.length - 1);
    for (var char in src.characters) {
      // 两个反义符号
      if (lastChar == '\\') {
        if (isSingle && char == '"') {
          buf.write('\\"');
        } else if (!isSingle && char == "'") {
          buf.write("\\'");
        } else if (char == 'n') {
          buf.write('\n');
        } else {
          // \
          buf.write('\\');
        }
        lastChar = '';
        continue;
      }
      lastChar = char;
      if (lastChar != '\\') buf.write(char);
    }
    final regStr = buf.toString();
    return llvm.LLVMConstStringInContext(
        llvmContext, regStr.toChar(), regStr.length, LLVMFalse);
  }

  LLVMValueRef constArray(LLVMTypeRef ty, int size) {
    final alloca =
        llvm.LLVMBuildArrayAlloca(builder, ty, constI64(size, false), unname);
    return alloca;
  }
}

mixin Cast on BuildMethods {
  LLVMValueRef castLit(LitKind src, LLVMValueRef value, LitKind dest) {
    final ty = BuiltInTy.from(dest.lit)!;
    final llty = ty.llvmType.litType(this);
    if (src.isInt != dest.isInt) {
      final op = getCastOp(src, dest)!;
      return llvm.LLVMBuildCast(builder, op, value, llty, unname);
    }
    if (dest.isInt) {
      return llvm.LLVMBuildIntCast2(
          builder, value, llty, dest.signed ? LLVMTrue : LLVMFalse, unname);
    }

    return llvm.LLVMBuildFPCast(builder, value, llty, unname);
  }

  static int? getCastOp(LitKind src, LitKind dest) {
    if (src.isInt && dest.isFp) {
      if (src.signed) {
        return LLVMOpcode.LLVMSIToFP;
      } else {
        return LLVMOpcode.LLVMUIToFP;
      }
    } else if (src.isFp && dest.isInt) {
      if (dest.signed) {
        return LLVMOpcode.LLVMFPToSI;
      }
      return LLVMOpcode.LLVMFPToUI;
    }
    return null;
  }
}
