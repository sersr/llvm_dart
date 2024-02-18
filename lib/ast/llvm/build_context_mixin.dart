import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../builders/coms.dart';
import '../expr.dart';
import '../memory.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'intrinsics.dart';
import 'variables.dart';

part 'flow_mixin.dart';
part 'fn_build_mixin.dart';
part 'fn_context_mixin.dart';
part 'free_mixin.dart';

class LLVMBasicBlock {
  LLVMBasicBlock(this.bb, this.context, this.inserted);
  final LLVMBasicBlockRef bb;
  final FnBuildMixin context;
  String? label;
  LLVMBasicBlock? parent;
  bool inserted = false;
}

abstract class BuildContext
    with
        Tys<Variable>,
        LLVMTypeMixin,
        BuildMethods,
        Consts,
        DebugMixin,
        OverflowMath,
        StoreLoadMixin,
        Cast {
  void copyBuilderFrom(BuildContext other);
  Abi get abi;

  @override
  bool get isGlobal => getLastFnContext() == null;

  @override
  FnBuildMixin? getLastFnContext();
  FnBuildMixin createNewRunContext();
  FnBuildMixin createChildContext();
}

mixin SretMixin on BuildContext {
  /// todo:
  StoreVariable? sretFromVariable(Identifier? nameIdent, Variable variable) {
    final fnContext = getLastFnContext()!;
    final fnty = fnContext.currentFn!;
    if (fnty.fnDecl.isVoidRet(this)) return null;

    nameIdent ??= variable.ident;
    final owner = nameIdent.toRawIdent;
    if (!fnty.returnVariables.contains(owner)) {
      return null;
    }

    StoreVariable? fnSret;
    fnSret = fnContext.sret ?? fnContext.compileRetValue;
    if (fnSret == null) return null;

    final ty = fnSret.ty;

    if (variable is LLVMAllocaProxyVariable && !variable.created) {
      variable.initProxy(proxy: fnSret);
    } else {
      fnSret.store(this, variable.load(this));
    }

    return LLVMAllocaVariable(fnSret.alloca, ty, ty.typeOf(this), nameIdent);
  }
}
