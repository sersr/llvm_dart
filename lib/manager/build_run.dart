import 'dart:ffi';

import '../ast/llvm/llvm_context.dart';
import '../fs/fs.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';

void buildRun(BuildContextImpl root,
    {String name = 'out', bool optimize = false}) {
  if (optimize) {
    llvm.optimize(
      root.module,
      root.tm,
      LLVMRustPassBuilderOptLevel.O3,
      LLVMRustOptStage.PreLinkThinLTO,
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

  llvm.LLVMPrintModuleToFile(root.module, buildFileChar('$name.ll'), nullptr);
  // llvm.writeOutput(root.module, root.tm, LLVMCodeGenFileType.LLVMAssemblyFile,
  //     buildFileChar('$name.S'));
  llvm.writeOutput(root.module, root.tm, LLVMCodeGenFileType.LLVMObjectFile,
      buildFileChar('$name.o'));

  root.dispose();
}
