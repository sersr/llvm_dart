import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/runner.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

import '../bin/run.dart';

void main() {
  test('test all bin', () async {
    final files = kcBinDir.list(recursive: true, followLinks: false);
    await for (var entry in files) {
      if (entry is! File) continue;
      if (!entry.basename.endsWith('.kc')) continue;
      final options = Options(
        logFile: false,
        std: stdRoot.path,
        isVerbose: false,
        isDebug: false,
        logAst: false,
        binFile: entry,
        cFiles: const ['kc/bin/arch.c'],
      );

      Log.i(">>> ---------------------- : ${entry.path}",
          showTag: false, showPath: false);

      if (!await run(options)) {
        Log.w(">>> ---------------------- : ${entry.path} | ignore",
            showTag: false, showPath: false);
      }
    }
  });
}
