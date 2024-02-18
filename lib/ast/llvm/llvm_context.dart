import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
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

  // ExprTempValue? arrayBuiltin(FnBuildMixin context, Identifier ident,
  //     String fnName, Variable? val, Ty valTy, List<FieldExpr> params) {
  //   if (valTy is ArrayTy && val != null) {
  //     if (fnName == 'getSize') {
  //       final size =
  //           LiteralKind.usize.ty.llty.createValue(ident: '${valTy.size}'.ident);
  //       return ExprTempValue(size);
  //     } else if (fnName == 'toStr') {
  //       final element = valTy.llty.toStr(context, val);
  //       return ExprTempValue(element);
  //     }
  //   }

  //   if (valTy is StructTy) {
  //     if (valTy.ident.src == 'Array') {
  //       if (fnName == 'new') {
  //         if (params.isNotEmpty) {
  //           final first = params.first
  //               .build(context, baseTy: LiteralKind.usize.ty)
  //               ?.variable;

  //           if (first is LLVMLitVariable) {
  //             if (valTy.tys.isNotEmpty) {
  //               final arr = ArrayTy(valTy.tys.values.first, first.value.iValue);

  //               final value = LLVMAllocaProxyVariable(context, (value, _) {
  //                 if (value == null) return;
  //                 value.store(
  //                   context,
  //                   llvm.LLVMConstNull(arr.typeOf(context)),
  //                 );
  //               }, arr, arr.llty.typeOf(context), ident);

  //               return ExprTempValue(value);
  //             }
  //           }
  //         }
  //       }
  //     }
  //   }

  //   return null;
  // }

  final _structTypes = <ListKey, LLVMTypeRef>{};

  LLVMTypeRef createStructType(
      List<LLVMTypeRef> types, List<Ty> tys, String name) {
    final key = ListKey([types, tys, name]);

    return _structTypes.putIfAbsent(key, () {
      final struct =
          llvm.LLVMStructCreateNamed(llvmContext, 'struct_$name'.toChar());
      llvm.LLVMStructSetBody(struct, types.toNative(), types.length, LLVMFalse);
      return struct;
    });
  }
}

class BuildContextImpl extends BuildContext
    with FreeMixin, FlowMixin, FnContextMixin, SretMixin, FnBuildMixin
    implements LogPretty {
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
  void copyBuilderFrom(BuildContext other) {
    if (_builder != null) {
      llvm.LLVMDisposeBuilder(_builder!);
    }
    _ignoreDisposeBuilder = true;
    _builder = other.builder;
  }

  bool _ignoreDisposeBuilder = false;

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

  @override
  VA? getKVImpl<VA>(List<VA>? Function(Tys<LifeCycleVariable> c) map,
      {bool Function(VA v)? test}) {
    return super.getKVImpl(map, test: test) ??
        parent?.getKVImpl(map, test: test);
  }

  @override
  void dispose() {
    if (!_ignoreDisposeBuilder) llvm.LLVMDisposeBuilder(builder);
    super.dispose();

    for (var child in _children) {
      child.dispose();
    }
  }

  @override
  void freeHeapParent(FnBuildMixin to, {FnBuildMixin? from}) {
    final fn = from ?? getLastFnContext();
    assert(fn != null, "error: fn == null.");
    if (fn == null || fn == this) return;

    var current = parent;

    while (current != null) {
      current.freeHeapCurrent(to);
      if (current == fn) return;
      current = current.parent;
    }
  }

  bool get _isEmpty =>
      currentStmts.isEmpty && _children.every((element) => element._isEmpty);

  @override
  String toString() {
    return logPretty(0, ignorePath: false).$1.logPretty();
  }

  @override
  (Map, int) logPretty(int level, {bool ignorePath = true}) {
    final children = _children.where((element) => !element._isEmpty).toList();
    if (children.isEmpty && currentStmts.isEmpty) return ({}, level);

    final map = {
      if (currentFn == null && !ignorePath) "path": block?.blockStart.basePath,
      if (currentFn != null) "fn": currentFn?.fnName.path,
      if (currentStmts.isNotEmpty) "stmts": currentStmts,
      if (children.isNotEmpty) "children": children,
    };
    return (map, level);
  }
}
