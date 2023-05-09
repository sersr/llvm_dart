import 'package:path/path.dart';

import '../ast/analysis_context.dart';
import '../ast/ast.dart';
import '../ast/buildin.dart';
import '../ast/llvm/build_methods.dart';
import '../ast/llvm/llvm_context.dart';
import '../ast/memory.dart';
import '../ast/tys.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../parsers/parser.dart';
import 'fs.dart';

class Project {
  Project(this.path) {
    _init();
  }

  final String path;

  late Parser parser;

  void _init() {
    parser = parserToken(path)!;
  }

  static Parser? parserToken(String path) {
    final file = currentDir.childFile(path);
    if (file.existsSync()) {
      final data = file.readAsStringSync();
      return parseTopItem(data);
    }
    return null;
  }

  AnalysisContext? analysisContext;
  BuildContext? buildContext;

  void run() {
    analysis();
    if (enableBuild) build(asmPrinter);
  }

  void asmPrinter() {
    if (buildContext != null && printAsm) {
      llvm.writeOutput(buildContext!.kModule,
          LLVMCodeGenFileType.LLVMAssemblyFile, 'out.s'.toChar());
    }
  }

  void analysis() {
    Identifier.run(() {
      print(parser.globalVar.values.join('\n'));
      print(parser.globalTy.values.join('\n'));

      final alc = analysisContext = AnalysisContext.root();
      alc.currentPath = path;
      alc.importHandler = importBuild;
      alc.pushAllTy(parser.globalTy);

      for (var val in parser.globalVar.values) {
        val.analysis(alc);
      }
      for (var fns in alc.fns.values) {
        for (var fn in fns) {
          fn.analysis(alc);
        }
      }
    });
  }

  bool mem2reg = false;
  bool printAsm = false;
  bool enableBuild = true;

  final _caches = <String, Parser?>{};
  Tys importBuild(Tys current, ImportPath path) {
    final child = current.import();
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
    final mImport = _caches.putIfAbsent(pn, () {
      final mImport = parserToken(pathName);
      if (mImport != null) {
        print(mImport.globalVar.values.join('\n'));
        print(mImport.globalTy.values.join('\n'));
      }
      return mImport;
    });
    if (mImport != null) {
      child.currentPath = pn;
      child.importHandler = importBuild;
      child.pushAllTy(mImport.globalTy);
      if (child is BuildContext) {
        for (var val in mImport.globalVar.values) {
          val.build(child);
        }
      } else if (child is AnalysisContext) {
        for (var val in mImport.globalVar.values) {
          val.analysis(child);
        }
      }
    }
    return child as Tys;
  }

  void build([void Function()? after]) {
    Identifier.run(() {
      llvm.initLLVM();
      final root = buildContext = BuildContext.root();
      root.currentPath = path;
      root.importHandler = importBuild as dynamic;
      BuildContext.mem2reg = mem2reg;
      root.pushAllTy(parser.globalTy);
      root.pushFn(SizeOfFn.ident, sizeOfFn);
      for (var val in parser.globalVar.values) {
        val.build(root);
      }
      out:
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          if (fn.fnSign.fnDecl.ident.src == 'main') {
            fn.build(root);
            break out;
          }
        }
      }

      llvm.LLVMDumpModule(root.module);
      after?.call();
      llvm.writeOutput(
          root.kModule, LLVMCodeGenFileType.LLVMObjectFile, 'out.o'.toChar());
      root.dispose();
    });
  }
}
