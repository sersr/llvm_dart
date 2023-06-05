import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  Future<void> run(String name) {
    return runPrint(() {
      // final name = 'impl_fn.kc';
      final project = Project(testSrcDir.childFile(name).path);
      // project.mem2reg = true;
      // project.printAsm = true;
      // project.enableBuild = true;
      project.analysis();
      project.printAst();
      project.printLifeCycle((v) {
        // Log.w(v.lifeCycyle?.light, showTag: false);
      });
      project.build();
      return runNativeCode(run: false, args: 'hello world');
    });
  }

  test('file', () => run('com_ty.kc'));

  test('final', () => run('final.kc'));

  test('delay.kc', () => run('delay.kc'));
}
