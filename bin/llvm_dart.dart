import 'dart:ffi';

import 'package:llvm_dart/llvm_core.dart';
import 'package:llvm_dart/llvm_dart.dart';
import 'package:ffi/ffi.dart';

void main(List<String> arguments) {
  final llvm = LLVMInstance.getInstance();
  llvm.initLLVM();
  final k = llvm.createKModule("hello".toNativeUtf8().cast());

  // llvm.kModuleInit(k);
  final context = llvm.getLLVMContext(k);
  final module = llvm.getModule(k);

  final builder = llvm.LLVMCreateBuilderInContext(context);
  final returnType = llvm.LLVMVoidTypeInContext(context);

  final i8 = llvm.LLVMInt8TypeInContext(context);

  final p = malloc<Pointer<LLVMOpaqueType>>(2);
  p[0] = i8;
  p[1] = i8;
  final type = llvm.LLVMFunctionType(returnType, p, 2, 0);
  malloc.free(p);

  final function =
      llvm.getOrInsertFunction("main".toNativeUtf8().cast(), module, type);
  final bb = llvm.LLVMAppendBasicBlockInContext(
      context, function, "entry".toNativeUtf8().cast());
  llvm.LLVMPositionBuilderAtEnd(builder, bb);
  final intType = llvm.LLVMInt64TypeInContext(context);

  final ret = llvm.LLVMConstInt(intType, 0, 0);
  llvm.LLVMBuildRet(builder, ret);
  llvm.writeOutput(k);
  malloc.free(module);
  malloc.free(context);
}
