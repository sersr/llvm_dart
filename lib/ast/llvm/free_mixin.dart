part of 'build_context_mixin.dart';

mixin FreeMixin on BuildContext {
  void freeHeap();

  void freeHeapParent(FnBuildMixin to, {FnBuildMixin? from});
  void freeHeapCurrent(FnBuildMixin to);

  bool removeVal(Variable? val) {
    if (val == null || val is! StoreVariable) return false;
    final key = val.getBaseValue(this);
    final value = getKV(
      (c) => switch (c) {
        FnBuildMixin c => [c._ptrMap[key]],
        var _ => null,
      },
    );

    return value != null;
  }

  /// 以`alloca`作为`key`
  final _ptrMap = <LLVMValueRef, Variable>{};

  @override
  void addFree(Variable val) {
    _ptrMap[val.getBaseValue(this)] = val;
  }
}
