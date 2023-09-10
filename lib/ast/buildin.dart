import 'analysis_context.dart';
import 'ast.dart';
import 'llvm/llvm_context.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';

final class BuiltinFn extends Ty {
  BuiltinFn(this.name);
  final Identifier name;
  @override
  void analysis(AnalysisContext context) {}

  @override
  LLVMType get llvmType => throw UnimplementedError();

  @override
  List<Object?> get props => [name];
}

LLVMConstVariable sizeOf(BuildContext c, Ty ty) {
  if (ty is EnumItem) {
    ty = ty.parent;
  }
  final tyy = ty.llvmType.createType(c);
  final size = c.typeSize(tyy);

  final v = c.usizeValue(size);
  return LLVMConstVariable(v, BuiltInTy.usize);
}

final sizeOfFn = BuiltinFn(Identifier.builtIn('sizeOf'));
