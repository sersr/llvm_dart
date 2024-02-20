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

    if (asTy case BuiltInTy(literal: LiteralKind(isInt: true))
        when lty is RefTy) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildPtrToInt(
          context.builder, lv.load(context), type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else if (lty case BuiltInTy(literal: LiteralKind(isInt: true))
        when asTy is RefTy) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildIntToPtr(
          context.builder, lv.load(context), type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else {
      final v = FnCatch.toFnClosure(context, asTy, lv);
      if (v != null) {
        asValue = v;
      } else {
        asValue = lv.asType(context, asTy);
      }
    }

    return asValue;
  }
}
