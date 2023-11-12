import 'dart:ffi';

import '../ast/llvm/llvm_context.dart';
import '../fs/fs.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';

void buildRun(BuildContext root, {String name = 'out', bool optimize = false}) {
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

  llvm.LLVMPrintModuleToFile(root.module, buildFileChar('$name.ll'), nullptr);
  // llvm.LLVMTargetMachineEmitToFile(root.tm, root.module, '$name.o'.toChar(),
  //     LLVMCodeGenFileType.LLVMObjectFile, nullptr);
  llvm.writeOutput(root.module, root.tm, LLVMCodeGenFileType.LLVMObjectFile,
      buildFileChar('$name.o'));

  root.dispose();
}
