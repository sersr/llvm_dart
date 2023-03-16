import 'dart:io';

import 'package:file/local.dart';

void main() {
  final dir = const LocalFileSystem().currentDirectory;
  final file = dir.childDirectory('lib').childFile('llvm_core.dart');
  final reg = RegExp(r' (LLVM\w+)\(');

  final list = <String>{
    // "InitializeAllTargets",
    // "InitializeAllTargetMCs",
    // "InitializeAllAsmParsers",
    // "InitializeAllAsmPrinters",
  };
  final lines = file.readAsLinesSync();
  for (var line in lines) {
    final s = reg.firstMatch(line);
    if (s != null) {
      list.add(s[1] ?? '');
    }
  }

  final tt = dir.childFile('wrapper.def');
  tt.createSync(recursive: true);
  final os = tt.openSync(mode: FileMode.write);
  os.writeStringSync('''#include "llvm-c/Core.h"

void _initFunction() {
''');
  var isFirst = true;
  for (var l in list) {
    if (l == 'LLVMCore') continue;
    if (isFirst) {
      isFirst = false;
      os.writeStringSync('  void *x = reinterpret_cast<void *>($l);\n');
    } else {
      os.writeStringSync('  x = reinterpret_cast<void *>($l);\n');
    }
  }
  os.writeStringSync("}\n");
  os.closeSync();
}
