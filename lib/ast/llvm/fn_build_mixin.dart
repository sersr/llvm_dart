part of 'build_context_mixin.dart';

mixin FnBuildMixin
    on BuildContext, SretMixin, FreeMixin, FlowMixin, FnContextMixin {
  LLVMConstVariable buildFnBB(Fn fn,
      [Set<AnalysisVariable>? extra,
      Map<Identifier, Set<AnalysisVariable>> map = const {},
      void Function(FnBuildMixin context)? onCreated]) {
    final fv = AbiFn.createFunction(this, fn, extra, (fv) {
      final block = fn.block?.clone();
      if (block == null) return;

      final fnContext = fn.currentContext!.createChildContext();
      fnContext._fn = fv;
      fnContext._fnScope = llvm.LLVMGetSubprogram(fv.value);
      fnContext.isFnBBContext = true;
      fnContext.instertFnEntryBB();
      onCreated?.call(fnContext);
      fnContext.initFnParamsStart(fv.value, fn.fnSign.fnDecl, fn, extra,
          map: map);
      block.build(fnContext, free: false);

      final retTy = fn.getRetTy(fnContext);
      if (retTy == BuiltInTy.kVoid) {
        fnContext.ret(null);
      } else {
        block.ret(fnContext);
      }
    });
    return fv;
  }

  void initFnParamsStart(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final sret = AbiFn.initFnParams(this, fn, decl, fnty, extra, map: map);
    _sret = sret;
  }

  void initFnParams(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final params = decl.params;
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
      var realTy = fnty.getRty(this, p);
      if (realTy is FnTy) {
        final extra = map[p.ident];
        if (extra != null) {
          realTy = realTy.clone(extra);
        }
      }

      resolveParam(realTy, fnParam, p.ident);
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

  void resolveParam(Ty ty, LLVMValueRef fnParam, Identifier ident) {
    final alloca = ty.llty.createAlloca(this, ident);
    alloca.store(this, fnParam);

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
    _inRunMode = true;

    for (var p in params) {
      pushVariable(p);
    }

    fn.pushTyGenerics(this);

    block.build(this, free: false);

    final retTy = fn.getRetTy(this);
    if (retTy == BuiltInTy.kVoid) {
      ret(null);
    } else {
      block.ret(this);
    }
    if (_runBbAfter != null) {
      insertPointBB(_runBbAfter!);
    }
    return _compileRetValue;
  }

  bool _freeDone = false;
  @override
  void freeHeap() {
    if (_freeDone) return;
    _freeDone = true;

    for (var variable in _stackComVariables) {
      ImplStackTy.removeStack(this, variable);
    }
  }

  @override
  void addStackCom(Variable variable) {
    ImplStackTy.addStack(this, variable);
  }
}