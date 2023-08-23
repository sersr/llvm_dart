import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/llvm_dart.dart';
import 'package:llvm_dart/run.dart';

void main() async {
  llvm.initLLVM();
  final context = llvm.LLVMContextCreate();

  llvm.LLVMIRReader(context, buildFile('out.ll'), buildFile('outnn.o'));

  await runCmd(['clang -g outnn.o -o outn2']);
}
