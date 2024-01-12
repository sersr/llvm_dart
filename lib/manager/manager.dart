import '../abi/abi_fn.dart';
import '../ast/llvm/llvm_context.dart';
import 'manager_base.dart';

class ProjectManager extends ManagerBase
    with AnalysisContextMixin, BuildContextMixin {
  ProjectManager(
      {this.stdRoot = '',
      String? triple,
      String name = 'root',
      Abi abi = Abi.arm64,
      this.isDebug = false})
      : rootBuildContext =
            RootBuildContext(triple: triple, name: name, abi: abi);

  @override
  final String stdRoot;
  @override
  final bool isDebug;

  @override
  final RootBuildContext rootBuildContext;

  bool genFn(String path, {bool logAst = false}) {
    analysis(path);
    if (logAst) printAst();
    build(path);
    return getFn('main')?.genFn() != null;
  }
}
