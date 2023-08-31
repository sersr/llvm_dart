import 'package:llvm_dart/manager/build_run.dart';
import 'package:llvm_dart/manager/manager.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/run.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

void main() {
  final rq = TaskQueue();

  Future<void> run(String name, {bool run = false}) {
    return rq.run(() => runPrint(() {
          // final name = 'impl_fn.kc';
          final path = testSrcDir.childFile(name).path;
          final project = ProjectManager();
          final root = project.build(path);
          project.printAst();
          buildRun(root);
          // final project = Project(path, isDebug: false);
          // project.printAsm = true;
          // project.enableBuild = true;
          // project.analysis();
          // project.printAst();
          // project.build();
          // project.printLifeCycle((v) {
          // Log.w(v.lifeCycyle?.light, showTag: false);
          // });
          return runNativeCode(run: run, args: 'hello world');
        }));
  }

  test('com_ty', () => run('com_ty.kc'));

  test('final', () => run('final.kc'));

  test('delay.kc', () => run('delay.kc'));

  test('c_array.kc', () => run('c_array.kc'));

  test('array', () => run('array.kc'));

  test('array_to_str', () => run('array_to_str.kc'));

  test('debug', () => run('debug.kc', run: false));

  test('type alias', () => run('type_alias.kc'));

  test('vec', () => run('vec_main.kc'));
}
