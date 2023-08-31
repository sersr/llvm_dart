import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../fs/fs.dart';
import '../parsers/parser.dart';
import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/buildin.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/tys.dart';

mixin ManagerBase {
  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      return parseTopItem(data);
    }
    return null;
  }

  final llvmCtxs = <String, BuildContext>{};
  final alcs = <String, AnalysisContext>{};
  final others = <String, Tys>{};

  Map<String, Tys> getMap(Tys<dynamic, LifeCycleVariable> target) {
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
        final parser = parserToken(path)!;
        printParser(parser, path);
      }
    });
  }

  void printLifeCycle(void Function(AnalysisVariable variable) action) {
    for (var e in alcs.values) {
      e.forEach(action);
    }
  }

  Tys importBuild<T>(Tys<dynamic, LifeCycleVariable> current, ImportPath path) {
    final pname = Consts.regSrc(path.name.src);
    var pathName = '';
    final currentPath = current.currentPath;
    if (currentPath != null) {
      pathName =
          join(currentDir.childDirectory(currentPath).parent.path, pname);
    } else {
      final p = currentDir.childFile(pname);
      pathName = p.path;
    }

    final pn = normalize(pathName);
    final map = getMap(current);
    var child = map[pn];
    if (child == null) {
      child = current.import() as Tys;
      map[pn] = child;
      final parser = parserToken(pn);
      if (parser == null) {
        //error
        return child;
      }

      baseProcess(
        context: child,
        path: pn,
        isRoot: false,
        action: (builder) {
          switch (child) {
            case BuildContext child:
              builder.build(child);
            case AnalysisContext child:
              builder.analysis(child);
          }
        },
      );
    }
    return child;
  }

  void baseProcess(
      {required Tys context,
      required String path,
      Parser? parser,
      required void Function(BuildMixin builder) action,
      bool isRoot = true,
      ImportHandler? importHandler}) {
    context.currentPath = path;
    parser ??= parserToken(path)!;
    context.importHandler = importHandler ?? importBuild;

    parser.globalImportStmt.values.forEach(action);

    context.pushAllTy(parser.globalTy);
    parser.globalStmt.values.forEach(action);

    if (!isRoot) return;
    action(sizeOfFn);
    if (context is BuildContext) {
      out:
      for (var fns in context.fns.values) {
        for (var fn in fns) {
          if (fn.fnSign.fnDecl.ident.src == 'main') {
            action(fn);
            break out;
          }
        }
      }
    } else {
      for (var fns in context.fns.values) {
        for (var fn in fns) {
          action(fn);
        }
      }
    }
  }
}
