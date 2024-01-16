import 'dart:io';

import 'package:nop/nop.dart';

import 'abi/abi_fn.dart';
import 'fs/fs.dart';
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
    this.opt = false,
  });
  final bool logFile;
  final String std;
  final bool isVerbose;
  final bool isDebug;
  final bool logAst;
  final File binFile;
  final List<String> cFiles;
  final bool opt;
}

Future<bool> run(Options options) {
  return runPrint(() async {
    var abi = Abi.arm64;
    final path = options.binFile.path;

    var target = '$abi-apple-darwin22.4.0';
    if (Platform.isWindows) {
      abi = Abi.winx86_64;
      target = "$abi-pc-windows-msvc";
    }

    final project = ProjectManager(
      stdRoot: options.std,
      name: options.binFile.basename,
      abi: abi,
      triple: target,
      isDebug: options.isDebug,
    );

    final genMain = project.genFn(path, logAst: options.logAst);
    if (genMain) {
      final name = options.binFile.basename.replaceFirst(RegExp('.kc\$'), '');
      writeOut(project.rootBuildContext, name: name, optimize: options.opt);

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
        'clang $debug $verbose $linkName $files $abiV -o $main --target=$target -Wno-override-module && ./$main "hello world"'
      ], dir: buildDir);
      if (options.logFile) {
        Log.w(buildDir.childFile('$name.ll').path, onlyDebug: false);
        for (var ctx in project.alcs.keys) {
          Log.w(ctx, onlyDebug: false);
        }
      }
    }

    project.dispose();

    return genMain;
  });
}
