import 'dart:io';

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

abstract class Cmd {
  String get command;

  String get defaultTarget => _defaultTarget ?? '';
  bool get isActive => _defaultTarget != null;

  String? _defaultTarget;

  Configs getConfigs(bool isDebug);

  Future<void> obtainClang() async {
    if (isActive) return;
    final target = await runStr(['$command -dumpmachine']);
    if (target.isNotEmpty) {
      _defaultTarget = target;
    }
  }
}

class ClangCmd extends Cmd {
  @override
  String get command => 'clang';

  @override
  Configs getConfigs(bool isDebug) {
    assert(isActive);

    final list = defaultTarget.split('-');

    final isWin = list.any((e) => e == 'windows');
    final isGnu = list.any((e) => e == 'gnu');
    final isMsvc = list.any((e) => e == 'msvc');
    var abi = Abi.from(list.first, isWin) ?? Abi.arm64;

    final targetTriple = list.join('-');
    return Configs(
      isGnu: isGnu,
      isMsvc: isMsvc,
      abi: abi,
      targetTriple: targetTriple,
      isDebug: isDebug,
    );
  }
}

Future<bool> run(Options options) {
  return runPrint(() async {
    final path = options.binFile.path;
    final cmd = ClangCmd();
    await cmd.obtainClang();

    if (!cmd.isActive) {
      Log.e('clang not found');
      return false;
    }

    final configs = cmd.getConfigs(options.isDebug);

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
      if (Platform.isWindows) path = path.replaceAll(r'\', '/');
      args.write(' $path');
    }

    var main = 'main';
    if (Platform.isWindows) {
      args.write(' -o $main.exe');
    } else {
      args.write(' -o $main');
    }

    await runCmd(
      [
        '${cmd.command}$args',
        '&&',
        './$main "hello world"',
      ],
      dir: buildDir,
    );

    if (options.logFile) {
      Log.w(buildDir.childFile('$name.ll').path, onlyDebug: false);
      // for (var ctx in project.alcs.keys) {
      //   Log.w(ctx, onlyDebug: false);
      // }
    }

    project.dispose();

    return true;
  });
}
