part of 'build_context_mixin.dart';

mixin FreeMixin on BuildContext {
  void freeHeap();

  void freeHeapParent(FnBuildMixin to, {FnBuildMixin? from});
  void freeHeapCurrent(FnBuildMixin to);

  void removeVal(Variable? val) {
    if (val == null || val is! StoreVariable) return;
    _ptrMap.remove(val.getBaseValue(this));
  }

  /// 以`alloca`作为`key`
  final _ptrMap = <LLVMValueRef, LLVMAllocaVariable>{};

  @override
  void addFree(LLVMAllocaVariable val) {
    _ptrMap[val.alloca] = val;
  }
}
