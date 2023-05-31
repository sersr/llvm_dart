import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

void main() {
  test('file', () async {
    final name = 'com_ty.kc';
    await runPrint(() {
      // final name = 'impl_fn.kc';
      final project = Project(testSrcDir.childFile(name).path);
      // project.mem2reg = true;
      // project.printAsm = true;
      // project.enableBuild = true;
      project.analysis();
      project.printAst();
      project.printLifeCycle((v) {
        Log.w(v.lifeCycyle?.light, showTag: false);
      });
      project.build();
      return runNativeCode(run: false, args: 'hello world');
    });
  });
}
