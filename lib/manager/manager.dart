import '../ast/llvm/llvm_context.dart';
import 'manager_base.dart';

class ProjectManager extends ManagerBase
    with AnalysisContextMixin, BuildContextMixin {
  ProjectManager(
      {this.stdRoot = '', String name = 'root', required Configs configs})
      : rootBuildContext = RootBuildContext(name: name, configs: configs);

  @override
  final String stdRoot;

  @override
  final RootBuildContext rootBuildContext;

  bool genFn(String path, {bool logAst = false}) {
    analysis(path);
    if (logAst) printAst();
    build(path);
    return getFn('main')?.genFn() != null;
  }
}
