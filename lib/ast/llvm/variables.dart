import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../context.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'llvm_types.dart';

abstract class Variable extends LifeCycleVariable {
  bool isRef = false;
  LLVMValueRef load(covariant BuildMethods c, Offset offset);
  LLVMTypeRef getDerefType(BuildContext c);
  Variable getRef(BuildContext c) {
    return LLVMConstVariable(getBaseValue(c), RefTy(ty));
  }

  LLVMValueRef getBaseValue(covariant BuildMethods c) => load(c, Offset.zero);
  Ty get ty;

  Variable defaultDeref(BuildContext c) {
    final cTy = ty;
    if (cTy is! RefTy) return this;

    final v = load(c, Offset.zero);
    final parent = cTy.parent;

    Variable val;

    /// 如果是一个指针，说明还有下一级，满足 store, load
    if (parent is RefTy) {
      val = LLVMAllocaVariable(parent, v, parent.llvmType.createType(c))
        ..isTemp = false;
    } else {
      val = LLVMConstVariable(v, parent);
    }
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

/// 没有[store]功能
///
/// 可以看作右值，临时变量
/// 函数返回值，数值运算
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
}

mixin DelayVariableMixin {
  LLVMValueRef Function([StoreVariable? alloca, Identifier? ident]) get _create;

  LLVMValueRef? _alloca;

  bool get created => _alloca != null;

  bool create(BuildContext c, [StoreVariable? alloca, Identifier? ident]) {
    final result = _alloca == null;
    _alloca ??= _create(alloca, ident);
    if (result) {
      storeInit(c);
    }
    return result;
  }

  void storeInit(BuildContext c);

  LLVMValueRef get alloca => _alloca ??= _create();
}

/// 不会立即分配内存，如立即使用[context.allocator()]
/// 可以重定向到[_create]返回的[_alloca],[_alloca]作为分配地址
/// 一般用在复杂结构体中，如结构体内包含其他结构体，在作为字面量初始化时会使用外面
/// 结构体[LLVMStructType.getField]创建的[Variable]
class LLVMAllocaDelayVariable extends StoreVariable
    with DelayVariableMixin, Deref {
  LLVMAllocaDelayVariable(this.ty, this.initAlloca, this._create, this.type);
  @override
  final LLVMValueRef Function([StoreVariable? alloca, Identifier? ident])
      _create;
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

/// 使用已分配的地址
/// 有[store],[load]功能
class LLVMAllocaVariable extends StoreVariable implements Deref {
  LLVMAllocaVariable(this.ty, this.alloca, this.type);
  @override
  final LLVMValueRef alloca;

  final LLVMTypeRef type;

  @override
  final Ty ty;

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

/// 内部的原生类型
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

  LLVMAllocaDelayVariable createAlloca(BuildContext c, Identifier ident,
      [BuiltInTy? tty]) {
    final rValue = load(c, ident.offset, ty: tty);
    final alloca = ty.llvmType.createAlloca(c, ident, rValue);

    return alloca;
  }
}
