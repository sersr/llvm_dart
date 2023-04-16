import 'dart:async';

import 'ast/analysis_context.dart';
import 'ast/buildin.dart';
import 'ast/llvm_context.dart';
import 'llvm_dart.dart';
import 'parsers/parser.dart';

T runZonedSrc<T>(T Function() body, String src) {
  return runZoned(
    body,
    zoneValues: {'astSrc': src},
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
    }),
  );
}

AnalysisContext testRun(String src, {bool mem2reg = false, bool build = true}) {
  return runZoned(
    () {
      final m = parseTopItem(src);
      print(m.globalTy.values.join('\n'));
      final root = AnalysisContext.root();
      root.pushAllTy(m.globalTy);
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          fn.analysis(root);
        }
      }
      if (!build) return root;
      {
        llvm.initLLVM();
        final root = BuildContext.root();
        BuildContext.mem2reg = mem2reg;
        root.pushAllTy(m.globalTy);
        root.pushFn(SizeOfFn.ident, sizeOfFn);
        for (var es in root.enums.values) {
          for (var e in es) {
            e.build(root);
          }
        }
        for (var fns in root.fns.values) {
          for (var fn in fns) {
            fn.build(root);
          }
        }

        for (var impls in root.impls.values) {
          for (var impl in impls) {
            impl.build(root);
          }
        }

        llvm.LLVMDumpModule(root.module);
        llvm.writeOutput(root.kModule);
        root.dispose();
      }
      return root;
    },
    zoneValues: {'astSrc': src},
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
    }),
  );
}
