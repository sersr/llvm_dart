part of 'build_context_mixin.dart';

mixin FnContextMixin on BuildContext, FreeMixin, FlowMixin {
  LLVMMetadataRef? _fnScope;

  @override
  LLVMMetadataRef get scope => _fnScope ?? parent?.scope ?? unit;

  LLVMConstVariable? _fn;
  LLVMValueRef? _fnValue;
  @override
  LLVMValueRef get fnValue => _fnValue ?? _fn!.value;

  StoreVariable? _sret;
  StoreVariable? get sret => _sret;

  Fn? _fnty;
  StoreVariable? _compileRetValue;
  Variable? _retValue;
  Variable? get compileDyValue => _retValue ?? _compileRetValue;
  StoreVariable? get compileRetValue {
    if (_compileRetValue != null) return _compileRetValue;
    final fn = _fnty;
    if (fn == null) return null;
    final ty = fn.getRetTy(this);

    return _compileRetValue = LLVMAllocaDelayVariable((proxy) {
      if (proxy != null) return proxy.alloca;

      final alloca =
          ty.llty.createAlloca(this, Identifier.builtIn('comple_ret'));
      removeVal(alloca);
      return alloca.alloca;
    }, ty, ty.typeOf(this), Identifier.none);
  }

  void _updateDebugFn(FnContextMixin parent, FnContextMixin debug) {
    builder = parent.builder;
    _fnValue = parent.getLastFnContext()?.fnValue;
    assert(dBuilder == null);

    // 一个函数只能和一个文件绑定，在同一个文件中，可以取巧，使用同一个file scope
    if (parent.currentPath == debug.currentPath) {
      init(parent);
      _fnScope = parent.scope;
    }
    _proxy = parent;
    isFnBBContext = true;
  }

  FnContextMixin? _proxy;
  @override
  void addFree(Variable val) {
    if (_proxy != null) {
      _proxy!.addFree(val);
      return;
    }
    super.addFree(val);
  }

  @override
  bool removeVal(Variable? val) {
    if (_proxy != null) {
      return _proxy!.removeVal(val);
    }
    return super.removeVal(val);
  }

  bool _inRunMode = false;
  LLVMBasicBlock? _runBbAfter;

  /// 同一个文件支持跳转
  bool compileRunMode(Fn fn) => currentPath == fn.currentContext!.currentPath;

  bool _updateRunAfter(Variable? val, FlowMixin current, islastStmt) {
    if (!_inRunMode) return false;

    var retV = islastStmt ? _compileRetValue : compileRetValue;

    if (val != null && retV != null) {
      if (val is LLVMAllocaDelayVariable && !val.created) {
        val.initProxy(proxy: retV);
      } else {
        retV.store(this, val.load(this));
      }
    } else {
      _retValue = val;
    }

    var block = _runBbAfter;
    if (current != this) {
      block = buildSubBB(name: '_new_ret');
      _runBbAfter = block;
    }

    if (block != null) current._br(block.context);
    return true;
  }
}
