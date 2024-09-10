import '../../llvm_core.dart';
import '../ast.dart';
import '../builders/coms.dart';
import '../stmt.dart';
import '../tys.dart';
import 'build_context_mixin.dart';
import 'build_methods.dart';
import 'llvm_types.dart';

abstract class Variable extends LifeCycleVariable {
  Variable(this.ident);

  LLVMValueRef load(StoreLoadMixin c);
  bool isIgnore = false;

  LLVMConstVariable getRef(StoreLoadMixin c, Identifier ident) {
    return LLVMConstVariable(getBaseValue(c), RefTy(ty), ident);
  }

  LLVMValueRef getBaseValue(StoreLoadMixin c) => load(c);

  Variable asType(StoreLoadMixin c, Ty ty);

  @override
  final Identifier ident;

  Offset get offset => ident.offset;

  Variable newIdent(Identifier id, {bool dirty = false}) {
    final value = newIdentInternal(id, dirty);
    return value;
  }

  Variable newIdentInternal(Identifier id, bool dirty);

  Variable getBaseVariable(StoreLoadMixin c, Identifier ident) {
    Variable current = this;
    for (;;) {
      final newVal = current.defaultDeref(c, ident);
      if (newVal == current) return current;
      current = newVal;
    }
  }

  Variable defaultDeref(StoreLoadMixin c, Identifier ident) {
    final cTy = ty;
    if (cTy is! RefTy) return this;

    final parent = cTy.parent;
    return LLVMAllocaVariable.delay(
        () => load(c), parent, parent.typeOf(c), ident);
  }

  @override
  String toString() {
    return 'variable:$ident';
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
    // init
    alloca;

    if (ty is RefTy) {
      if (val is LLVMAllocaProxyVariable && !val.created) {
        val.initProxy(proxy: this);
        return;
      }

      if (alloca != val.getBaseValue(c)) {
        c.store(alloca, val.load(c), offset);
      }
      return;
    }

    val = FnCatch.toFnClosure(c, ty, val) ?? val;

    if (val is LLVMAllocaProxyVariable && !val.created) {
      if (!isNew) ImplStackTy.removeStack(c, this);
      val.initProxy(proxy: this);
      if (!isNew) ImplStackTy.updateStack(c, this);
      return;
    }

    if (alloca == val.getBaseValue(c)) {
      return;
    }

    final update = val is! LLVMLitVariable;

    if (update) {
      if (!isNew) {
        ImplStackTy.replaceStack(c, this, val);
      } else {
        ImplStackTy.addStack(c, val);
      }
    }

    c.store(alloca, val.load(c), offset);

    if (!isNew && update) {
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

typedef ProxyFn = void Function(
    LLVMAllocaProxyVariable? variable, bool isProxy);

class LLVMAllocaProxyVariable extends StoreVariable {
  LLVMAllocaProxyVariable(
      this._createContext, this._proxyFn, this.ty, this.type, super.ident)
      : _root = null;
  LLVMAllocaProxyVariable._(this._root, this._createContext, this._proxyFn,
      this.ty, this.type, super.ident);

  final ProxyFn _proxyFn;
  @override
  final Ty ty;

  @override
  final LLVMTypeRef type;

  bool get created => _root?._alloca != null || _alloca != null;

  final StoreLoadMixin _createContext;
  LLVMValueRef? _alloca;

  @override
  LLVMValueRef get alloca {
    if (_root != null) return _root.alloca;

    if (_alloca != null) return _alloca!;

    final alloca = _alloca = ty.llty.createAlloca(_createContext, ident).alloca;
    _proxyFn(this, false);

    return alloca;
  }

  /// 从 [proxy] 中获取地址空间
  ///
  /// [cancel] : [ExprStmt]使用，取消创建操作
  bool initProxy({StoreVariable? proxy, bool cancel = false}) {
    if (_root != null) return _root.initProxy(proxy: proxy);

    final result = _alloca == null;
    if (result) {
      if (cancel) {
        _proxyFn(null, true);
      } else {
        _alloca =
            proxy?.alloca ?? ty.llty.createAlloca(_createContext, ident).alloca;

        _proxyFn(this, proxy != null);
      }
    }

    return result;
  }

  final LLVMAllocaProxyVariable? _root;
  @override
  LLVMAllocaProxyVariable newIdentInternal(Identifier id, bool dirty) {
    _dirty = dirty;
    return LLVMAllocaProxyVariable._(
        _root ?? this, _createContext, _proxyFn, ty, type, id)
      .._alloca = _alloca;
  }

  @override
  Variable asType(StoreLoadMixin c, Ty ty) {
    return LLVMAllocaProxyVariable._(
        _root ?? this, _createContext, _proxyFn, ty, ty.typeOf(c), ident)
      .._alloca = _alloca;
  }
}

typedef DelayFn = LLVMValueRef Function();

/// 使用已分配的地址
/// 有[store],[load]功能
class LLVMAllocaVariable extends StoreVariable {
  LLVMAllocaVariable(LLVMValueRef this._alloca, this.ty, this.type, super.ident)
      : _delayFn = null,
        _root = null;
  LLVMAllocaVariable.delay(
      DelayFn this._delayFn, this.ty, this.type, super.ident)
      : _root = null;

  LLVMAllocaVariable._(this._root, this.ty, this.type, super.ident)
      : _delayFn = null,
        _alloca = null;

  final DelayFn? _delayFn;

  LLVMValueRef? _alloca;

  void init() => alloca;

  @override
  LLVMValueRef get alloca => _root?.alloca ?? (_alloca ??= _delayFn!());

  @override
  final LLVMTypeRef type;

  @override
  final Ty ty;

  final LLVMAllocaVariable? _root;

  @override
  LLVMAllocaVariable newIdentInternal(Identifier id, bool dirty) {
    _dirty = dirty;
    return LLVMAllocaVariable._(_root ?? this, ty, type, id);
  }

  @override
  LLVMAllocaVariable asType(StoreLoadMixin c, Ty ty) {
    return LLVMAllocaVariable._(_root ?? this, ty, ty.typeOf(c), ident);
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
