import 'dart:async';

import 'ast/analysis_context.dart';
import 'ast/buildin.dart';
import 'ast/llvm_context.dart';
import 'llvm_dart.dart';
import 'parsers/parser.dart';

void testRun(String src, {bool mem2reg = false, bool build = true}) {
  runZoned(
    () {
      final m = parseTopItem(src);
      print(m.globalTy.values.join('\n'));
      if (!build) return;
      final root = AnalysisContext.root();
      root.pushAllTy(m.globalTy);
      for (var fns in root.fns.values) {
        for (var fn in fns) {
          fn.analysis(root);
        }
      }
      {
        llvm.initLLVM();
        final root = BuildContext.root();
        BuildContext.mem2reg = mem2reg;
        root.pushAllTy(m.globalTy);
        root.pushFn(sizeOfFn.ident, sizeOfFn);

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
    },
    zoneValues: {'astSrc': src},
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
    }),
  );
}
