import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/buildin.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/llvm/variables.dart';
import '../ast/tys.dart';
import '../fs/fs.dart';
import '../llvm_dart.dart';
import '../parsers/parser.dart';

abstract class ManagerBase extends GlobalContext {
  ManagerBase() {
    init();
  }

  static const stds = [
    'd.kc',
  ];

  void init() {
    for (var std in stds) {
      final path = normalize(join(stdRoot, std));
      addStd(path);
    }
  }

  void addStd(String path) {}

  @override
  bool isStd(Tys c) {
    for (var std in stds) {
      final path = normalize(join(stdRoot, std));
      if (path == c.currentPath) return true;
    }
    return false;
  }

  void importStdTys(Tys c) {
    for (var std in stds) {
      final path = normalize(join(stdRoot, std));
      if (c.currentPath == path) return;
      c.pushImport(ImportPath.path(path));
    }
  }

  void dispose() {}

  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      return parseTopItem(data);
    }
    return null;
  }

  String get stdRoot => '';

  final _mapParsers = <String, Parser?>{};

  Parser? getParser(String path) =>
      _mapParsers.putIfAbsent(path, () => parserToken(path));

  @override
  Tys<LifeCycleVariable> import(
      Tys<LifeCycleVariable> current, ImportPath path) {
    final currentPath = current.currentPath;
    String rawPath = path.path;
    if (rawPath.startsWith('std:')) {
      rawPath = rawPath.replaceFirst(RegExp('^std:'), '');
      rawPath = join(stdRoot, rawPath);
    } else {
      rawPath = fs.file(currentPath).parent.childFile(rawPath).path;
    }

    rawPath = normalize(rawPath);
    return creatChildContext(current, rawPath);
  }

  Tys creatChildContext(Tys from, String path) {
    throw StateError('Unknown type: ${from.runtimeType}');
  }

  @override
  VA? getKVImpl<VA, T>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    throw UnimplementedError();
  }

  @override
  V? getVariable<V>(Identifier ident) {
    throw UnimplementedError();
  }
}

mixin BuildContextMixin on ManagerBase {
  final llvmCtxs = <String, BuildContextImpl>{};

  RootBuildContext get rootBuildContext;

  BuildContextImpl build(String path) {
    return llvmCtxs.putIfAbsent(path, () {
      final root = BuildContextImpl.root(rootBuildContext, path);
      importStdTys(root);
      root.debugInit();
      initBuildContext(context: root, path: path);
      return root;
    });
  }

  @override
  Tys<LifeCycleVariable> creatChildContext(
      Tys<LifeCycleVariable> from, String path) {
    return switch (from) {
      BuildContext() => build(path),
      _ => super.creatChildContext(from, path),
    };
  }

  void initBuildContext({required FnBuildMixin context, required String path}) {
    final parser = getParser(path)!;

    final block = parser.block;
    block.build(context);
  }

  Fn? getFn(String name) {
    for (var ctx in llvmCtxs.values) {
      for (var fns in ctx.fns.values) {
        for (var fn in fns) {
          if (fn.fnName.src == name) {
            return fn;
          }
        }
      }
    }
    return null;
  }

  static bool _initLLVM = false;

  @override
  void init() {
    if (!_initLLVM) {
      _initLLVM = true;
      llvm.initLLVM();
    }
    rootBuildContext.global = this;
    initBuiltinFns(rootBuildContext);
    rootBuildContext.init();
    super.init();
  }

  @override
  void addStd(String path) {
    super.addStd(path);
    build(path);
  }

  @override
  void dispose() {
    rootBuildContext.dispose();
    for (var ctx in llvmCtxs.values) {
      ctx.dispose();
    }
    llvmCtxs.clear();
    super.dispose();
  }

  @override
  VA? getKVImpl<VA, T>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    return switch (T) {
      Variable => rootBuildContext.getKVImpl<VA>(map, test: test),
      _ => super.getKVImpl<VA, T>(map, test: test),
    };
  }

  @override
  V? getVariable<V>(Identifier ident) {
    return switch (V) {
      Variable => rootBuildContext.getVariableImpl(ident) as V?,
      _ => super.getVariable(ident),
    };
  }
}

mixin AnalysisContextMixin on ManagerBase {
  final alcs = <String, AnalysisContext>{};
  final rootAnalysis = RootAnalysis();

  AnalysisContext analysis(String path) {
    return alcs.putIfAbsent(path, () {
      final alc = AnalysisContext.root(rootAnalysis, path);
      importStdTys(alc);
      initAnalysisContext(context: alc, path: path);
      return alc;
    });
  }

  @override
  Tys creatChildContext(Tys from, String path) {
    return switch (from) {
      AnalysisContext() => analysis(path),
      _ => super.creatChildContext(from, path),
    };
  }

  void initAnalysisContext(
      {required AnalysisContext context, required String path}) {
    final parser = getParser(path)!;

    final block = parser.block;

    block.analysis(context);

    for (var fns in context.fns.values) {
      for (var fn in fns) {
        fn.analysis(context);
      }
    }
  }

  @override
  void init() {
    rootAnalysis.global = this;
    initBuiltinFns(rootAnalysis);
    super.init();
  }

  @override
  void addStd(String path) {
    analysis(path);
    super.addStd(path);
  }

  @override
  void dispose() {
    alcs.clear();
    super.dispose();
  }

  void printAst() {
    void printParser(Parser parser, String path) {
      Log.i('--- $path', showTag: false);
      Log.w(parser.stmts.join('\n'), showTag: false);
    }

    for (var entry in alcs.entries) {
      final path = entry.key;
      final parser = getParser(path)!;
      printParser(parser, path);
    }
  }

  void printLifeCycle(void Function(AnalysisVariable variable) action) {
    for (var e in alcs.values) {
      e.forEach(action);
    }
  }

  @override
  VA? getKVImpl<VA, T>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    return switch (T) {
      AnalysisVariable => rootAnalysis.getKVImpl<VA>(map, test: test),
      _ => super.getKVImpl<VA, T>(map, test: test),
    };
  }

  @override
  V? getVariable<V>(Identifier ident) {
    return switch (V) {
      AnalysisVariable => rootAnalysis.getVariableImpl(ident) as V?,
      _ => super.getVariable(ident),
    };
  }
}
