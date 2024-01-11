import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/run.dart';
import 'package:llvm_dart/runner.dart';
import 'package:test/test.dart';

import '../bin/run.dart';

void main() {
  test('test all bin', () async {
    return runPrint(() async {
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

        print(">>> ---------------------- : ${entry.path}");

        await run(options);
      }
    });
  });
}
