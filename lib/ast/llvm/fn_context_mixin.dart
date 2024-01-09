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

  void _updateDebugFn(FnContextMixin parent, FnContextMixin debug) {
    builder = parent.builder;
    _fnValue = parent.fnValue;
    assert(dBuilder == null);

    // 一个函数只能和一个文件绑定，在同一个文件中，可以取巧，使用同一个file scope
    if (parent.currentPath == debug.currentPath) {
      init(parent);
      _fnScope = parent.scope;
    }
    isFnBBContext = true;
  }

  bool _inRunMode = false;
  LLVMBasicBlock? _runBbAfter;
  Variable? _compileRetValue;

  /// 同一个文件支持跳转
  bool compileRunMode(Fn fn) => currentPath == fn.currentContext!.currentPath;

  bool _updateRunAfter(Variable? val, FlowMixin current) {
    if (!_inRunMode) return false;
    _compileRetValue = val;
    var block = _runBbAfter;
    if (current != this) {
      block = buildSubBB(name: '_new_ret');
      _runBbAfter = block;
    }

    if (block != null) current._br(block.context);
    return true;
  }
}
