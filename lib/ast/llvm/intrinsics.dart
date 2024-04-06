import '../../llvm_dart.dart';
import '../ast.dart';
import '../memory.dart';
import 'build_methods.dart';

enum LLVMITy {
  i8,
  i16,
  i32,
  i64,
  i128,
}

enum LLVMIntrisics {
  saddOI8('llvm.sadd.with.overflow.i8'),
  saddOI16('llvm.sadd.with.overflow.i16'),
  saddOI32('llvm.sadd.with.overflow.i32'),
  saddOI64('llvm.sadd.with.overflow.i64'),
  saddOI128('llvm.sadd.with.overflow.i128'),

  uaddOI8('llvm.uadd.with.overflow.i8'),
  uaddOI16('llvm.uadd.with.overflow.i16'),
  uaddOI32('llvm.uadd.with.overflow.i32'),
  uaddOI64('llvm.uadd.with.overflow.i64'),
  uaddOI128('llvm.uadd.with.overflow.i128'),

  ssubOI8("llvm.ssub.with.overflow.i8"),
  ssubOI16("llvm.ssub.with.overflow.i16"),
  ssubOI32("llvm.ssub.with.overflow.i32"),
  ssubOI64("llvm.ssub.with.overflow.i64"),
  ssubOI128("llvm.ssub.with.overflow.i128"),

  // mul sign
  smulOI8("llvm.smul.with.overflow.i8"),
  smulOI16("llvm.smul.with.overflow.i16"),
  smulOI32("llvm.smul.with.overflow.i32"),
  smulOI64("llvm.smul.with.overflow.i64"),
  smulOI128("llvm.smul.with.overflow.i128"),
  // mul unsign
  umulOI8("llvm.umul.with.overflow.i8"),
  umulOI16("llvm.umul.with.overflow.i16"),
  umulOI32("llvm.umul.with.overflow.i32"),
  umulOI64("llvm.umul.with.overflow.i64"),
  umulOI128("llvm.umul.with.overflow.i128"),
  ;

  final String name;
  const LLVMIntrisics(this.name);

  static LLVMIntrisics? getAdd(Ty ty, bool isSigned, BuildMethods context) {
    final t = getTypeFrom(ty, context);
    if (t != null && !isSigned) {
      return values[t.index + 5];
    }
    return t;
  }

  static LLVMIntrisics? getSub(Ty ty, bool isSigned, BuildMethods context) {
    final t = getTypeFrom(ty, context);
    if (t != null) {
      if (isSigned) {
        return values[t.index + 10];
      }
    }
    return t;
  }

  static LLVMIntrisics? getMul(Ty ty, bool isSigned, BuildMethods context) {
    final t = getTypeFrom(ty, context);
    if (t != null) {
      if (isSigned) {
        return values[t.index + 15];
      } else {
        return values[t.index + 20];
      }
    }
    return t;
  }

  static LLVMIntrisics? getTypeFrom(Ty ty, BuildMethods context) {
    if (ty is! BuiltInTy) return null;
    switch (ty.literal.convert) {
      case LiteralKind.i8:
        return saddOI8;
      case LiteralKind.i16:
        return saddOI16;
      case LiteralKind.i32:
        return saddOI32;
      case LiteralKind.i64:
        return saddOI64;
      case LiteralKind.i128:
        return saddOI128;
      default:
    }

    if (ty.literal.isSize) {
      final size = context.pointerSize();
      if (size > 8) {
        return saddOI128;
      } else if (size > 4) {
        return saddOI64;
      } else {
        return saddOI32;
      }
    }
    return null;
  }
}

class MathValue {
  MathValue(this.value, this.condition);
  final LLVMValueRef value;
  final LLVMValueRef condition;
}

class FunctionDeclare {
  final LLVMTypeRef retType;
  final List<LLVMTypeRef> params;
  final String name;
  FunctionDeclare(this.params, this.name, this.retType);

  LLVMValueRef? _fn;
  LLVMTypeRef? _type;
  LLVMTypeRef get type {
    return _type ??= llvm.LLVMFunctionType(
        retType, params.toNative(), params.length, LLVMFalse);
  }

  LLVMValueRef build(BuildMethods context) {
    return _fn ??= llvm.LLVMAddFunction(context.module, name.toChar(), type);
  }
}
