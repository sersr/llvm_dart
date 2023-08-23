import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  Future<void> run(String name, {bool run = false}) {
    return runPrint(() {
      // final name = 'impl_fn.kc';
      final project = Project(testSrcDir.childFile(name).path, isDebug: true);
      // project.mem2reg = true;
      // project.printAsm = true;
      // project.enableBuild = true;
      project.analysis();
      project.printAst();
      project.printLifeCycle((v) {
        // Log.w(v.lifeCycyle?.light, showTag: false);
      });
      project.build();
      return runNativeCode(run: run, args: 'hello world');
    });
  }

  test('file', () => run('com_ty.kc'));

  test('final', () => run('final.kc', run: true));

  test('delay.kc', () => run('delay.kc'));

  test('c_array.kc', () => run('c_array.kc'));

  test('debug', () => run('debug.kc', run: false));
}
