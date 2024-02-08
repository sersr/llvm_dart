part of 'build_context_mixin.dart';

mixin FnBuildMixin
    on BuildContext, SretMixin, FreeMixin, FlowMixin, FnContextMixin {
  void buildFnBB(Fn fn,
      {required LLVMValueRef fnValue, bool ignoreFree = false}) {
    final block = fn.block?.clone();
    if (block == null) return;

    final fnContext = fn.currentContext!.createChildContext();

    fnContext._fnValue = fnValue;
    fnContext._currentFn = fn;
    fnContext._fnScope = llvm.LLVMGetSubprogram(fnValue);
    fnContext._isFnBBContext = true;
    fnContext.instertFnEntryBB();
    fn.pushTyGenerics(fnContext);

    fnContext.initFnParamsStart(fnValue, fn, ignoreFree: ignoreFree);

    block.build(fnContext, hasRet: true);

    if (block.isEmpty) {
      fnContext.ret(null);
    }
  }

  void initFnParamsStart(LLVMValueRef fn, Fn fnty, {bool ignoreFree = false}) {
    final sret = AbiFn.initFnParams(this, fn, fnty, ignoreFree: ignoreFree);
    if (sret != null) _sret = sret;
  }

  void initFnParams(LLVMValueRef fn, Fn fnty, {bool ignoreFree = false}) {
    final params = fnty.fnDecl.fields;
    final decl = fnty.fnDecl;
    var index = 0;

    if (fnty is ImplFn && !fnty.isStatic) {
      final p = fnty.ty;
      final selfValue = llvm.LLVMGetParam(fn, index);
      final ident = Identifier.self;

      final value = switch (p) {
        BuiltInTy() => LLVMConstVariable(selfValue, p, ident),
        _ => LLVMAllocaVariable(selfValue, p, p.typeOf(this), ident),
      };

      setName(selfValue, ident.src);
      pushVariable(value);
      index += 1;
    } else if (decl is FnClosure) {
      decl.llty.pushVariables(this, fn);
      index += 1;
    }

    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      final fnParam = llvm.LLVMGetParam(fn, index);
      var realTy = fnty.fnDecl.getFieldTy(this, p);

      resolveParam(realTy, fnParam, p.ident, ignoreFree);
      index += 1;
    }
  }

  void resolveParam(
      Ty ty, LLVMValueRef fnParam, Identifier ident, bool ignoreFree) {
    final alloca = ty.llty.createAlloca(this, ident);
    alloca.store(this, fnParam);
    if (ignoreFree) removeVal(alloca);

    pushVariable(alloca);
  }

  Variable? compileRun(Fn fn, List<Variable> params) {
    final fnContext = fn.currentContext!.createNewRunContext();
    return fnContext._compileRun(fn, this, params);
  }

  Variable? _compileRun(Fn fn, FnBuildMixin context, List<Variable> params) {
    final block = fn.block?.clone();
    if (block == null) {
      Log.e('block == null');
      return null;
    }
    _updateDebugFn(context, this);

    _currentFn = fn;
    _inRunMode = true;

    for (var p in params) {
      pushVariable(p);
    }

    fn.pushTyGenerics(this);

    block.build(this, hasRet: true);

    if (_runBbAfter != null) {
      insertPointBB(_runBbAfter!);
    }

    return _compileDyValue;
  }

  @override
  void sretRet(StoreVariable sret, Variable val) {
    sret.storeVariable(this, val);
  }

  bool _freeDone = false;

  final List<LLVMValueRef> _caches = [];

  bool _freeAddCache(LLVMValueRef v) {
    if (_caches.contains(v)) {
      Log.w('contains.');
      return true;
    }
    _caches.add(v);
    return false;
  }

  @override
  void freeHeapCurrent(FnBuildMixin to) {
    assert(loopBBs.isEmpty || !_freeDone, "error: freedone.");
    for (var val in _ptrMap.values) {
      ImplStackTy.drop(to, val, to._freeAddCache);
    }
  }

  @override
  void freeBr(FnBuildMixin? from) {
    freeHeapCurrent(this);
    if (from != null) freeHeapParent(this, from: from);
  }

  @override
  void freeHeap() {
    if (_freeDone) return;
    freeHeapCurrent(this);
    freeHeapParent(this);
    _freeDone = true;
    _caches.clear();
  }

  @override
  void freeAddStack(Variable val) {
    if (val.ty is RefTy) return;
    ImplStackTy.addStack(this, val);
  }
}
