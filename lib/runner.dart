import 'package:nop/nop.dart';

import 'abi/abi_fn.dart';
import 'ast/context.dart';
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
    this.compileIR = false,
  });
  final bool logFile;
  final String std;
  final bool isVerbose;
  final bool isDebug;
  final bool logAst;
  final File binFile;
  final List<String> cFiles;
  final bool opt;
  final bool compileIR;
}

Future<bool> run(Options options) {
  return runPrint(() async {
    final path = options.binFile.path;
    var defaultTarget = await runStr(['clang -dumpmachine']);
    if (defaultTarget == 'clang not found') return false;
    final list = defaultTarget.trim().split('-');
    if (list.isEmpty) {
      Log.e('target error: $defaultTarget');
      return false;
    }
    final isWin = list.any((e) => e == 'windows');
    final isGnu = list.any((e) => e == 'gnu');
    final isMsvc = list.any((e) => e == 'msvc');
    var abi = Abi.from(list.first, isWin) ?? Abi.arm64;

    var target = list.join('-');

    final configs = Configs(
      abi: abi,
      isGnu: isGnu,
      isDebug: options.isDebug,
      targetTriple: target,
      isMsvc: isMsvc,
    );

    final project = ProjectManager(
      stdRoot: options.std,
      name: options.binFile.basename,
      configs: configs,
    );

    if (!project.genFn(path, logAst: options.logAst)) {
      project.dispose();
      return false;
    }

    final name = options.binFile.basename.replaceFirst(RegExp('.kc\$'), '');
    writeOut(project.rootBuildContext, name: name, optimize: options.opt);

    final args = StringBuffer();

    if (options.isVerbose) {
      args.write(' -v');
    }
    if (options.isDebug) {
      args.write(' -g');
    }

    args.write(' --target=${configs.targetTriple}');

    if (!options.compileIR) {
      args.write(' $name.o');
    } else {
      args.write(' $name.ll');
      args.write(' -Wno-override-module');
    }

    for (var file in options.cFiles) {
      var path = currentDir.childFile(file).path;
      if (configs.isWin) path = path.replaceAll(r'\', '/');
      args.write(' $path');
    }

    var main = 'main';
    if (configs.isWin) {
      args.write(' -o $main.exe');
    } else {
      args.write(' -o $main');
    }

    await runCmd(
      [
        'clang$args',
        '&&',
        './$main "hello world"',
      ],
      dir: buildDir,
    );

    if (options.logFile) {
      Log.w(buildDir.childFile('$name.ll').path, onlyDebug: false);
      for (var ctx in project.alcs.keys) {
        Log.w(ctx, onlyDebug: false);
      }
    }

    project.dispose();

    return true;
  });
}
