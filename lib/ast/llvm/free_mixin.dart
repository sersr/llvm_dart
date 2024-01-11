part of 'build_context_mixin.dart';

mixin FreeMixin on BuildContext {
  /// todo:
  void autoAddFreeHeap(Variable variable) {
    if (ImplStackTy.isStackCom(this, variable)) {
      _stackComVariables.add(variable);
    }
  }

  void autoAddStackCom(Variable variable) {
    if (ImplStackTy.isStackCom(this, variable)) {
      _stackComVariables.add(variable);
      var ty = variable.ty;
      if (ty is RefTy) {
        ty = ty.baseTy;
      }
      variable = variable.defaultDeref(this, variable.ident);

      if (ty is StructTy) {
        for (var field in ty.fields) {
          final val = ty.llty.getField(variable, this, field.ident);
          if (val != null) autoAddStackCom(val);
        }
      }
    }
  }

  final _stackComVariables = <Variable>{};

  void removeFreeVariable(Variable variable) {
    if (!_stackComVariables.remove(variable)) {
      addStackCom(variable);
    }
  }

  void freeHeap();
  void addStackCom(Variable val);

  /// drop
  final _freeVal = <Variable>[];

  @override
  void addFree(Variable val) {
    _freeVal.add(val);
  }

  @override
  void dropAll() {
    for (var val in _freeVal) {
      final ty = val.ty;
      final ident = Identifier.builtIn('drop');
      final fn = getImplFnForStruct(ty, ident);
      final fnv = fn?.genFn();
      if (fn == null || fnv == null) continue;
      LLVMValueRef v;

      // fixme: remove
      if (val.ty is BuiltInTy) {
        v = val.load(this);
      } else {
        v = val.getBaseValue(this);
      }
      final type = fn.llty.createFnType(this);
      llvm.LLVMBuildCall2(
          builder, type, fnv.getBaseValue(this), [v].toNative(), 1, unname);
    }
  }
}
