part of 'builders.dart';

abstract class AsBuilder {
  static Variable asType(
      FnBuildMixin context, Variable lv, Identifier asId, Ty asTy) {
    final lty = lv.ty;
    assert(lty is! EnumItem && asTy is! EnumItem);

    if (asTy is BuiltInTy && lty is BuiltInTy) {
      final val = context.castLit(lty.literal, lv.load(context), asTy.literal);
      return LLVMConstVariable(val, asTy, asId);
    }

    Variable? asValue;

    switch (asTy) {
      case BuiltInTy(literal: var literial) when literial.isInt && lty is RefTy:
        final type = asTy.typeOf(context);
        final v = llvm.LLVMBuildPtrToInt(
            context.builder, lv.load(context), type, unname);
        asValue = LLVMConstVariable(v, asTy, asId);
      case RefTy() when lty is BuiltInTy && lty.literal.isInt:
        final type = asTy.typeOf(context);
        final v = llvm.LLVMBuildIntToPtr(
            context.builder, lv.load(context), type, unname);
        asValue = LLVMConstVariable(v, asTy, asId);
      case _:
        asValue = lv.asType(context, asTy);
    }

    return asValue;
  }
}
