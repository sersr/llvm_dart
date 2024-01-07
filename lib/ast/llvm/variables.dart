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
      val = LLVMAllocaVariable(parent, v, parent.typeOf(c))..isTemp = false;
    } else {
      val = LLVMConstVariable(v, parent);
    }
    return val;
  }
}

abstract class StoreVariable extends Variable {
  /// 在 let 表达式使用，判断是否需要分配空间或者直接使用当前对象
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
class LLVMConstVariable extends Variable {
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

typedef LoadFn = LLVMValueRef Function(StoreVariable? proxy);

mixin DelayVariableMixin {
  LoadFn get _delayLoad;

  LLVMValueRef? _alloca;

  bool get created => _alloca != null;

  /// 从 [proxy] 中获取地址空间
  bool initProxy(BuildContext c, [StoreVariable? proxy]) {
    final result = _alloca == null;
    _alloca ??= _delayLoad(proxy);
    if (result) {
      storeInit(c);
    }
    return result;
  }

  void storeInit(BuildContext c);

  LLVMValueRef get alloca => _alloca ??= _delayLoad(null);
}

/// 不会立即分配内存，如立即使用[context.allocator()]
/// 可以重定向到[_create]返回的[_alloca],[_alloca]作为分配地址
/// 一般用在复杂结构体中，如结构体内包含其他结构体，在作为字面量初始化时会使用外面
/// 结构体[LLVMStructType.getField]创建的[Variable]
class LLVMAllocaDelayVariable extends StoreVariable with DelayVariableMixin {
  LLVMAllocaDelayVariable(this.ty, this.initAlloca, this._delayLoad, this.type);
  @override
  final LoadFn _delayLoad;
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
    initProxy(c);
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
    initProxy(c);
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
class LLVMAllocaVariable extends StoreVariable {
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
      [Ty? tty]) {
    if (tty is! BuiltInTy) {
      tty = ty;
    }

    final rValue = load(c, ident.offset, ty: tty);
    final alloca = ty.llty.createAlloca(c, ident, rValue);

    return alloca;
  }
}
