import '../../abi/abi_fn.dart';
import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../memory.dart';
import '../tys.dart';
import 'build_context_mixin.dart';
import 'build_methods.dart';
import 'intrinsics.dart';
import 'variables.dart';

export 'build_context_mixin.dart';

final class Configs {
  Configs({
    required this.isGnu,
    required this.isMsvc,
    required this.abi,
    required this.targetTriple,
    required this.isDebug,
  });

  final bool isGnu;
  final bool isMsvc;
  final Abi abi;
  final String targetTriple;
  final bool isDebug;
  bool get isWin => abi.isWindows;

  @override
  String toString() {
    return '''target: $targetTriple
abi: $abi, isWin: ${abi.isWindows}
isMsvc: $isMsvc
isGnu: $isGnu
isDebug: $isDebug''';
  }
}

class RootBuildContext with Tys<Variable>, LLVMTypeMixin, Consts {
  RootBuildContext({
    this.name = 'root',
    required this.configs,
  });

  bool _initContext = false;
  void init() {
    assert(!_initContext);
    _initContext = true;
    llvmContext = llvm.LLVMContextCreate();
    module = llvm.LLVMModuleCreateWithNameInContext(name.toChar(), llvmContext);
    tm = llvm.createTarget(module, configs.targetTriple.toChar());

    void add(int lv, String name, int size) {
      llvm.LLVMAddFlag(module, lv, name.toChar(), size);
    }

    if (configs.isWin && configs.isMsvc) {
      add(2, "CodeView", 1);
      // add(8, "PIC Level", 2);
      // add(8, "PIE Level", 2);
    } else {
      add(8, "Dwarf Version", 2);
    }

    add(2, "Debug Info Version", 3);
  }

  final Configs configs;

  @override
  late final GlobalContext global;

  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMTargetMachineRef tm;

  final String name;

  Abi get abi => configs.abi;
  bool get isDebug => configs.isDebug;

  final maps = <String, FunctionDeclare>{};

  final _globalStrings = <String, LLVMValueRef>{};
  LLVMValueRef globalStringPut(String key, LLVMValueRef Function() data) {
    return _globalStrings.putIfAbsent(key, data);
  }

  void dispose() {
    llvm.LLVMDisposeModule(module);
    llvm.LLVMDisposeTargetMachine(tm);
    llvm.LLVMContextDispose(llvmContext);
    llvmMalloc.releaseAll();
  }

  @override
  String get currentPath => throw UnimplementedError();
}

class BuildContextImpl extends BuildContext
    with FreeMixin, FlowMixin, FnContextMixin, SretMixin, FnBuildMixin {
  BuildContextImpl._baseChild(BuildContextImpl this.parent, this.currentPath)
      : root = parent.root {
    init(parent!);
  }

  BuildContextImpl._compileRun(BuildContextImpl this.parent, this.currentPath)
      : root = parent.root;

  BuildContextImpl.root(this.root, this.currentPath) : parent = null;

  @override
  final BuildContextImpl? parent;
  @override
  final RootBuildContext root;

  @override
  Abi get abi => root.abi;

  @override
  final String currentPath;

  @override
  GlobalContext get global => root.global;

  LLVMBuilderRef? _builder;
  @override
  LLVMBuilderRef get builder =>
      _builder ??= llvm.LLVMCreateBuilderInContext(llvmContext);

  @override
  set builder(LLVMBuilderRef v) {
    if (_builder != null) {
      llvm.LLVMDisposeBuilder(_builder!);
    }
    _builder = v;
  }

  final List<BuildContextImpl> _children = [];

  @override
  BuildContextImpl createChildContext() {
    final child = BuildContextImpl._baseChild(this, currentPath);
    _children.add(child);
    return child;
  }

  @override
  BuildContextImpl createNewRunContext() {
    return BuildContextImpl._compileRun(this, currentPath);
  }

  @override
  BuildContextImpl? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  void log(int level) {
    print('${' ' * level}$currentPath');
    level += 2;
    for (var child in _children) {
      child.log(level);
    }
  }

  /// override: Tys
  @override
  void pushAllTy(Iterable<Ty> all) {
    for (var item in all) {
      assert(item.currentContext == null);
      item.currentContext = this;
      item.build();
    }
  }

  @override
  VA? getKVImpl<K, VA>(
      K k, Map<K, List<VA>> Function(Tys<LifeCycleVariable> c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return super.getKVImpl(k, map, handler: handler, test: test) ??
        parent?.getKVImpl(k, map, handler: handler, test: test);
  }

  @override
  Variable? getVariableImpl(Identifier ident) {
    return super.getVariableImpl(ident) ?? parent?.getVariableImpl(ident);
  }

  @override
  void dispose() {
    llvm.LLVMDisposeBuilder(builder);
    super.dispose();

    for (var child in _children) {
      child.dispose();
    }
  }
}
