import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('file', () async {
    final name = 'array_to_str.kc';
    await runPrint(() {
      // final name = 'impl_fn.kc';
      final project = Project(testSrcDir.childFile(name).path);
      // project.mem2reg = true;
      // project.printAsm = true;
      project.enableBuild = true;
      project.run();
      return runNativeCode(run: false, args: 'hello world');
    });
  });
}
