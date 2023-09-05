import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/manager/build_run.dart';
import 'package:llvm_dart/manager/manager.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('test extern fn', () => run('arch_fn.kc', files: '../test/src/arch.c'));
}

Future<void> run(String name, {String files = '', bool run = false}) {
  return runPrint(() {
    final path = testSrcDir.childFile(name).path;
    final project = ProjectManager();
    project.isDebug = true;
    final root = project.build(path, afterAnalysis: () => project.printAst());
    buildRun(root);

    llvmMalloc.releaseAll();
    return runNativeCode(run: run, files: files, args: 'hello world');
  });
}
