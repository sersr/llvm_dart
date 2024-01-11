import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/tys.dart';
import '../fs/fs.dart';
import '../parsers/parser.dart';
import '../parsers/str.dart';

abstract class ManagerBase extends GlobalContext {
  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      return parseTopItem(data);
    }
    return null;
  }

  String get stdRoot => '';

  final llvmCtxs = <String, BuildContext>{};
  final alcs = <String, AnalysisContext>{};
  final others = <String, Tys>{};

  Map<String, Tys> getMap(Tys target) {
    return switch (target) {
      BuildContext _ => llvmCtxs,
      AnalysisContext _ => alcs,
      _ => others,
    } as Map<String, Tys>;
  }

  void printAst() {
    void printParser(Parser parser, String path) {
      Log.w('--- $path', showTag: false);
      if (parser.globalStmt.isNotEmpty) {
        print(parser.globalStmt.values.join('\n'));
      }
      print(parser.globalTy.values.join('\n'));
    }

    Identifier.run(() {
      for (var entry in alcs.entries) {
        final path = entry.key;
        final parser = getParser(path)!;
        printParser(parser, path);
      }
    });
  }

  void printLifeCycle(void Function(AnalysisVariable variable) action) {
    for (var e in alcs.values) {
      e.forEach(action);
    }
  }

  final _mapParsers = <String, Parser>{};

  Parser? getParser(String path) {
    var parser = _mapParsers[path];
    if (parser != null) return parser;
    parser = parserToken(path);
    if (parser != null) {
      _mapParsers[path] = parser;
    }
    return parser;
  }

  @override
  Tys<LifeCycleVariable> import(
      Tys<LifeCycleVariable> current, ImportPath path) {
    var pname = parseStr(path.name.src);

    final currentPath = current.currentPath;
    assert(currentPath != null, 'current == null.');
    if (pname.startsWith('std:')) {
      pname = pname.replaceFirst(RegExp('^std:'), stdRoot);
    }

    final filePath =
        join(currentDir.childDirectory(currentPath!).parent.path, pname);

    final pn = normalize(filePath);
    final map = getMap(current);
    var child = map[pn];
    if (child == null) {
      child = current.defaultImport(pn);

      map[pn] = child;
      initChildContext(child, pn);
    }
    return child;
  }

  void initChildContext(Tys context, String path);

  void dispose() {}
}

mixin BuildContextMixin on ManagerBase {
  void initBuildContext({required FnBuildMixin context, required String path}) {
    final parser = getParser(path)!;
    // for (var stmt in parser.globalImportStmt.values) {
    //   stmt.build(context);
    // }
    // context.pushAllTy(parser.globalTy);
    // for (var stmt in parser.globalStmt.values) {
    //   stmt.build(context);
    // }

    // for (var ty in parser.globalTy.values) {
    //   ty.currentContext = context;
    // }

    for (var stmt in parser.stmts) {
      stmt.build(context);
    }
  }
}

mixin AnalysisContextMixin on ManagerBase {
  void initAnalysisContext(
      {required AnalysisContext context, required String path}) {
    final parser = getParser(path)!;
    // for (var stmt in parser.globalImportStmt.values) {
    //   stmt.analysis(context);
    // }
    // context.pushAllTy(parser.globalTy);

    // for (var stmt in parser.globalStmt.values) {
    //   stmt.analysis(context);
    // }
    // for (var fns in context.fns.values) {
    //   for (var fn in fns) {
    //     fn.analysis(context);
    //   }
    // }

    for (var stmt in parser.stmts) {
      stmt.analysis(context);
    }
  }
}
