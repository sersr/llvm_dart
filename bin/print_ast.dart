import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/parsers/parser.dart';
import 'package:nop/nop.dart';

Directory get kcBinDir => currentDir.childDirectory('kc').childDirectory('bin');
Directory get stdRoot => currentDir.childDirectory('kc').childDirectory('lib');
void main(List<String> args) async {
  Log.logPathFn = (path) => path;

  var name = 'c_array';
  if (args.isEmpty) {
    final argsFile = currentDir.childFile('.debug_args');
    if (argsFile.existsSync()) {
      final debugArgs =
          argsFile.readAsStringSync().replaceAll(RegExp('\r\n|\n'), ' ');
      name = debugArgs.split(' ').first;
    }
  } else {
    name = args.first;
  }

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
  final data = runFile.readAsStringSync();
  final parser = Parser(data, runFile.path);
  Log.w(parser.stmts, showTag: false);
}
