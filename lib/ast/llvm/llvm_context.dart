import 'dart:io';

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

class RootBuildContext with Tys<Variable>, LLVMTypeMixin, Consts {
  RootBuildContext(
      {this.abi = Abi.arm64, String name = 'root', String? targetTriple}) {
    llvmContext = llvm.LLVMContextCreate();
    module = llvm.LLVMModuleCreateWithNameInContext(name.toChar(), llvmContext);
    if (targetTriple != null) {
      tm = llvm.createTarget(module, targetTriple.toChar());
    } else {
      final tt = llvm.LLVMGetDefaultTargetTriple();
      tm = llvm.createTarget(module, tt);
      llvm.LLVMDisposeMessage(tt);
    }

    final info = "Debug Info Version";

    void add(int lv, String name, int size) {
      final (namePointer, nameLength) = name.toNativeUtf8WithLength();
      llvm.LLVMAddModuleFlag(module, lv, namePointer, nameLength,
          llvm.LLVMValueAsMetadata(constI32(size)));
    }

    if (Platform.isWindows) {
      add(1, "CodeView", 1);
    } else {
      final version = "Dwarf Version";
      add(6, version, 2);
    }

    add(1, info, 3);
  }

  @override
  Tys<LifeCycleVariable> defaultImport(String path) {
    throw UnimplementedError();
  }

  @override
  late final GlobalContext importHandler;

  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMTargetMachineRef tm;
  final Abi abi;

  final maps = <String, FunctionDeclare>{};

  final _globalStrings = <String, LLVMValueRef>{};
  LLVMValueRef globalStringPut(String key, LLVMValueRef Function() data) {
    return _globalStrings.putIfAbsent(key, data);
  }

  void dispose() {
    llvm.LLVMDisposeModule(module);
    llvm.LLVMDisposeTargetMachine(tm);
    llvm.LLVMContextDispose(llvmContext);
  }
}

class BuildContextImpl extends BuildContext
    with FreeMixin, FlowMixin, FnContextMixin, SretMixin, FnBuildMixin {
  BuildContextImpl._baseChild(BuildContextImpl this.parent)
      : root = parent.root {
    init(parent!);
  }

  BuildContextImpl._compileRun(BuildContextImpl this.parent)
      : root = parent.root;

  BuildContextImpl.root(this.root) : parent = null;

  @override
  final BuildContextImpl? parent;
  @override
  final RootBuildContext root;

  @override
  Abi get abi => root.abi;

  @override
  String? get currentPath => super.currentPath ??= parent?.currentPath;

  @override
  GlobalContext get importHandler => root.importHandler;

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

  final List<BuildContextImpl> children = [];

  @override
  BuildContextImpl defaultImport(String path) {
    final child = BuildContextImpl.root(root);
    child.currentPath = path;
    children.add(child);
    if (dBuilder != null) {
      child.debugInit();
    }
    return child;
  }

  @override
  BuildContextImpl createChildContext() {
    final child = BuildContextImpl._baseChild(this);
    children.add(child);
    return child;
  }

  @override
  BuildContextImpl createNewRunContext() {
    return BuildContextImpl._compileRun(this);
  }

  @override
  BuildContextImpl? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  void log(int level) {
    print('${' ' * level}$currentPath');
    level += 2;
    for (var child in children) {
      child.log(level);
    }
  }

  /// override: Tys
  @override
  void pushAllTy(Map<Object, Ty> all) {
    super.pushAllTy(all);
    for (var item in all.values) {
      item.currentContext = this;
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

  void dispose() {
    _dispose();
    llvmMalloc.releaseAll();
  }

  void _dispose() {
    llvm.LLVMDisposeBuilder(builder);
    for (var child in children) {
      child._dispose();
    }
  }
}
