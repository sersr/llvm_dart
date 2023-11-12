import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'llvm/llvm_context.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
import 'memory.dart';

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

LLVMAllocaVariable elmentAt(
    BuildContext c, Ty elementTy, Variable v, Variable index) {
  if (elementTy is EnumItem) {
    elementTy = elementTy.parent;
  }
  final tyy = elementTy.llvmType.createType(c);

  final ptr = v.getBaseValue(c);
  final indics = <LLVMValueRef>[index.load(c, Offset.zero)];

  final llValue = llvm.LLVMBuildInBoundsGEP2(
      c.builder, tyy, ptr, indics.toNative(), indics.length, unname);

  return LLVMAllocaVariable(elementTy, llValue, tyy);
}

final elementAt = BuiltinFn(Identifier.builtIn('getElement'));
