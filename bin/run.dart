import 'package:args/args.dart';
import 'package:llvm_dart/abi/abi_fn.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/manager/build_run.dart';
import 'package:llvm_dart/manager/manager.dart';
import 'package:llvm_dart/run.dart';
import 'package:nop/nop.dart';

Directory get kcBinDir => currentDir.childDirectory('kc').childDirectory('bin');
void main(List<String> args) async {
  assert(() {
    args = ['sret_fn'];
    return true;
  }());

  final argParser = ArgParser();
  argParser.addMultiOption('c',
      abbr: 'c', help: '-c kc/bin/arch.c', defaultsTo: ['kc/bin/arch.c']);
  argParser.addFlag('verbose', abbr: 'v', help: '-v', defaultsTo: false);

  argParser.addFlag('g', abbr: 'g', defaultsTo: false, help: 'clang -g');
  argParser.addFlag('ast', abbr: 'a', defaultsTo: false, help: 'printAst');

  final results = argParser.parse(args);
  final kcFiles = results.rest;

  final name = kcFiles.firstOrNull;

  if (name == null) {
    Log.e('dart run bin/run.dart <filename>.kc');
    return;
  }
  final cFiles = results['c'] as List<String>;
  final isVerbose = results['verbose'] as bool;
  final isDebug = results['g'] as bool;
  final printAst = results['ast'] as bool;

  File? runFile = currentDir.childFile(name);
  if (!runFile.existsSync()) {
    runFile = null;
    final entries = kcBinDir.listSync(followLinks: false);
    for (var file in entries) {
      if (file is File &&
          file.basename.contains(name) &&
          file.basename.endsWith('.kc')) {
        runFile = file;
        break;
      }
    }
  }
  if (runFile == null) {
    Log.e('找不到 <$name> 文件');
    return;
  }

  return run(runFile, cFiles, isVerbose, isDebug, printAst);
}

final rq = TaskQueue();

const abi = Abi.arm64;

Future<void> run(File file, Iterable<String> cFiles, bool isVerbose,
    bool isDebug, bool printAst) {
  return runPrint(() async {
    final project = ProjectManager();
    final path = file.path;
    project.isDebug = isDebug;
    final root = project.build(
      path,
      abi: abi,
      target: '$abi-apple-darwin22.4.0',
      afterAnalysis: () {
        if (printAst) project.printAst();
      },
    );

    final name = file.basename.replaceFirst(RegExp('.kc\$'), '');
    buildRun(root, name: name);

    final files = cFiles.map((e) => currentDir.childFile(e).path).join(' ');
    final verbose = isVerbose ? ' -v ' : ' ';
    final debug = isDebug ? ' -g ' : ' ';
    await runCmd([
      'clang $debug$verbose $name.o $files -arch $abi -o main && ./main hello world'
    ], dir: buildDir);

    Log.w(buildDir.childFile('$name.ll').path, onlyDebug: false);
    for (var ctx in project.alcs.keys) {
      Log.w(ctx, onlyDebug: false);
    }
  });
}
