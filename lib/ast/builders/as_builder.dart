part of 'builders.dart';

abstract class AsBuilder {
  static Variable asType(
      FnBuildMixin context, Variable lv, Identifier asId, Ty asTy) {
    final lty = lv.ty;
    if (lty is EnumItem && asTy is EnumItem) {
      if (lty.parent == asTy.parent) {
        return lv;
      }
    }

    if (asTy is BuiltInTy && lty is BuiltInTy) {
      final val = context.castLit(lty.literal, lv.load(context), asTy.literal);
      return LLVMConstVariable(val, asTy, asId);
    }
    Variable? asValue;

    if (lty is RefTy && asTy is BuiltInTy && asTy.literal.isInt) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildPtrToInt(
          context.builder, lv.load(context), type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else if (lty is BuiltInTy && lty.literal.isInt && asTy is RefTy) {
      final type = asTy.typeOf(context);
      final v = llvm.LLVMBuildIntToPtr(
          context.builder, lv.load(context), type, unname);
      asValue = LLVMConstVariable(v, asTy, asId);
    } else {
      asValue = lv.asType(context, asTy);
    }

    return asValue;
  }
}
