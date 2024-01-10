import 'package:nop/nop.dart';

import '../../abi/abi_fn.dart';
import '../ast.dart';
import '../tys.dart';
import 'llvm_context.dart';
import 'variables.dart';

abstract class ImplStackTy {
  static void addStack(FnBuildMixin context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }
    final stackImpl = context.getImplWithIdent(ty, Identifier.builtIn('Stack'));
    if (stackImpl == null) return;
    var addFn = stackImpl.getFn(ty, Identifier.builtIn('addStack'));
    if (addFn == null) {
      Log.e('error addFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      addFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.load(context), ty, Identifier.none),
      null,
      null,
    );
  }

  static bool isStackCom(FreeMixin context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }
    return context.getImplWithIdent(ty, Identifier.builtIn('Stack')) != null;
  }

  static void removeStack(FnBuildMixin context, Variable variable) {
    final ident = Identifier.builtIn('removeStack');
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final stackImpl = context.getImplWithIdent(ty, Identifier.builtIn('Stack'));
    if (stackImpl == null) return;
    var removeFn = stackImpl.getFn(ty, ident);

    if (removeFn == null) {
      Log.e('error removeFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      removeFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.load(context), ty, Identifier.none),
      null,
      null,
    );
  }
}

abstract class RefDerefCom {
  static ImplFnMixin? getImplFn(
      Tys context, Ty ty, Identifier com, Identifier fnIdent) {
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final impl = context.getImplWithIdent(ty, com);
    if (impl == null) return null;

    return impl.getFn(ty, fnIdent);
  }

  static Variable getDeref(FnBuildMixin context, Variable variable) {
    final fn = getImplFn(context, variable.ty, Identifier.builtIn('Deref'),
        Identifier.builtIn('deref'));

    if (fn == null) return variable;

    final param = LLVMAllocaVariable(variable.getBaseValue(context),
        variable.ty, variable.ty.typeOf(context), Identifier.self);
    return context.compileRun(fn, [param]) ?? variable;
  }

  static void loopGetDeref(
      FnBuildMixin context, Variable variable, bool Function(Variable) action) {
    if (action(variable)) return;
    for (;;) {
      final v =
          getDeref(context, variable).defaultDeref(context, Identifier.none);
      if (action(v)) break;
      if (variable == v) break;
      variable = v;
    }
  }
}
