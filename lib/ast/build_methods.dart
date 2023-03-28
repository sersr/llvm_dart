import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/memory.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';

mixin BuildMethods {
  LLVMModuleRef get module;
  LLVMContextRef get llvmContext;
  LLVMBuilderRef get builder;
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
    final type = llvm.LLVMFunctionType(
        ret, params.toNative().cast(), params.length, LLVMFalse);
    return type;
  }

  LLVMTypeRef typeStruct(List<LLVMTypeRef> types, Identifier ident) {
    final struct =
        llvm.LLVMStructCreateNamed(llvmContext, 'struct_$ident'.toChar());
    llvm.LLVMStructSetBody(
        struct, types.toNative().cast(), types.length, LLVMFalse);

    return struct;
  }

  LLVMTypeRef pointer() {
    return llvm.LLVMPointerTypeInContext(llvmContext, 0);
  }
}

mixin Consts on BuildMethods {
  LLVMValueRef constI1(int v) {
    return llvm.LLVMConstInt(i1, v, LLVMFalse);
  }

  LLVMValueRef constI8(int v) {
    return llvm.LLVMConstInt(i8, v, LLVMFalse);
  }

  LLVMValueRef constU8(int v) {
    return llvm.LLVMConstInt(i8, v, LLVMTrue);
  }

  LLVMValueRef constI16(int v) {
    return llvm.LLVMConstInt(i16, v, LLVMFalse);
  }

  LLVMValueRef constU16(int v) {
    return llvm.LLVMConstInt(i16, v, LLVMTrue);
  }

  LLVMValueRef constI32(int v) {
    return llvm.LLVMConstInt(i32, v, LLVMFalse);
  }

  LLVMValueRef constU32(int v) {
    return llvm.LLVMConstInt(i32, v, LLVMTrue);
  }

  LLVMValueRef constI64(int v) {
    return llvm.LLVMConstInt(i64, v, LLVMFalse);
  }

  LLVMValueRef constU64(int v) {
    return llvm.LLVMConstInt(i64, v, LLVMTrue);
  }

  LLVMValueRef constI128(int v) {
    return llvm.LLVMConstInt(i128, v, LLVMFalse);
  }

  LLVMValueRef constU128(int v) {
    return llvm.LLVMConstInt(i128, v, LLVMTrue);
  }

  LLVMValueRef constF32(double v) {
    return llvm.LLVMConstReal(f32, v);
  }

  LLVMValueRef constF64(double v) {
    return llvm.LLVMConstReal(f64, v);
  }

  LLVMValueRef constStr(String str) {
    return llvm.LLVMConstStringInContext(
        llvmContext, str.toChar(), str.length, LLVMFalse);
  }
}
