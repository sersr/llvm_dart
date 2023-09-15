import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../ast.dart';
import 'llvm_context.dart';
import 'variables.dart';

abstract class ImplStackTy {
  static void addStack(BuildContext context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }
    final stackImpl = context.getImplWithIdent(ty, Identifier.builtIn('Stack'));
    if (stackImpl == null) return;
    var addFn = stackImpl.getFn(Identifier.builtIn('addStack'));
    addFn = addFn?.copyFrom(ty);
    if (addFn == null) {
      Log.e('error addFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      addFn,
      [],
      LLVMConstVariable(variable.load(context, Offset.zero), ty),
      null,
      null,
      Identifier.none,
    );
  }

  static bool isStackCom(BuildContext context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }
    return context.getImplWithIdent(ty, Identifier.builtIn('Stack')) != null;
  }

  static void removeStack(BuildContext context, Variable variable) {
    final ident = Identifier.builtIn('removeStack');
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final stackImpl = context.getImplWithIdent(ty, Identifier.builtIn('Stack'));
    if (stackImpl == null) return;
    var removeFn = stackImpl.getFn(ident);
    removeFn = removeFn?.copyFrom(ty);

    if (removeFn == null) {
      Log.e('error removeFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      removeFn,
      [],
      LLVMConstVariable(variable.load(context, Offset.zero), ty),
      null,
      null,
      Identifier.none,
    );
  }
}

abstract class RefDerefCom {
  static ImplFnMixin? getImplFn(
      BuildContext context, Ty ty, Identifier com, Identifier fnIdent) {
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final impl = context.getImplWithIdent(ty, com);
    if (impl == null) return null;
    var fn = impl.getFn(fnIdent);
    return fn?.copyFrom(ty);
  }

  static Variable getRef(BuildContext context, Variable variable) {
    // 自动解引用
    if (variable is Deref) {
      variable = variable.getDeref(context);
    }

    final fn = getImplFn(context, variable.ty, Identifier.builtIn('Ref'),
        Identifier.builtIn('ref'));
    if (fn == null) return variable;
    final retVariable = fn
        .getRetTy(context)
        .llvmType
        .createAlloca(context, Identifier.none, null);

    final param = LLVMConstVariable(variable.getBaseValue(context), fn.ty);
    param.ident = Identifier.builtIn('self');
    context.compileRun(fn, context, [param], retVariable);

    return retVariable;
  }

  static Variable getDeref(BuildContext context, Variable variable) {
    if (variable is Deref) {
      variable = variable.getDeref(context);
    }

    final fn = getImplFn(context, variable.ty, Identifier.builtIn('Deref'),
        Identifier.builtIn('deref'));
    if (fn == null) return variable;
    final retVariable = fn
        .getRetTy(context)
        .llvmType
        .createAlloca(context, Identifier.none, null);
    final param = LLVMConstVariable(variable.getBaseValue(context), fn.ty);
    param.ident = Identifier.builtIn('self');
    context.compileRun(fn, context, [param], retVariable);

    return retVariable;
  }
}
