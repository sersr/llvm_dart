import '../llvm_core.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'llvm/llvm_context.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';

class SizeOfFn extends Fn {
  SizeOfFn()
      : super(
          FnSign(
            true,
            FnDecl(
              Identifier.none,
              [],
              [],
              PathTy.ty(BuiltInTy.lit(LitKind.usize)),
              false,
            ),
          ),
          Block([], null),
        );
  static final ident = Identifier.builtIn('sizeOf');
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
    return c.pointer();
  }

  @override
  LLVMConstVariable createFunction(BuildContext c,
      [Set<AnalysisVariable>? variables, Ty? ty]) {
    if (ty is EnumItem) {
      ty = ty.parent;
    }
    final tyy = ty!.llvmType.createType(c);
    // final size = llvm.LLVMSizeOf(tyy);
    final size = c.typeSize(tyy);

    final t = BuiltInTy.lit(LitKind.usize);
    final v = t.llvmType.createValue(str: '$size');
    return LLVMConstVariable(v.getBaseValue(c), t);
  }
}

final sizeOfFn = SizeOfFn();
