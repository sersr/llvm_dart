part of 'build_context_mixin.dart';

// class FnOptions {
//   const FnOptions({
//     this.isDrop = false,
//     this.isAddStack = false,
//     this.isRemoveStack = false,
//     this.isUpdateStack = false,
//   });

//   final bool isDrop;
//   final bool isAddStack;
//   final bool isRemoveStack;

//   final bool isUpdateStack;

//   bool get isValid => isDrop || isAddStack || isRemoveStack || isUpdateStack;

//   bool get isStack => isAddStack || isRemoveStack;
//   bool get isStart => isDrop || isAddStack || isUpdateStack;
//   bool get isEnd => isRemoveStack;

//   void startOption(FnBuildMixin context, Variable value, Ty ty) {
//     if (!isStart) return;
//     if (ty is! StructTy) return;

//     for (final field in ty.fields) {
//       final val = ty.llty.getField(value, context, field.ident);
//       if (val != null) {
//         if (isDrop) {
//           context.addFree(val);
//         } else if (isAddStack) {
//           ImplStackTy.addStack(context, val);
//         } else if (isUpdateStack) {
//           ImplStackTy.updateStack(context, val);
//         }
//       }
//     }
//   }

//   void endOption(FnBuildMixin context, Variable value) {
//     if (!isEnd) return;

//     for (final field in ty.fields) {
//       final val = ty.llty.getField(value, context, field.ident);
//       if (val != null) {
//         if (isRemoveStack) {
//           ImplStackTy.removeStack(context, val);
//         }
//       }
//     }
//   }
// }

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

      fnContext._fnVariable = fv;
      fnContext._fnScope = llvm.LLVMGetSubprogram(fv.value);
      fnContext._isFnBBContext = true;
      fnContext.instertFnEntryBB();
      onCreated?.call(fnContext);

      final hasRet = fn.getRetTy(fnContext) != BuiltInTy.kVoid;
      fnContext.initFnParamsStart(fv.value, fn.fnSign.fnDecl, fn, extra,
          map: map);

      block.build(fnContext, hasRet: hasRet);

      assert(!hasRet || fnContext._returned || !block.isNotEmpty,
          'error: return.');
      fnContext.ret(null);
    });
    return fv;
  }

  void initFnParamsStart(
      LLVMValueRef fn, FnDecl decl, Fn fnty, Set<AnalysisVariable>? extra,
      {Map<Identifier, Set<AnalysisVariable>> map = const {}}) {
    final sret = AbiFn.initFnParams(this, fn, decl, fnty, extra, map: map);
    if (sret != null) _sret = sret;
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
      var realTy = fnty.getFieldTy(this, p);
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
      ImplStackTy.drop(to, val, test: to._freeAddCache);
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
    ImplStackTy.addStack(this, val);
  }
}
