import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../expr.dart';
import '../memory.dart';
import '../tys.dart';
import 'build_methods.dart';
import 'coms.dart';
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
  set builder(LLVMBuilderRef b);
  Abi get abi;

  @override
  FnBuildMixin? getLastFnContext();
  FnBuildMixin createNewRunContext();
  FnBuildMixin createChildContext();
}

mixin SretMixin on BuildContext {
  //
  RawIdent? _sertOwner;

  /// todo:
  StoreVariable? sretFromVariable(Identifier? nameIdent, Variable variable) {
    return _sretFromVariable(this, nameIdent, variable);
  }

  static StoreVariable? _sretFromVariable(
      BuildContext context, Identifier? nameIdent, Variable variable) {
    final fnContext = context.getLastFnContext()!;
    final fnty = fnContext._fn?.ty as Fn?;
    if (fnty == null) return null;

    StoreVariable? fnSret;
    fnSret = fnContext.sret;
    if (fnSret == null) return null;

    nameIdent ??= variable.ident;
    final owner = nameIdent.toRawIdent;
    if (!fnty.returnVariables.contains(owner)) {
      return null;
    }

    if (fnContext._sertOwner == null &&
        variable is LLVMAllocaDelayVariable &&
        !variable.created) {
      variable.initProxy(proxy: fnSret);
      fnContext._sertOwner = owner;
      return variable;
    } else {
      fnSret.storeVariable(context, variable);
      return fnSret;
    }
  }
}
