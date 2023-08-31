import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/tys.dart';
import 'manager_base.dart';

class Analyzer with ManagerBase {
  AnalysisContext addKcFile(String path) {
    return Identifier.run(() {
      final alc = AnalysisContext.root();
      _baseProcess(
        context: alc,
        path: path,
        action: (builder) {
          builder.analysis(alc);
        },
      );
      return alc;
    });
  }

  final _currentFileAllImports = <String, List<String>>{};
  final _currentImportAllLinks = <String, List<String>>{};

  void _baseProcess(
      {required Tys context,
      required String path,
      required void Function(BuildMixin builder) action,
      bool isRoot = true}) {
    Tys linkImportBuild(Tys current, ImportPath childPath) {
      final child = importBuild(current, childPath);
      final allImports = _currentFileAllImports.putIfAbsent(path, () => []);
      final cPath = child.currentPath!;
      if (cPath == path) return child;

      if (!allImports.contains(cPath)) {
        allImports.add(cPath);
        final currentImport =
            _currentImportAllLinks.putIfAbsent(cPath, () => []);
        assert(!currentImport.contains(path));
        currentImport.add(path);
      }
      return child;
    }

    baseProcess(
      context: context,
      path: path,
      action: action,
      isRoot: isRoot,
      importHandler: linkImportBuild,
    );
  }

  void removeKcFile(String path) {
    final currentFiles = _currentFileAllImports[path];
    if (currentFiles == null || currentFiles.isEmpty) return;
    final allImports = List.of(currentFiles); // copy
    allImports.add(path);
    for (var import in allImports) {
      if (_currentFileAllImports.containsKey(import)) continue;
      final list = _currentImportAllLinks.remove(import);
      if (list != null) {
        list.remove(path);
        currentFiles.remove(import);
      }
    }
  }
}
