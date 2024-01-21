import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nop/nop.dart';

import 'fs/fs.dart';

T runPrint<T>(T Function() body) {
  Log.logPathFn = (path) => path;
  return runZoned(body,
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
  }));
}

// AnalysisContext testRun(String src,
//     {bool mem2reg = false,
//     bool build = true,
//     void Function(BuildContext context)? b}) {
//   return Identifier.run(
//     () {
//       final m = parseTopItem(src);
//       print(m.globalStmt.values.join('\n'));
//       print(m.globalTy.values.join('\n'));
//       final root = AnalysisContext.root();
//       root.pushAllTy(m.globalTy);
//       for (var fns in root.fns.values) {
//         for (var fn in fns) {
//           fn.analysis(root);
//         }
//       }
//       if (!build) return root;
//       {
//         llvm.initLLVM();
//         final root = BuildContext.root();
//         root.importHandler = (current, path) {
//           final c = current as BuildContext;
//           final child = c.import();
//           final pname = Consts.regSrc(path.name.src);

//           final p = testSrcDir.childFile(pname);
//           child.importHandler = root.importHandler;

//           if (p.existsSync()) {
//             final data = p.readAsStringSync();
//             final mImport = parseTopItem(data);
//             print(mImport.globalStmt.values.join('__\n__'));
//             print(mImport.globalTy.values.join('__\n__'));
//             child.pushAllTy(mImport.globalTy);
//             for (var val in mImport.globalStmt.values) {
//               val.build(child);
//             }
//           }
//           return child;
//         };

//         root.pushAllTy(m.globalTy);
//         root.pushFn(SizeOfFn.ident, sizeOfFn);
//         for (var val in m.globalStmt.values) {
//           val.build(root);
//         }
//         out:
//         for (var fns in root.fns.values) {
//           for (var fn in fns) {
//             if (fn.fnSign.fnDecl.ident.src == 'main') {
//               fn.currentContext = root;
//               fn.build();
//               break out;
//             }
//           }
//         }

//         llvm.LLVMDumpModule(root.module);

//         llvm.writeOutput(
//             root.kModule, LLVMCodeGenFileType.LLVMObjectFile, 'out.o'.toChar());
//         b?.call(root);
//         root.dispose();
//       }
//       return root;
//     },
//     zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
//       Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
//     }),
//   );
// }

/// 使用 [runNativeCode]
Future<void> runCode() async {
  var main = 'main';
  if (Platform.isWindows) {
    main = 'main.exe';
  }
  return runCmd(['clang -g out.ll base.c -o $main && ./build/$main']);
}

Future<void> runNativeCode(
    {String args = '', String pre = '', bool run = true}) async {
  var runn = '';
  var main = 'main';
  if (Platform.isWindows) {
    main = 'main.exe';
  }
  if (run) {
    runn = '&& ./$main $args';
  }

  return runCmd(['clang -g out.o $pre -o $main $runn']);
}

Future<void> runCmd(List<String> cmd, {Directory? dir}) async {
  dir ??= buildDir;
  final p = dir.path;

  final process =
      await Process.start('sh', ['-c', cmd.join(' ')], workingDirectory: p);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  await process.exitCode;
}

Future<String> runStr(List<String> cmd, {Directory? dir}) async {
  dir ??= buildDir;
  final p = dir.path;
  final completer = Completer<String>();

  final process = await Process.start('sh', ['-c', cmd.join(' ')],
      workingDirectory: p, runInShell: true);
  String last = '';
  process.stdout.listen((event) {
    last = utf8.decode(event);
  });

  process.exitCode.then((code) {
    if (!completer.isCompleted) {
      if (code == 0) {
        completer.complete(last.trim());
      } else {
        completer.complete('');
      }
    }
  });

  return completer.future;
}
