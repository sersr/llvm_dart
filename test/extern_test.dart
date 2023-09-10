import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/manager/build_run.dart';
import 'package:llvm_dart/manager/manager.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('test extern fn', () => run('arch_fn.kc'));

  test('c fn', () => run('c_fn.kc'));
}

Future<void> run(String name,
    {String files = '../test/src/arch.c', bool run = false}) {
  return runPrint(() async {
    final path = testSrcDir.childFile(name).path;
    final project = ProjectManager();
    final arch = 'x86_64';
    project.isDebug = true;
    final root = project.build(path,
        target: '$arch-apple-darwin22.4.0',
        afterAnalysis: () => project.printAst());
    buildRun(root);

    llvmMalloc.releaseAll();
    return runNativeCode(
        run: run, pre: '-arch $arch $files', args: 'hello world');
  });
}
