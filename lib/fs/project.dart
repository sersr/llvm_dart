import 'dart:ffi';

import 'package:nop/nop.dart';
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
  Project(this.path, {this.isDebug = true}) {
    _init();
  }

  final String path;
  final bool isDebug;

  late Parser parser;

  void _init() {
    Identifier.run(() {
      parser = parserToken(path)!;
    });
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

  void printAst() {
    void printParser(String path, Parser parser) {
      Log.w('--- $path', showTag: false);
      if (parser.globalVar.isNotEmpty) {
        print(parser.globalVar.values.join('\n'));
      }
      print(parser.globalTy.values.join('\n'));
    }

    Identifier.run(() {
      printParser(path, parser);
      for (var entry in _caches.entries) {
        final path = entry.key;
        final parser = entry.value;
        if (parser == null) continue;
        printParser(path, parser);
      }
    });
  }

  void printLifeCycle(void Function(AnalysisVariable variable) action) {
    final alc = analysisContext;
    if (alc == null) return;
    alc.forEach(action);
  }

  void analysis() {
    Identifier.run(() {
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
    final mImport = _caches.putIfAbsent(pn, () => parserToken(pathName));
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
      final fileName = currentDir.childFile(path).basename;
      final root = buildContext = BuildContext.root(fileName);
      root.currentPath = path;
      root.init(isDebug);
      root.importHandler = importBuild as dynamic;

      for (var val in parser.globalVar.values) {
        val.build(root);
      }

      root.pushAllTy(parser.globalTy);

      for (var val in parser.globalVar.values) {
        val.build(root);
      }
      root.pushFn(SizeOfFn.ident, sizeOfFn);

      out:
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          if (fn.fnSign.fnDecl.ident.src == 'main') {
            fn.build(root);
            break out;
          }
        }
      }
      root.finalize();

      llvm.optimize(
        root.kModule,
        LLVMRustPassBuilderOptLevel.O0,
        LLVMRustOptStage.PreLinkNoLTO,
        LLVMFalse,
        LLVMTrue,
        LLVMTrue,
        LLVMTrue,
        LLVMTrue,
        LLVMTrue,
        LLVMTrue,
        LLVMFalse,
      );
      llvm.LLVMDumpModule(root.module);
      llvm.LLVMPrintModuleToFile(root.module, buildFile('out.ll'), nullptr);
      llvm.writeOutput(
          root.kModule, LLVMCodeGenFileType.LLVMObjectFile, buildFile('out.o'));
      after?.call();
      root.dispose();
    });
  }
}
