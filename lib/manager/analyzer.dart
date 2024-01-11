import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/tys.dart';
import 'manager_base.dart';

class Analyzer extends ManagerBase with AnalysisContextMixin {
  Analyzer() {
    rootAnalysis.importHandler = this;
  }

  AnalysisContext addKcFile(String path) {
    return Identifier.run(() {
      final alc = AnalysisContext.root(rootAnalysis);
      initAnalysisContext(context: alc, path: path);
      return alc;
    });
  }

  final _currentFileAllImports = <String, List<String>>{};
  final _currentImportAllLinks = <String, List<String>>{};

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

  final rootAnalysis = RootAnalysis();
  @override
  VA? getKVImpl<K, VA, T>(
      K k, Map<K, List<VA>> Function(Tys<LifeCycleVariable> c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return rootAnalysis.getKVImpl(k, map, handler: handler, test: test);
  }

  @override
  V? getVariable<V>(Identifier ident) {
    return rootAnalysis.getVariableImpl(ident) as V?;
  }

  @override
  void initChildContext(Tys<LifeCycleVariable> context, String path) {
    initAnalysisContext(context: context as AnalysisContext, path: path);
  }
}
