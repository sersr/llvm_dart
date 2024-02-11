import 'package:meta/meta.dart';
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
    _stdPaths = stds.map((e) => normalize(join(stdRoot, e))).toList();
    init();
  }

  static const stds = [
    'd.kc',
    'vec.kc',
    'fn.kc',
    'closure.kc',
    'box.kc',
    'option.kc',
    'allocator.kc',
  ];

  late final List<String> _stdPaths;

  List<String> get stdPaths => _stdPaths;

  @mustCallSuper
  void init() {}

  @override
  bool isStd(Tys c) {
    for (var path in _stdPaths) {
      if (path == c.currentPath) return true;
    }
    return false;
  }

  void importStdTys(Tys c) {
    if (_stdPaths.contains(c.currentPath)) return;
    for (var path in _stdPaths) {
      c.pushImport(ImportPath.path(path));
    }
  }

  @override
  Ty? getStdTy(Tys<LifeCycleVariable> c, Identifier ident) {
    return null;
  }

  void dispose() {}

  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      final sufPath = getSufPath(path);

      return Parser(data, sufPath);
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
}

mixin BuildContextMixin on ManagerBase {
  final llvmCtxs = <String, BuildContextImpl>{};

  RootBuildContext get rootBuildContext;
  final _stdTys = <BuildContextImpl>{};

  @override
  Ty? getStdTy(Tys<LifeCycleVariable> c, Identifier ident) {
    if (c case BuildContextImpl()) {
      if (_stdTys.isEmpty) {
        for (var ctx in llvmCtxs.entries) {
          if (isStd(ctx.value)) {
            _stdTys.add(ctx.value);
          }
        }
      }
      for (var std in _stdTys) {
        final ty = std.getTy(ident);
        if (ty != null) return ty;
      }
    }

    return super.getStdTy(c, ident);
  }

  BuildContextImpl build(String path) {
    final cache = llvmCtxs[path];
    if (cache != null) return cache;

    final root = BuildContextImpl.root(rootBuildContext, path);
    llvmCtxs[path] = root;
    importStdTys(root);

    root.debugInit();
    initBuildContext(context: root, path: path);
    return root;
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
    final ident = name.ident;
    for (var ctx in llvmCtxs.values) {
      final fn = ctx.getFn(ident);
      if (fn != null) return fn;
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
}

mixin AnalysisContextMixin on ManagerBase {
  final alcs = <String, AnalysisContext>{};
  final rootAnalysis = RootAnalysis();

  AnalysisContext analysis(String path) {
    final cache = alcs[path];
    if (cache != null) return cache;

    final alc = AnalysisContext.root(rootAnalysis, path);
    alcs[path] = alc;

    importStdTys(alc);

    initAnalysisContext(context: alc, path: path);
    return alc;
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
  }

  @override
  void init() {
    rootAnalysis.global = this;
    initBuiltinFns(rootAnalysis);
    super.init();
  }

  @override
  void dispose() {
    alcs.clear();
    super.dispose();
  }

  void printAst() {
    void printParser(Parser parser, String path) {
      Log.i('--- $path', showTag: false);
      Log.w(parser.stmts, showTag: false);
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
}
