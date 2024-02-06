part of 'build_context_mixin.dart';

mixin FnBuildMixin
    on BuildContext, SretMixin, FreeMixin, FlowMixin, FnContextMixin {
  void buildFnBB(Fn fn,
      {Set<AnalysisVariable>? extra,
      required LLVMConstVariable fnValue,
      bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>>? map}) {
    final block = fn.block?.clone();
    if (block == null) return;

    final fnContext = fn.currentContext!.createChildContext();

    fnContext._fnVariable = fnValue;
    fnContext._fnScope = llvm.LLVMGetSubprogram(fnValue.value);
    fnContext._isFnBBContext = true;
    fnContext.instertFnEntryBB();
    fn.pushTyGenerics(fnContext);

    fnContext.initFnParamsStart(fnValue.value, fn, extra,
        ignoreFree: ignoreFree, map: map ?? const {});

    block.build(fnContext, hasRet: true);

    if (block.isEmpty) {
      fnContext.ret(null);
    }
  }

  void initFnParamsStart(LLVMValueRef fn, Fn fnty, Set<AnalysisVariable>? extra,
      {bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final sret = AbiFn.initFnParams(this, fn, fnty, extra,
        ignoreFree: ignoreFree, map: map);
    if (sret != null) _sret = sret;
  }

  void initFnParams(LLVMValueRef fn, Fn fnty, Set<AnalysisVariable>? extra,
      {bool ignoreFree = false,
      Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final params = fnty.fnSign.fnDecl.params;
    var index = 0;

    if (fnty is ImplFn) {
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
    }

    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      final fnParam = llvm.LLVMGetParam(fn, index);
      var realTy = fnty.getFieldTy(this, p);
      if (realTy is FnTy) {
        final extra = map[p.ident];
        if (extra != null) {
          realTy = realTy.copyWith(extra);
        }
      }

      resolveParam(realTy, fnParam, p.ident, ignoreFree);
      index += 1;
    }

    void fnCatchVariable(AnalysisVariable variable, int index) {
      final value = llvm.LLVMGetParam(fn, index);
      final ident = variable.ident;
      final val = getVariable(ident);

      if (val == null) {
        return;
      }

      final ty = val.ty;
      final type = ty.typeOf(this);
      final alloca = LLVMAllocaVariable(value, ty, type, ident);
      if (!ignoreFree) addFree(alloca);
      setName(value, ident.src);
      pushVariable(alloca);
    }

    for (var variable in fnty.variables) {
      fnCatchVariable(variable, index);
      index += 1;
    }

    if (extra != null) {
      for (var variable in extra) {
        fnCatchVariable(variable, index);
        index += 1;
      }
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
