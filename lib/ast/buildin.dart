import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/llvm_context.dart';
import 'package:llvm_dart/llvm_core.dart';

import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'llvm_types.dart';
import 'variables.dart';

class SizeofFn extends Fn {
  SizeofFn()
      : super(FnSign(true, FnDecl(Identifier.none, [], Ty.unknown)),
            Block([], null));
  final ident = Identifier.builtIn('sizeof');
  @override
  LLVMConstVariable? build(BuildContext context,
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    return null;
  }

  @override
  SizeOfType get llvmType => SizeOfType(this);
}

class SizeOfType extends LLVMFnType {
  SizeOfType(super.fn);

  @override
  LLVMTypeRef createType(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  LLVMConstVariable createFunction(BuildContext c,
      [Set<AnalysisVariable>? variables, Ty? ty]) {
    final tyy = ty!.llvmType.createType(c);
    final size = llvm.LLVMSizeOf(tyy);
    return LLVMConstVariable(size, ty);
  }
}

final sizeOfFn = SizeofFn();
