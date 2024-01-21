import 'package:args/args.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/runner.dart';
import 'package:nop/nop.dart';

Directory get kcBinDir => currentDir.childDirectory('kc').childDirectory('bin');
Directory get stdRoot => currentDir.childDirectory('kc').childDirectory('lib');
void main(List<String> args) async {
  assert(() {
    final argsFile = currentDir.childFile('.debug_args');
    if (argsFile.existsSync()) {
      final debugArgs = argsFile.readAsStringSync();
      args = debugArgs.split(' ');
    } else {
      args = ['c_array'];
    }
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
  argParser.addFlag('Optimize', abbr: 'O', defaultsTo: false, help: 'optimize');

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
  final optimize = results['Optimize'] as bool;

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
    opt: optimize,
  );

  await run(options);
}
