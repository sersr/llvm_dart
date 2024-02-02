part of 'build_context_mixin.dart';

mixin FnContextMixin on BuildContext, FreeMixin, FlowMixin {
  LLVMMetadataRef? _fnScope;

  @override
  LLVMMetadataRef get scope => _fnScope ?? parent?.scope ?? unit;

  bool _isFnBBContext = false;
  @override
  bool get isFnBBContext => _isFnBBContext;

  LLVMConstVariable? _fnVariable;

  LLVMValueRef? _fnValue;
  @override
  LLVMValueRef get fnValue => _fnValue ?? _fnVariable!.value;

  Fn? _currentFn;
  Fn? get currentFn => _fnVariable?.ty as Fn? ?? _currentFn!;

  StoreVariable? _sret;
  StoreVariable? get sret => _sret;

  /// ----------- compileRun -------------
  Variable? _retValue;
  StoreVariable? _compileRetValue;
  Variable? get _compileDyValue => _retValue ?? _compileRetValue;

  StoreVariable? get compileRetValue {
    assert(_retValue == null);
    if (_compileRetValue != null) return _compileRetValue;
    final fn = _currentFn;
    if (fn == null) return null;
    final ty = fn.getRetTy(this);

    return _compileRetValue = LLVMAllocaProxyVariable(this, (value, isProxy) {
      if (isProxy) return;
      removeVal(value);
    }, ty, ty.typeOf(this), 'compile_ret'.ident);
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
    _isFnBBContext = true;
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

  bool _updateRunAfter(Variable? val, FlowMixin current, bool islastStmt) {
    if (!_inRunMode) return false;

    final retValue = islastStmt ? _compileRetValue : compileRetValue;

    if (val != null && retValue != null) {
      if (val is LLVMAllocaProxyVariable && !val.created) {
        val.initProxy(proxy: retValue);
      } else {
        retValue.store(this, val.load(this));
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
