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
    final addFn = stackImpl.getFnCopy(ty, Identifier.builtIn('addStack'));

    if (addFn == null) {
      Log.e('error addFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      addFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.getBaseValue(context), ty, Identifier.none),
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
    final removeFn = stackImpl.getFnCopy(ty, ident);

    if (removeFn == null) {
      Log.e('error removeFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      removeFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.getBaseValue(context), ty, Identifier.none),
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

    return impl.getFnCopy(ty, fnIdent);
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

abstract class DropImpl {
  static final _dropIdent = Identifier.builtIn('drop');
  static void drop(FnBuildMixin context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final dropImpl = context.getImplWithIdent(ty, Identifier.builtIn('Drop'));
    if (dropImpl == null) return;
    final dropFn = dropImpl.getFnCopy(ty, _dropIdent);

    if (dropFn == null) {
      return;
    }
    AbiFn.fnCallInternal(
      context,
      dropFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.getBaseValue(context), ty, Identifier.none),
      null,
      null,
    );
  }
}

abstract class Clone {
  static final _onCloneIdent = Identifier.builtIn('onClone');
  static final _cloneCom = Identifier.builtIn('Clone');
  static void onClone(FnBuildMixin context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.baseTy;
    }
    final impl = context.getImplWithIdent(ty, _cloneCom);
    if (impl == null) return;
    final onCloneFn = impl.getFnCopy(ty, _onCloneIdent);

    if (onCloneFn == null) {
      return;
    }

    AbiFn.fnCallInternal(
      context,
      onCloneFn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.getBaseValue(context), ty, Identifier.none),
      null,
      null,
    );
  }
}
