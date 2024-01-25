import '../../llvm_core.dart';
import '../ast.dart';
import '../context.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'coms.dart';
import 'llvm_types.dart';

abstract class Variable extends LifeCycleVariable {
  Variable(this.ident);

  LLVMValueRef load(StoreLoadMixin c);

  LLVMConstVariable getRef(StoreLoadMixin c, Identifier ident) {
    return LLVMConstVariable(getBaseValue(c), RefTy(ty), ident);
  }

  LLVMValueRef getBaseValue(StoreLoadMixin c) => load(c);

  Variable asType(StoreLoadMixin c, Ty ty);
  Ty get ty;

  @override
  final Identifier ident;

  Offset get offset => ident.offset;

  Variable newIdent(Identifier id, {bool dirty = false}) {
    final value = newIdentInternal(id, dirty);
    return value;
  }

  Variable newIdentInternal(Identifier id, bool dirty);

  Variable defaultDeref(StoreLoadMixin c, Identifier ident) {
    final cTy = ty;
    if (cTy is! RefTy) return this;

    final parent = cTy.parent;
    return LLVMAllocaVariable.delay(
        () => load(c), parent, parent.typeOf(c), ident);
  }
}

abstract class StoreVariable extends Variable {
  StoreVariable(super.ident);

  LLVMValueRef get alloca;
  LLVMTypeRef get type;

  @override
  LLVMValueRef getBaseValue(StoreLoadMixin c) {
    assert(!_dirty);
    return alloca;
  }

  bool _dirty = false;

  @override
  LLVMValueRef load(StoreLoadMixin c) {
    assert(!_dirty);
    return c.load2(type, alloca, '', offset);
  }

  LLVMValueRef store(StoreLoadMixin c, LLVMValueRef val) {
    assert(!_dirty);
    return c.store(alloca, val, offset);
  }

  void storeVariable(FnBuildMixin c, Variable val, {bool isNew = false}) {
    assert(!_dirty);

    if (val is LLVMAllocaDelayVariable && !val.created) {
      if (!isNew) ImplStackTy.removeStack(c, this);
      val.initProxy(proxy: this);
      if (!isNew) ImplStackTy.updateStack(c, this);
      return;
    }

    final update = alloca != val.getBaseValue(c);
    if (update) {
      ImplStackTy.addStack(c, val);
      if (!isNew) ImplStackTy.removeStack(c, this);
    }

    c.store(alloca, val.load(c), offset);

    if (update && !isNew) {
      ImplStackTy.updateStack(c, this);
    }
  }
}

/// 没有[store]功能
///
/// 可以看作右值，临时变量
class LLVMConstVariable extends Variable {
  LLVMConstVariable(this.value, this.ty, super.ident);
  @override
  final Ty ty;

  final LLVMValueRef value;

  @override
  LLVMValueRef getBaseValue(BuildMethods c) {
    return value;
  }

  @override
  LLVMValueRef load(BuildMethods c) {
    return value;
  }

  @override
  LLVMConstVariable newIdentInternal(Identifier id, bool dirty) {
    return LLVMConstVariable(value, ty, id);
  }

  @override
  Variable asType(StoreLoadMixin c, Ty ty) {
    return LLVMConstVariable(value, ty, ident);
  }
}

typedef LoadFn = void Function(LLVMAllocaDelayVariable variable, bool isProxy);

/// 不会立即分配内存，如立即使用[context.allocator()]
/// 可以重定向到[_create]返回的[_alloca],[_alloca]作为分配地址
/// 一般用在复杂结构体中，如结构体内包含其他结构体，在作为字面量初始化时会使用外面
class LLVMAllocaDelayVariable extends StoreVariable {
  LLVMAllocaDelayVariable(
      this._createContext, this._delayLoad, this.ty, this.type, super.ident);

  final LoadFn _delayLoad;
  @override
  final Ty ty;

  @override
  final LLVMTypeRef type;

  bool get created => _alloca != null;

  final StoreLoadMixin _createContext;
  LLVMValueRef? _alloca;
  @override
  LLVMValueRef get alloca {
    if (_alloca != null) return _alloca!;

    final alloca = _alloca = ty.llty.createAlloca(_createContext, ident).alloca;
    _delayLoad(this, false);

    return alloca;
  }

  /// 从 [proxy] 中获取地址空间
  bool initProxy({StoreVariable? proxy}) {
    final result = _alloca == null;
    if (result) {
      _alloca =
          proxy?.alloca ?? ty.llty.createAlloca(_createContext, ident).alloca;
      _delayLoad(this, proxy != null);
    }

    return result;
  }

  @override
  LLVMAllocaDelayVariable newIdentInternal(Identifier id, bool dirty) {
    _dirty = dirty;
    return LLVMAllocaDelayVariable(_createContext, _delayLoad, ty, type, id)
      .._alloca = _alloca;
  }

  @override
  Variable asType(StoreLoadMixin c, Ty ty) {
    return LLVMAllocaDelayVariable(
        _createContext, _delayLoad, ty, ty.typeOf(c), ident)
      .._alloca = _alloca;
  }
}

typedef DelayFn = LLVMValueRef Function();

/// 使用已分配的地址
/// 有[store],[load]功能
class LLVMAllocaVariable extends StoreVariable {
  LLVMAllocaVariable(LLVMValueRef this._alloca, this.ty, this.type, super.ident)
      : _delayFn = null;
  LLVMAllocaVariable.delay(
      DelayFn this._delayFn, this.ty, this.type, super.ident);

  LLVMAllocaVariable._(
      this._delayFn, this._alloca, this.ty, this.type, super.ident);

  final DelayFn? _delayFn;

  LLVMValueRef? _alloca;

  void init() => alloca;

  @override
  LLVMValueRef get alloca => _alloca ??= _delayFn!();

  @override
  final LLVMTypeRef type;

  @override
  final Ty ty;

  @override
  LLVMAllocaVariable newIdentInternal(Identifier id, bool dirty) {
    _dirty = dirty;
    assert(_delayFn != null || _alloca != null);
    return LLVMAllocaVariable._(_delayFn, _alloca, ty, type, ident);
  }

  @override
  LLVMAllocaVariable asType(StoreLoadMixin c, Ty ty) {
    return LLVMAllocaVariable._(_delayFn, _alloca, ty, ty.typeOf(c), ident);
  }
}

/// 内部的原生类型
class LLVMLitVariable extends Variable {
  LLVMLitVariable(this._load, this.ty, this.value, super.ident);

  final LLVMRawValue value;
  @override
  final BuiltInTy ty;
  final LLVMValueRef Function(Consts c, BuiltInTy? ty) _load;
  LLVMValueRef? _cache;
  @override
  LLVMValueRef load(StoreLoadMixin c, {BuiltInTy? ty}) {
    return _cache ??= _load(c, ty);
  }

  LLVMValueRef getValue(Consts c) {
    return _cache ??= _load(c, null);
  }

  @override
  LLVMLitVariable newIdentInternal(Identifier id, bool dirty) {
    return LLVMLitVariable(_load, ty, value, id).._cache = _cache;
  }

  LLVMAllocaVariable createAlloca(StoreLoadMixin c, Identifier ident,
      [Ty? tty]) {
    if (tty is! BuiltInTy) {
      tty = ty;
    }

    final alloca = ty.llty.createAlloca(c, ident);
    final rValue = load(c, ty: tty);
    alloca.store(c, rValue);

    return alloca;
  }

  @override
  Variable asType(StoreLoadMixin c, Ty ty) {
    return this;
  }
}
