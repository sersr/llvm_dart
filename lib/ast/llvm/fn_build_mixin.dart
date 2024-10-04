part of 'build_context_mixin.dart';

mixin FnBuildMixin
    on BuildContext, SretMixin, FreeMixin, FlowMixin, FnContextMixin {
  void buildFnBB(Fn fn, FnDecl fnDecl,
      {required LLVMValueRef fnValue, bool ignoreFree = false}) {
    final block = fn.block?.clone();
    if (block == null) return;

    final fnContext = fn.currentContext!.createChildContext();

    fnContext._fnValue = fnValue;
    fnContext._currentFn = fn;
    fnContext._fnScope = llvm.LLVMGetSubprogram(fnValue);
    fnContext._isFnBBContext = true;
    fnContext.instertFnEntryBB();
    fn.pushTyGenerics(fnContext, fnDecl);

    fnContext.initFnParamsStart(fnValue, fn, fnDecl, ignoreFree: ignoreFree);

    block.build(fnContext, hasRet: true);

    if (block.isEmpty) {
      fnContext.ret(null);
    }
  }

  void initFnParamsStart(LLVMValueRef fn, Fn fnty, FnDecl fnDecl,
      {bool ignoreFree = false}) {
    final sret =
        AbiFn.initFnParams(this, fn, fnty, fnDecl, ignoreFree: ignoreFree);
    if (sret != null) _sret = sret;
  }

  void initFnParams(LLVMValueRef fn, Fn fnTy, FnDecl decl,
      {bool ignoreFree = false}) {
    final params = decl.fields;
    var index = 0;
    final retTy = decl.getRetTy(this);
    if (retTy.llty.getBytes(this) > 8) {
      final value = llvm.LLVMGetParam(fn, index);
      _sret =
          LLVMAllocaVariable(value, retTy, retTy.typeOf(this), Identifier.none);
      setName(value, 'sret');
      index += 1;
    }

    if (fnTy case ImplFn(isStatic: false, ty: var ty)) {
      final selfValue = llvm.LLVMGetParam(fn, index);
      final ident = Identifier.self;

      final value = LLVMAllocaVariable(selfValue, ty, ty.typeOf(this), ident);

      setName(selfValue, ident.src);
      diBuilderDeclare(ident, selfValue, ty);
      pushVariable(value);
      index += 1;
    }

    final paramIndices = <(FieldDef, int)>[];
    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      var realTy = decl.getFieldTy(this, p);
      if (realTy is! FnCatch) {
        final fnParam = llvm.LLVMGetParam(fn, index);
        resolveParam(realTy, fnParam, p.ident, ignoreFree);
      } else {
        paramIndices.add((p, index));
      }
      index += 1;
    }

    void pushCatch(AnalysisVariable val) {
      final ty = val.ty;
      final fnParam = llvm.LLVMGetParam(fn, index);
      final value = LLVMAllocaVariable(fnParam, ty, ty.typeOf(this), val.ident);
      setName(fnParam, val.ident.src);
      diBuilderDeclare(val.ident, fnParam, ty);
      pushVariable(value);
    }

    if (decl is FnCatch) {
      for (var val in decl.analysisVariables) {
        pushCatch(val);
        index += 1;
      }
    }

    for (final (param, pIndex) in paramIndices) {
      final ty = decl.getFieldTy(this, param);

      if (ty is FnCatch) {
        final fnParam = llvm.LLVMGetParam(fn, pIndex);

        final variables = <Variable>[];
        for (var val in ty.analysisVariables) {
          final ty = val.ty;
          final fnParam = llvm.LLVMGetParam(fn, index);
          final value =
              LLVMAllocaVariable(fnParam, ty, ty.typeOf(this), Identifier.none);
          setName(fnParam, val.ident.src);
          variables.add(value);
          index += 1;
        }

        final nTy = ty.newVariables(variables);
        resolveParam(nTy, fnParam, param.ident, ignoreFree);
      }
    }
  }

  void resolveParam(
      Ty ty, LLVMValueRef fnParam, Identifier ident, bool ignoreFree) {
    if (ty.llty.getBytes(this) > 8) {
      final alloca = LLVMAllocaVariable(fnParam, ty, ty.typeOf(this), ident);
      setName(fnParam, ident.src);
      diBuilderDeclare(ident, fnParam, ty);
      pushVariable(alloca);
    } else {
      final alloca = ty.llty.createAlloca(this, ident);
      alloca.store(this, fnParam);
      if (ignoreFree) removeVal(alloca);
      diBuilderDeclare(ident, alloca.alloca, ty);
      pushVariable(alloca);
    }
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

    fn.pushTyGenerics(this, fn.baseFnDecl);

    block.build(this, hasRet: true);

    if (_runBbAfter != null) {
      insertPointBB(_runBbAfter!);
    }

    return _compileDyValue;
  }

  @override
  void sretRet(StoreVariable sret, Variable val) {
    if (val is LLVMAllocaProxyVariable && !val.created) {
      val.initProxy(proxy: sret);
    } else {
      sret.storeVariable(this, val);
    }
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
