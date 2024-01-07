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

    /// 内部方法不使用
    final currentFn = context.getLastFnContext()!.runFn;
    if (currentFn is ImplFn && currentFn.ty == ty) return null;

    var fn = impl.getFn(fnIdent);
    return fn?.copyFrom(ty);
  }

  static Variable getDeref(BuildContext context, Variable variable) {
    final fn = getImplFn(context, variable.ty, Identifier.builtIn('Deref'),
        Identifier.builtIn('deref'));

    if (fn == null) return variable;

    final param = LLVMAllocaVariable(variable.ty,
        variable.getBaseValue(context), variable.ty.typeOf(context));
    param.ident = Identifier.self;
    return context.compileRun(fn, context, [param]) ?? variable;
  }

  static void loopGetDeref(
      BuildContext context, Variable variable, bool Function(Variable) action) {
    if (action(variable)) return;
    for (;;) {
      final v = getDeref(context, variable).defaultDeref(context);
      if (action(v)) break;
      if (variable == v) break;
      variable = v;
    }
  }
}
