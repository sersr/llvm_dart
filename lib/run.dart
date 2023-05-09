import 'dart:async';
import 'dart:io';

import 'ast/analysis_context.dart';
import 'ast/ast.dart';
import 'ast/buildin.dart';
import 'ast/llvm/build_methods.dart';
import 'ast/llvm/llvm_context.dart';
import 'ast/memory.dart';
import 'fs/fs.dart';
import 'llvm_core.dart';
import 'llvm_dart.dart';
import 'parsers/parser.dart';

T runPrint<T>(T Function() body) {
  return runZoned(body,
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
  }));
}

AnalysisContext testRun(String src,
    {bool mem2reg = false,
    bool build = true,
    void Function(BuildContext context)? b}) {
  return Identifier.run(
    () {
      final m = parseTopItem(src);
      print(m.globalVar.values.join('\n'));
      print(m.globalTy.values.join('\n'));
      final root = AnalysisContext.root();
      root.pushAllTy(m.globalTy);
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          fn.analysis(root);
        }
      }
      if (!build) return root;
      {
        llvm.initLLVM();
        final root = BuildContext.root();
        root.importHandler = (current, path) {
          final c = current as BuildContext;
          final child = c.import();
          final pname = Consts.regSrc(path.name.src);

          final p = testSrcDir.childFile(pname);
          child.importHandler = root.importHandler;

          if (p.existsSync()) {
            final data = p.readAsStringSync();
            final mImport = parseTopItem(data);
            print(mImport.globalVar.values.join('__\n__'));
            print(mImport.globalTy.values.join('__\n__'));
            child.pushAllTy(mImport.globalTy);
            for (var val in mImport.globalVar.values) {
              val.build(child);
            }
          }
          return child;
        };
        BuildContext.mem2reg = mem2reg;
        root.pushAllTy(m.globalTy);
        root.pushFn(SizeOfFn.ident, sizeOfFn);
        for (var val in m.globalVar.values) {
          val.build(root);
        }
        out:
        for (var fns in root.fns.values) {
          for (var fn in fns) {
            if (fn.fnSign.fnDecl.ident.src == 'main') {
              fn.build(root);
              break out;
            }
          }
        }

        llvm.LLVMDumpModule(root.module);
        llvm.writeOutput(
            root.kModule, LLVMCodeGenFileType.LLVMObjectFile, 'out.o'.toChar());
        b?.call(root);
        root.dispose();
      }
      return root;
    },
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
    }),
  );
}

Future<void> runCode() async {
  final p = currentDir.path;

  final process = await Process.start(
      'sh', ['-c', 'cc $p/out.o  $p/base.c -o main && ./main'],
      workingDirectory: p);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  await process.exitCode;
}

Future<void> runNativeCode({String args = ''}) async {
  final p = currentDir.path;

  final process = await Process.start(
      'sh', ['-c', 'cc $p/out.o -o main && ./main $args'],
      workingDirectory: p);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  await process.exitCode;
}
