import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/fs/project.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('file', () async {
    final project = Project(testSrcDir.childFile('main.kc').path);
    runPrint(project.run);
    await runNativeCode();
  });
}
