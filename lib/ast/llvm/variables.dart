import 'dart:ffi';

import 'package:nop/nop.dart';

import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../context.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'llvm_types.dart';

abstract class Variable extends LifeCycleVariable {
  bool isRef = false;
  LLVMValueRef load(BuildContext c, Offset offset);
  LLVMTypeRef getDerefType(BuildContext c);
  Variable getRef(BuildContext c) {
    return RefTy(ty).llvmType.createAlloca(c, Identifier.none, getBaseValue(c));
  }

  // void setCurrentLoc(BuildContext c) {
  //   if (ident != null) {
  //     c.diSetCurrentLoc(ident!.offset);
  //   }
  // }

  LLVMValueRef getBaseValue(BuildContext c) => load(c, Offset.zero);
  Ty get ty;

  Variable defaultDeref(BuildContext c) {
    final cTy = ty;
    if (cTy is! RefTy) return this;

    final v = load(c, Offset.zero);
    final parent = cTy.parent;
    final type = parent.llvmType.createType(c);
    final val = LLVMAllocaVariable(parent, v, type);
    val.isTemp = false;
    return val;
  }
}

abstract class StoreVariable extends Variable {
  /// 一般是未命名的，右表达式生成的
  bool isTemp = true;
  LLVMValueRef get alloca;
  LLVMValueRef store(BuildContext c, LLVMValueRef val, Offset offset);

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return alloca;
  }
}

class LLVMConstVariable extends Variable with Deref {
  LLVMConstVariable(this.value, this.ty);
  @override
  final Ty ty;

  final LLVMValueRef value;

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return value;
  }

  @override
  LLVMValueRef load(BuildContext c, Offset offset) {
    return value;
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(value);
  }

  @override
  Variable getRef(BuildContext c) {
    final alloca =
        ty.llvmType.createAlloca(c, Identifier.builtIn('_ref'), value);
    alloca.create(c);
    return RefTy(ty).llvmType.createAlloca(c, Identifier.none, alloca.alloca);
  }
}

class LLVMTempOpVariable extends LLVMConstVariable {
  LLVMTempOpVariable(Ty ty, this.isFloat, this.isSigned, LLVMValueRef value)
      : super(value, ty);
  final bool isSigned;
  final bool isFloat;
}

mixin DelayVariableMixin {
  LLVMValueRef Function([StoreVariable? alloca]) get _create;

  LLVMValueRef? _alloca;

  bool get created => _alloca != null;

  bool create(BuildContext c, [StoreVariable? alloca]) {
    final result = _alloca == null;
    _alloca ??= _create(alloca);
    if (result) {
      storeInit(c);
    }
    return result;
  }

  void storeInit(BuildContext c);

  LLVMValueRef get alloca => _alloca ??= _create();
}

/// 只要用于 [Struct] 作为右值时延时分配
class LLVMAllocaDelayVariable extends StoreVariable
    with DelayVariableMixin, Deref {
  LLVMAllocaDelayVariable(this.ty, this.initAlloca, this._create, this.type);
  @override
  final LLVMValueRef Function([StoreVariable? alloca]) _create;
  @override
  final Ty ty;

  final LLVMTypeRef type;

  final LLVMValueRef? initAlloca;
  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return type;
  }

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    create(c);
    return super.getBaseValue(c);
  }

  @override
  Variable getRef(BuildContext c) {
    create(c);
    return RefTy(ty).llvmType.createAlloca(c, Identifier.none, alloca);
  }

  @override
  LLVMValueRef get alloca {
    if (!created && initAlloca != null) return initAlloca!;
    return super.alloca;
  }

  @override
  LLVMValueRef load(BuildContext c, Offset offset) {
    if (!created && initAlloca != null) return initAlloca!;
    return c.load2(type, alloca, '', offset);
  }

  @override
  LLVMValueRef store(BuildContext c, LLVMValueRef val, Offset offset) {
    create(c);
    return c.store(alloca, val, offset);
  }

  @override
  void storeInit(BuildContext c) {
    if (initAlloca == null) return;
    c.store(alloca, initAlloca!, Offset.zero);
  }
}

class LLVMAllocaVariable extends StoreVariable implements Deref {
  LLVMAllocaVariable(this.ty, this.alloca, this.type);
  @override
  final LLVMValueRef alloca;

  final LLVMTypeRef type;

  @override
  final Ty ty;

  @override
  Variable getRef(BuildContext c) {
    return RefTy(ty).llvmType.createAlloca(c, Identifier.none, alloca);
  }

  @override
  LLVMValueRef load(BuildContext c, Offset offset) {
    return c.load2(type, alloca, '', offset);
  }

  @override
  LLVMValueRef store(BuildContext c, LLVMValueRef val, Offset offset) {
    return c.store(alloca, val, offset);
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return type;
  }

  @override
  Variable getDeref(BuildContext c) {
    return defaultDeref(c);
  }
}

mixin Deref on Variable {
  Variable getDeref(BuildContext c) {
    return defaultDeref(c);
  }
}

class LLVMLitVariable extends Variable {
  LLVMLitVariable(this._load, this.ty, this.value);

  final LLVMRawValue value;
  @override
  final BuiltInTy ty;
  final LLVMValueRef Function(Consts c, BuiltInTy? ty) _load;
  LLVMValueRef? _cache;
  @override
  LLVMValueRef load(BuildContext c, Offset offset, {BuiltInTy? ty}) {
    return _cache ??= _load(c, ty);
  }

  LLVMValueRef getValue(Consts c) {
    return _cache ??= _load(c, null);
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(load(c, Offset.zero));
  }

  @override
  Variable getRef(BuildContext c) {
    final alloca = createAlloca(c, Identifier.builtIn('_${ty.ty.lit}_ref'));
    alloca.create(c);
    return RefTy(ty).llvmType.createAlloca(c, Identifier.none, alloca.alloca);
  }

  LLVMAllocaDelayVariable createAlloca(BuildContext c, Identifier ident,
      [BuiltInTy? tty]) {
    // 需要分配内存地址
    // final rty = tty ?? ty;
    Log.w(ident.light, showTag: false);
    final rValue = load(c, ident.offset, ty: tty);
    final alloca = ty.llvmType.createAlloca(c, ident, rValue);
    // alloca.store(c, rValue);

    // string 以指针形式存在，访问一次[load]会加载指针，以引用作为基本形式
    // if (rty.ty == LitKind.kString) {
    //   return LLVMRefAllocaVariable.create(c, alloca)..store(c, alloca.load(c));
    // }

    return alloca;
  }
}

abstract class UnimplVariable extends Variable {
  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  Variable getRef(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  LLVMValueRef load(BuildContext c, Offset offset) {
    throw UnimplementedError();
  }

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    throw UnimplementedError();
  }
}

class TyVariable extends UnimplVariable {
  TyVariable(this.ty);
  @override
  final Ty ty;
}
