import '../abi/abi_fn.dart';
import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/buildin.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/tys.dart';
import 'manager_base.dart';

class ProjectManager extends ManagerBase {
  ProjectManager(
      {this.stdRoot = '',
      String? triple,
      String name = 'root',
      Abi abi = Abi.arm64})
      : rootBuildContext =
            RootBuildContext(targetTriple: triple, name: name, abi: abi) {
    rootBuildContext.importHandler = this;
    rootAnalysisContext.importHandler = this;
  }

  @override
  final String stdRoot;
  bool isDebug = false;

  AnalysisContext analysis(String path) {
    return Identifier.run(() {
      final alc = AnalysisContext.root(rootAnalysisContext);
      alcs[path] = alc;
      baseProcess(
        context: alc,
        path: path,
        action: (builder) => builder.analysis(alc),
      );
      return alc;
    });
  }

  final RootBuildContext rootBuildContext;
  final rootAnalysisContext = RootAnalysis();

  BuildContextImpl build(String path, {void Function()? afterAnalysis}) {
    return Identifier.run(() {
      final root = BuildContextImpl.root(rootBuildContext);
      llvmCtxs[path] = root;
      final parser = getParser(path);
      final alc = AnalysisContext.root(rootAnalysisContext);
      alcs[path] = alc;

      /// set path
      alc.currentPath = path;
      root.currentPath = path;

      initBuiltinFns(rootAnalysisContext);
      initBuiltinFns(rootBuildContext);

      void actionAlc(BuildMixin builder) => builder.analysis(alc);
      void action(BuildMixin builder) {
        if (builder is Ty) {
          builder.currentContext = root;
          builder.build();
        } else if (builder is Stmt) {
          builder.build(root);
        }
      }

      baseProcess(context: alc, path: path, parser: parser, action: actionAlc);
      afterAnalysis?.call();
      if (isDebug) root.debugInit();

      baseProcess(context: root, path: path, parser: parser, action: action);

      Fn? mainFn;
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          if (fn.fnName.src == 'main') {
            mainFn = fn;
            break;
          }
        }
        if (mainFn != null) break;
      }

      if (mainFn != null) {
        mainFn.build();
      }

      // root.finalize();

      return root;
    });
  }

  @override
  VA? getKVImpl<K, VA, T>(
      K k, Map<K, List<VA>> Function(Tys<LifeCycleVariable> c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return switch (T) {
      Variable =>
        rootBuildContext.getKVImpl(k, map, handler: handler, test: test),
      AnalysisVariable =>
        rootAnalysisContext.getKVImpl(k, map, handler: handler, test: test),
      _ => null,
    };
  }

  @override
  V? getVariable<V>(Identifier ident) {
    return switch (V) {
      Variable => rootBuildContext.getVariableImpl(ident) as V?,
      AnalysisVariable => rootAnalysisContext.getVariableImpl(ident) as V?,
      _ => null,
    };
  }

  @override
  void dispose() {
    rootBuildContext.dispose();
    llvmCtxs.values.firstOrNull?.dispose();
  }
}
