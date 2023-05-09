import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('file', () async {
    final name = 'array.kc';
    // final name = 'impl_fn.kc';
    final project = Project(testSrcDir.childFile(name).path);
    // project.mem2reg = true;
    // project.printAsm = true;
    project.enableBuild = true;
    runPrint(project.run);
    await runNativeCode(args: 'hello world');
  });
}
