import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/ast/llvm_context.dart';
import 'package:llvm_dart/llvm_core.dart';

import '../llvm_dart.dart';
import 'llvm_types.dart';
import 'variables.dart';

class SizeofFn extends Fn {
  SizeofFn()
      : super(FnSign(true, FnDecl(Identifier.none, [], Ty.unknown)),
            Block([], null));
  final ident = Identifier.builtIn('sizeof');
  @override
  void build(BuildContext context) {}

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
  LLVMConstVariable createFunction(BuildContext c, {Ty? ty}) {
    final tyy = ty!.llvmType.createType(c);
    final size = llvm.LLVMSizeOf(tyy);
    return LLVMConstVariable(size, ty);
  }
}

final sizeOfFn = SizeofFn();
