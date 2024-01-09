import '../../llvm_core.dart';
import '../ast.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'llvm_types.dart';

abstract class Variable extends LifeCycleVariable {
  Variable(this.ident);
  bool isRef = false;
  LLVMValueRef load(StoreLoadMixin c);

  LLVMConstVariable getRef(StoreLoadMixin c, Identifier ident) {
    return LLVMConstVariable(getBaseValue(c), RefTy(ty), ident);
  }

  LLVMValueRef getBaseValue(StoreLoadMixin c) => load(c);
  Ty get ty;

  @override
  final Identifier ident;

  Offset get offset => ident.offset;

  Variable newIdent(Identifier id);

  Variable defaultDeref(StoreLoadMixin c, Identifier ident) {
    final cTy = ty;
    if (cTy is! RefTy) return this;

    final v = load(c);
    final parent = cTy.parent;

    Variable val;

    /// 如果是一个指针，说明还有下一级，满足 store, load
    if (parent is RefTy) {
      val = LLVMAllocaVariable(v, parent, parent.typeOf(c), ident);
    } else {
      val = LLVMConstVariable(v, parent, ident);
    }
    return val;
  }
}

abstract class StoreVariable extends Variable {
  StoreVariable(super.ident);

  /// 在 let 表达式使用，判断是否需要分配空间或者直接使用当前对象
  LLVMValueRef get alloca;
  LLVMTypeRef get type;

  @override
  StoreVariable newIdent(Identifier id) {
    final value = newIdentInternal(id);
    value.isRef = isRef;
    return value;
  }

  StoreVariable newIdentInternal(Identifier id);

  @override
  LLVMValueRef getBaseValue(StoreLoadMixin c) {
    return alloca;
  }

  @override
  LLVMValueRef load(StoreLoadMixin c) {
    return c.load2(type, alloca, '', offset);
  }

  LLVMValueRef store(StoreLoadMixin c, LLVMValueRef val) {
    return c.store(alloca, val, offset);
  }

  LLVMValueRef storeVariable(StoreLoadMixin c, Variable val) {
    return c.store(alloca, val.load(c), offset);
  }
}

/// 没有[store]功能
///
/// 可以看作右值，临时变量
/// 函数返回值，数值运算
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
  LLVMConstVariable newIdent(Identifier id) {
    return LLVMConstVariable(value, ty, id);
  }
}

typedef LoadFn = LLVMValueRef Function(StoreVariable? proxy);

mixin DelayVariableMixin {
  LoadFn get _delayLoad;

  LLVMValueRef? _alloca;

  bool get created => _alloca != null;

  /// 从 [proxy] 中获取地址空间
  bool initProxy({StoreVariable? proxy}) {
    final result = _alloca == null;
    _alloca ??= _delayLoad(proxy);

    return result;
  }

  LLVMValueRef get alloca => _alloca ??= _delayLoad(null);
}

/// 不会立即分配内存，如立即使用[context.allocator()]
/// 可以重定向到[_create]返回的[_alloca],[_alloca]作为分配地址
/// 一般用在复杂结构体中，如结构体内包含其他结构体，在作为字面量初始化时会使用外面
/// 结构体[LLVMStructType.getField]创建的[Variable]
class LLVMAllocaDelayVariable extends StoreVariable with DelayVariableMixin {
  LLVMAllocaDelayVariable(this._delayLoad, this.ty, this.type, super.ident);
  @override
  final LoadFn _delayLoad;
  @override
  final Ty ty;

  @override
  final LLVMTypeRef type;

  bool _isTemp = true;

  @override
  bool initProxy({StoreVariable? proxy}) {
    _isTemp = false;
    return super.initProxy(proxy: proxy);
  }

  bool get isTemp => _isTemp;

  @override
  LLVMValueRef getBaseValue(StoreLoadMixin c) {
    initProxy();
    return super.getBaseValue(c);
  }

  @override
  LLVMValueRef load(StoreLoadMixin c, {Offset? o}) {
    return c.load2(type, alloca, '', o ?? offset);
  }

