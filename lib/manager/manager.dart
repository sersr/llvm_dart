import '../fs/fs.dart';
import '../llvm_dart.dart';
import '../parsers/parser.dart';
import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/llvm/llvm_context.dart';
import 'manager_base.dart';

class ProjectManager with ManagerBase {
  ProjectManager();

  bool isDebug = false;

  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      return parseTopItem(data);
    }
    return null;
  }

  AnalysisContext analysis(String path) {
    return Identifier.run(() {
      final alc = AnalysisContext.root();
      alcs[path] = alc;
      baseProcess(
        context: alc,
        path: path,
        action: (builder) => builder.analysis(alc),
      );
      return alc;
    });
  }

  BuildContext build(String path) {
    return Identifier.run(() {
      llvm.initLLVM();
      final fileName = currentDir.childFile(path).basename;
      final root = BuildContext.root(fileName);
      llvmCtxs[path] = root;
      final parser = parserToken(path);
      final alc = AnalysisContext.root();
      alcs[path] = alc;

      void actionAlc(BuildMixin builder) => builder.analysis(alc);
      void action(BuildMixin builder) => builder.build(root);

      baseProcess(
        context: alc,
        path: path,
        parser: parser,
        action: actionAlc,
      );

      root.init(isDebug);

      baseProcess(
        context: root,
        path: path,
        parser: parser,
        action: action,
      );

      root.finalize();

      return root;
    });
  }
}
