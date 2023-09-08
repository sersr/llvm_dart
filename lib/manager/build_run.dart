import 'dart:ffi';

import '../ast/llvm/llvm_context.dart';
import '../fs/fs.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';

void buildRun(BuildContext root, {bool optimize = false}) {
  if (optimize) {
    llvm.optimize(
      root.module,
      root.tm,
      LLVMRustPassBuilderOptLevel.O0,
      LLVMRustOptStage.PreLinkNoLTO,
      LLVMFalse,
      LLVMTrue,
      LLVMTrue,
      LLVMTrue,
      LLVMTrue,
      LLVMTrue,
      LLVMTrue,
      LLVMFalse,
    );
  }
  llvm.LLVMDumpModule(root.module);
  llvm.LLVMPrintModuleToFile(root.module, buildFile('out.ll'), nullptr);
  llvm.writeOutput(root.module, root.tm, LLVMCodeGenFileType.LLVMObjectFile,
      buildFile('out.o'));

  root.dispose();
}
