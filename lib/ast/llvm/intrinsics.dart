import 'dart:ffi';

import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../expr.dart';
import '../memory.dart';
import 'build_methods.dart';
import 'llvm_context.dart';
import 'variables.dart';

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

    if (ty.ty.isSize) {
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

mixin OverflowMath on BuildMethods, Consts {
  late final typeList = [i8, i16, i32, i64, i128];
  LLVMValueRef expect(LLVMValueRef lhs) {
    final fn = root.maps.putIfAbsent("llvm.expect.i1",
        () => FunctionDeclare([i1, i1], 'llvm.expect.i1', i1));
    final f = fn.build(this);
    return llvm.LLVMBuildCall2(builder, fn.type, f,
        [lhs, constI1(LLVMTrue)].toNative(), 2, 'bool'.toChar());
  }

  LLVMValueRef assume(LLVMValueRef expr) {
    final fn = root.maps.putIfAbsent(
        "llvm.assume", () => FunctionDeclare([i1], 'llvm.assume', typeVoid));

    return llvm.LLVMBuildCall2(
        builder, fn.type, fn.build(this), [expr].toNative(), 1, unname);
  }

  MathValue oMath(LLVMValueRef lhs, LLVMValueRef rhs, LLVMIntrisics fn) {
    final ty = typeList[fn.index % 5];
    final structTy = typeStruct([ty, i1], null);
    final inFn = root.maps.putIfAbsent(fn.name, () {
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

  void painc() {
    llvm.LLVMBuildUnreachable(builder);
  }

  static Variable math(BuildContext context, Variable lhs, Variable? rhs,
      OpKind op, Identifier opId) {
    final builder = context.builder;

    var isFloat = false;
    var signed = false;
    var ty = lhs.ty;
    LLVMTypeRef? type;

    var l = lhs.load(context);
    var r = rhs?.load(context);

    if (r == null || rhs == null) {
      LLVMValueRef? value;

      if (op == OpKind.Eq) {
        value = llvm.LLVMBuildIsNull(builder, l, unname);
      } else {
        assert(op == OpKind.Ne);
        value = llvm.LLVMBuildIsNotNull(builder, l, unname);
      }
      return LLVMConstVariable(value, BuiltInTy.kBool, opId);
    }

    if (ty is BuiltInTy && ty.ty.isNum) {
      final kind = ty.ty;
      final rty = rhs.ty;
      if (rty is BuiltInTy) {
        final rSize = rty.llty.getBytes(context);
        final lSize = ty.llty.getBytes(context);
        final max = rSize > lSize ? rty : ty;
        type = max.typeOf(context);
        ty = max;
      }
      if (kind.isFp) {
        isFloat = true;
      } else if (kind.isInt) {
        signed = kind.signed;
      }
    } else if (ty is RefTy) {
      ty = rhs.ty;
      type = ty.typeOf(context);
      l = llvm.LLVMBuildPtrToInt(builder, l, type, unname);
    }

    type ??= ty.typeOf(context);

    if (isFloat) {
      l = llvm.LLVMBuildFPCast(builder, l, type, unname);
      r = llvm.LLVMBuildFPCast(builder, r, type, unname);
    } else {
      l = llvm.LLVMBuildIntCast2(builder, l, type, signed.llvmBool, unname);
      r = llvm.LLVMBuildIntCast2(builder, r, type, signed.llvmBool, unname);
    }

    if (op == OpKind.And || op == OpKind.Or) {
      final after = context.buildSubBB(name: 'op_after');
      final opBB = context.buildSubBB(name: 'op_bb');
      final allocaValue = context.alloctor(context.i1, name: 'op');
      final variable =
          LLVMAllocaVariable(allocaValue, BuiltInTy.kBool, context.i1, opId);

      variable.store(context, l);
      context.appendBB(opBB);

      if (op == OpKind.And) {
        llvm.LLVMBuildCondBr(builder, l, opBB.bb, after.bb);
      } else {
        llvm.LLVMBuildCondBr(builder, l, after.bb, opBB.bb);
      }
      final c = opBB.context;

      variable.store(c, r);
      c.br(after.context);
      context.insertPointBB(after);
      return variable;
    }

    LLVMValueRef Function(LLVMBuilderRef b, LLVMValueRef l, LLVMValueRef r,
        Pointer<Char> name)? llfn;

    context.diSetCurrentLoc(opId.offset);

    if (isFloat) {
      final id = op.getFCmpId(true);
      if (id != null) {
        final v = llvm.LLVMBuildFCmp(builder, id, l, r, unname);
        return LLVMConstVariable(v, BuiltInTy.kBool, opId);
      }
      LLVMValueRef? value;
      switch (op) {
        case OpKind.Add:
          value = llvm.LLVMBuildFAdd(builder, l, r, unname);
        case OpKind.Sub:
          value = llvm.LLVMBuildFSub(builder, l, r, unname);
        case OpKind.Mul:
          value = llvm.LLVMBuildFMul(builder, l, r, unname);
        case OpKind.Div:
          value = llvm.LLVMBuildFDiv(builder, l, r, unname);
        case OpKind.Rem:
          value = llvm.LLVMBuildFRem(builder, l, r, unname);
        case OpKind.BitAnd:
        case OpKind.BitOr:
        case OpKind.BitXor:
        // value = llvm.LLVMBuildAnd(builder, l, r, unname);
        // value = llvm.LLVMBuildOr(builder, l, r, unname);
        // value = llvm.LLVMBuildXor(builder, l, r, unname);
        default:
      }
      if (value != null) {
        return LLVMConstVariable(value, ty, opId);
      }
    }

    final isConst = lhs is LLVMLitVariable && rhs is LLVMLitVariable;
    final cmpId = op.getICmpId(signed);
    if (cmpId != null) {
      final v = llvm.LLVMBuildICmp(builder, cmpId, l, r, unname);
      return LLVMConstVariable(v, BuiltInTy.kBool, opId);
    }

    LLVMValueRef? value;

    LLVMIntrisics? k;
    switch (op) {
      case OpKind.Add:
        if (isConst) {
          llfn = llvm.LLVMBuildAdd;
        } else {
          k = LLVMIntrisics.getAdd(ty, signed, context);
        }
        break;
      case OpKind.Sub:
        if (!signed || isConst) {
          llfn = llvm.LLVMBuildSub;
        } else {
          k = LLVMIntrisics.getSub(ty, signed, context);
        }
        break;
      case OpKind.Mul:
        if (isConst) {
          llfn = llvm.LLVMBuildMul;
        } else {
          k = LLVMIntrisics.getMul(ty, signed, context);
        }
        break;
      case OpKind.Div:
        llfn = signed ? llvm.LLVMBuildSDiv : llvm.LLVMBuildUDiv;
        break;
      case OpKind.Rem:
        llfn = signed ? llvm.LLVMBuildSRem : llvm.LLVMBuildURem;
        break;
      case OpKind.BitAnd:
        llfn = llvm.LLVMBuildAnd;
        break;
      case OpKind.BitOr:
        llfn = llvm.LLVMBuildOr;
        break;
      case OpKind.BitXor:
        llfn = llvm.LLVMBuildXor;
        break;
      case OpKind.Shl:
        llfn = llvm.LLVMBuildShl;
        break;
      case OpKind.Shr:
        llfn = signed ? llvm.LLVMBuildAShr : llvm.LLVMBuildLShr;
        break;
      default:
    }

    assert(k != null || llfn != null);

    if (k != null) {
      final mathValue = context.oMath(l, r, k);
      final after = context.buildSubBB(name: 'math');
      final panicBB = context.buildSubBB(name: 'panic');
      context.appendBB(panicBB);
      llvm.LLVMBuildCondBr(builder, mathValue.condition, panicBB.bb, after.bb);
      panicBB.context.diSetCurrentLoc(opId.offset);
      panicBB.context.painc();
      context.insertPointBB(after);

      return LLVMConstVariable(mathValue.value, ty, opId);
    }
    if (llfn != null) {
      value = llfn(builder, l, r, unname);
    }

    return LLVMConstVariable(value ?? l, ty, opId);
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
