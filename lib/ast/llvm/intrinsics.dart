import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../memory.dart';
import 'build_methods.dart';
import 'llvm_context.dart';

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

  static LLVMIntrisics? getAdd(Ty ty, bool isSigned, BuildContext context) {
    final t = getTypeFrom(ty, context);
    if (t != null && !isSigned) {
      return values[t.index + 5];
    }
    return t;
  }

  static LLVMIntrisics? getSub(Ty ty, bool isSigned, BuildContext context) {
    final t = getTypeFrom(ty, context);
    if (t != null) {
      if (isSigned) {
        return values[t.index + 10];
      }
    }
    return t;
  }

  static LLVMIntrisics? getMul(Ty ty, bool isSigned, BuildContext context) {
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

  static LLVMIntrisics? getTypeFrom(Ty ty, BuildContext context) {
    if (ty is! BuiltInTy) return null;
    switch (ty.ty.convert) {
      case LitKind.i8:
        return saddOI8;
      case LitKind.i16:
        return saddOI16;
      case LitKind.i32:
      case LitKind.kInt:
        return saddOI32;
      case LitKind.i64:
        return saddOI64;
      case LitKind.i128:
        return saddOI128;
      default:
    }

    if (ty.ty == LitKind.usize) {
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

mixin OverflowMath on Consts {
  static final maps = <String, FunctionDeclare>{};

  late final typeList = [i8, i16, i32, i64, i128];

  LLVMValueRef expect(LLVMValueRef lhs) {
    final fn = maps
        .putIfAbsent("llvm.expect.i1",
            () => FunctionDeclare([i1, i1], 'llvm.expect.i1', i1))
        .build(this);
    return llvm.LLVMBuildCall2(builder, i1, fn,
        [lhs, constI1(LLVMFalse)].toNative(), 2, 'bool'.toChar());
  }

  MathValue oMath(LLVMValueRef lhs, LLVMValueRef rhs, LLVMIntrisics fn) {
    final ty = typeList[fn.index % 5];
    final structTy = typeStruct([ty, i1], null);
    final inFn = maps.putIfAbsent(fn.name, () {
      return FunctionDeclare([ty, ty], fn.name, structTy);
    });
    final f = inFn.build(this);

    final result = llvm.LLVMBuildCall2(
        builder, inFn.type, f, [lhs, rhs].toNative(), 2, unname);
    final l1 =
        llvm.LLVMBuildExtractValue(builder, result, 0, '_result_0'.toChar());
    final l2 =
        llvm.LLVMBuildExtractValue(builder, result, 1, '_result_1'.toChar());
    return MathValue(l1, l2);
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
  LLVMTypeRef get type {
    return llvm.LLVMFunctionType(
        retType, params.toNative(), params.length, LLVMFalse);
  }

  LLVMValueRef build(BuildMethods context) {
    if (_fn != null) return _fn!;
    return _fn = llvm.LLVMAddFunction(context.module, name.toChar(), type);
  }
}
