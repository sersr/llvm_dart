import 'dart:ffi';

import '../fs/fs.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../ast/llvm/llvm_context.dart';

void buildRun(BuildContext root) {
  // llvm.optimize(
  //   root.kModule,
  //   LLVMRustPassBuilderOptLevel.O0,
  //   LLVMRustOptStage.PreLinkNoLTO,
  //   LLVMFalse,
  //   LLVMTrue,
  //   LLVMTrue,
  //   LLVMTrue,
  //   LLVMTrue,
  //   LLVMTrue,
  //   LLVMTrue,
  //   LLVMFalse,
  // );
  llvm.LLVMDumpModule(root.module);
  llvm.LLVMPrintModuleToFile(root.module, buildFile('out.ll'), nullptr);
  llvm.writeOutput(
      root.kModule, LLVMCodeGenFileType.LLVMObjectFile, buildFile('out.o'));

  root.dispose();
}