  @override
  LLVMValueRef store(StoreLoadMixin c, LLVMValueRef val, {Offset? o}) {
    initProxy();
    return c.store(alloca, val, o ?? offset);
  }

  @override
  LLVMValueRef storeVariable(StoreLoadMixin c, Variable val, {Offset? o}) {
    initProxy();
    return c.store(alloca, val.load(c), o ?? offset);
  }

  @override
  LLVMAllocaDelayVariable newIdentInternal(Identifier id) =>
      _LLVMAllocaDelayVariableProxy(this, id);
}

class _LLVMAllocaDelayVariableProxy extends StoreVariable
    implements LLVMAllocaDelayVariable {
  _LLVMAllocaDelayVariableProxy(this._proxy, super.ident);
  final LLVMAllocaDelayVariable _proxy;

  // hide
  @override
  LLVMValueRef? _alloca;

  @override
  @override
  LoadFn get _delayLoad => throw UnimplementedError();

  @override
  LLVMValueRef get alloca => _proxy.alloca;

  @override
  bool get created => _proxy.created;

  @override
  bool _isTemp = false;

  @override
  bool get isTemp => _proxy.isTemp;

  @override
  LLVMValueRef getBaseValue(StoreLoadMixin c) {
    return _proxy.getBaseValue(c);
  }

  @override
  LLVMConstVariable getRef(StoreLoadMixin c, Identifier ident) {
    return _proxy.getRef(c, ident);
  }

  @override
  bool initProxy({StoreVariable? proxy}) {
    return _proxy.initProxy(proxy: proxy);
  }

  @override
  LLVMValueRef load(StoreLoadMixin c, {Offset? o}) {
    return _proxy.load(c, o: o ?? offset);
  }

  @override
  LLVMAllocaDelayVariable newIdentInternal(Identifier id) {
    return _proxy.newIdentInternal(id);
  }

  @override
  LLVMValueRef store(StoreLoadMixin c, LLVMValueRef val, {Offset? o}) {
    return _proxy.store(c, val, o: o ?? offset);
  }

  @override
  LLVMValueRef storeVariable(StoreLoadMixin c, Variable val, {Offset? o}) {
    return _proxy.storeVariable(c, val, o: o ?? offset);
  }

  @override
  Ty get ty => _proxy.ty;

  @override
  LLVMTypeRef get type => _proxy.type;
}

/// 使用已分配的地址
/// 有[store],[load]功能
class LLVMAllocaVariable extends StoreVariable {
  LLVMAllocaVariable(this.alloca, this.ty, this.type, super.ident);
  @override
  final LLVMValueRef alloca;

  @override
  final LLVMTypeRef type;

  @override
  final Ty ty;

  @override
  LLVMAllocaVariable newIdentInternal(Identifier id) {
    return LLVMAllocaVariable(alloca, ty, type, id);
  }
}

typedef DelayFn = LLVMValueRef Function();

class LLVMDelayVariable extends StoreVariable implements LLVMAllocaVariable {
  LLVMDelayVariable(this._delayFn, this.ty, this.type, super.ident);
  @override
  final Ty ty;

  @override
  final LLVMTypeRef type;

  final DelayFn _delayFn;
  LLVMValueRef? _alloca;

  @override
  LLVMValueRef get alloca => _alloca ??= _delayFn();

  DelayFn? _rootFn;

  @override
  LLVMAllocaVariable newIdentInternal(Identifier id) {
    final fn = _rootFn ??= () => alloca;
    return LLVMDelayVariable(fn, ty, type, id).._rootFn = fn;
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
  LLVMLitVariable newIdent(Identifier id) {
    return LLVMLitVariable(_load, ty, value, id);
  }

  LLVMAllocaDelayVariable createAlloca(StoreLoadMixin c, Identifier ident,
      [Ty? tty]) {
    if (tty is! BuiltInTy) {
      tty = ty;
    }

    final alloca = ty.llty.createAlloca(c, ident);
    final rValue = load(c, ty: tty);
    alloca.store(c, rValue);

    return alloca;
  }
}
