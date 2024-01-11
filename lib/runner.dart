import 'dart:io';

import 'package:nop/nop.dart';

import 'abi/abi_fn.dart';
import 'fs/fs.dart';
import 'llvm_dart.dart';
import 'manager/build_run.dart';
import 'manager/manager.dart';
import 'run.dart';

class Options {
  Options({
    required this.logFile,
    required this.std,
    required this.isVerbose,
    required this.isDebug,
    required this.logAst,
    required this.binFile,
    required this.cFiles,
  });
  final bool logFile;
  final String std;
  final bool isVerbose;
  final bool isDebug;
  final bool logAst;
  final File binFile;
  final List<String> cFiles;

  String get stdFix {
    if (!std.endsWith('/')) {
      return '$std/';
    }
    return std;
  }
}

final rq = TaskQueue();

var abi = Abi.arm64;

Future<void> run(Options options) {
  return runPrint(() async {
    final path = options.binFile.path;

    var target = '$abi-apple-darwin22.4.0';
    if (Platform.isWindows) {
      abi = Abi.x86_64;
      target = "$abi-pc-windows-msvc";
    }
    llvm.initLLVM();

    final project = ProjectManager(
      stdRoot: options.stdFix,
      name: options.binFile.basename,
      abi: abi,
      triple: target,
    );

    project.isDebug = options.isDebug;

    final root = project.build(
      path,
      afterAnalysis: () {
        if (options.logAst) project.printAst();
      },
    );

    final name = options.binFile.basename.replaceFirst(RegExp('.kc\$'), '');
    buildRun(root, name: name);

    final files = options.cFiles.map((e) {
      final path = currentDir.childFile(e).path;
      if (Platform.isWindows) return path.replaceAll(r'\', '/');
      return path;
    }).join(' ');

    final verbose = options.isVerbose ? ' -v' : '';
    final debug = options.isDebug ? ' -g' : '';
    final abiV = Platform.isWindows ? '' : '-arch $abi';

    var main = 'main';
    if (Platform.isWindows) {
      main = 'main.exe';
    }

    var linkName = '$name.o';
    if (Platform.isWindows && options.isDebug) {
      linkName = '$name.ll';
    }

    await runCmd([
      'clang $debug $verbose $linkName $files $abiV -o $main -Wno-override-module && ./$main "hello world"'
    ], dir: buildDir);
    if (options.logFile) {
      Log.w(buildDir.childFile('$name.ll').path, onlyDebug: false);
      for (var ctx in project.alcs.keys) {
        Log.w(ctx, onlyDebug: false);
      }
    }
  });
}
