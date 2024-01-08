import 'dart:io';

import 'package:args/args.dart';
import 'package:llvm_dart/abi/abi_fn.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/manager/build_run.dart';
import 'package:llvm_dart/manager/manager.dart';
import 'package:llvm_dart/run.dart';
import 'package:nop/nop.dart';

Directory get kcBinDir => currentDir.childDirectory('kc').childDirectory('bin');
Directory get stdRoot => currentDir.childDirectory('kc').childDirectory('lib');
void main(List<String> args) async {
  assert(() {
    args = ['test/string.kc'];
    return true;
  }());
  buildDir.create();

  final argParser = ArgParser();
  argParser.addMultiOption('c',
      abbr: 'c', help: '-c kc/bin/arch.c', defaultsTo: ['kc/bin/arch.c']);
  argParser.addFlag('verbose', abbr: 'v', help: '-v', defaultsTo: false);

  argParser.addFlag('g', abbr: 'g', defaultsTo: false, help: 'clang -g');
  argParser.addFlag('logast', abbr: 'a', defaultsTo: false, help: 'log ast');
  argParser.addOption('std', defaultsTo: stdRoot.path, help: '--std ./bin/lib');
  argParser.addFlag('logfile', abbr: 'f', defaultsTo: false, help: 'log files');

  final results = argParser.parse(args);
  final kcFiles = results.rest;

  final name = kcFiles.firstOrNull;

  if (name == null) {
    Log.e('dart run bin/run.dart <filename>.kc', onlyDebug: false);
    print(argParser.usage);
    return;
  }
  final cFiles = results['c'] as List<String>;
  final isVerbose = results['verbose'] as bool;
  final isDebug = results['g'] as bool;
  final logAst = results['logast'] as bool;
  final stdDir = results['std'] as String;
  final logFile = results['logfile'] as bool;

  File? runFile = kcBinDir.childFile(name);
  if (!runFile.existsSync()) {
    var dir = runFile.parent;
    if (!dir.existsSync()) {
      dir = kcBinDir;
    }

    runFile = null;
    final basename = name.split('/').last;

    final entries = dir.listSync(followLinks: false);
    for (var file in entries) {
      if (file is File &&
          file.basename.startsWith(basename) &&
          file.basename.endsWith('.kc')) {
        runFile = file;
        break;
      }
    }
  }
  if (runFile == null) {
    Log.e('找不到 <$name> 文件', onlyDebug: false);
    return;
  }

  final options = Options(
    logFile: logFile,
    std: stdDir,
    isVerbose: isVerbose,
    isDebug: isDebug,
    logAst: logAst,
    binFile: runFile,
    cFiles: cFiles,
  );

  return run(options);
}

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
    final project = ProjectManager(stdRoot: options.stdFix);
    final path = options.binFile.path;
    project.isDebug = options.isDebug;

    var target = '$abi-apple-darwin22.4.0';
    if (Platform.isWindows) {
      abi = Abi.x86_64;
      target = "$abi-pc-windows-msvc";
    }

    final root = project.build(
      path,
      abi: abi,
      target: target,
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
