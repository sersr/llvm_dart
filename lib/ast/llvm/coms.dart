import '../../abi/abi_fn.dart';
import '../../llvm_core.dart';
import '../ast.dart';
import '../tys.dart';
import 'llvm_context.dart';
import 'variables.dart';

abstract class ImplStackTy {
  static final _stackCom = Identifier.builtIn('Stack');
  static final _addStack = Identifier.builtIn('addStack');
  static final _removeStack = Identifier.builtIn('removeStack');
  static final _updateStack = Identifier.builtIn('updateStack');
  static void _runStackFn(
      FnBuildMixin context, Variable variable, Identifier fnName) {
    variable = variable.defaultDeref(context, Identifier.none);

    var ty = variable.ty;

    final stackImpl = context.getImplWithIdent(ty, _stackCom);

    final fn = stackImpl?.getFnCopy(ty, fnName);

    if (fn == null) {
      _rec(context, variable, (context, val) {
        _runStackFn(context, val, fnName);
      });
      return;
    }
    AbiFn.fnCallInternal(
      context,
      fn,
      Identifier.none,
      [],
      LLVMConstVariable(variable.getBaseValue(context), ty, Identifier.none),
      null,
      null,
    );

    _rec(context, variable, (context, val) {
      _runStackFn(context, val, fnName);
    });
  }

  static bool isStackCom(FlowMixin context, Variable variable) {
    variable = variable.defaultDeref(context, Identifier.none);

    var ty = variable.ty;
    return context.getImplWithIdent(ty, _stackCom) != null;
  }

  static void addStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _addStack);
  }

  static void updateStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _updateStack);
  }

  static void removeStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _removeStack);
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

void _rec(FnBuildMixin context, Variable value,
    void Function(FnBuildMixin context, Variable val) action) {
  final ty = value.ty;
  if (ty is! StructTy) return;

  for (final field in ty.fields) {
    final val = ty.llty.getField(value, context, field.ident);
    if (val != null) {
      action(context, val);
    }
  }
}

abstract class DropImpl {
  static final _dropIdent = Identifier.builtIn('drop');
  static void drop(FnBuildMixin context, Variable variable,
      {bool Function(LLVMValueRef v)? test}) {
    variable = variable.defaultDeref(context, Identifier.none);
    var ty = variable.ty;

    final dropImpl = context.getImplWithIdent(ty, Identifier.builtIn('Drop'));
    final dropFn = dropImpl?.getFnCopy(ty, _dropIdent);

    if (dropFn == null) {
      _rec(context, variable, (c, v) => drop(c, v, test: test));

      return;
    }

    final value = variable.getBaseValue(context);
    if (test != null && test(value)) return;

    AbiFn.fnCallInternal(
      context,
      dropFn,
      Identifier.none,
      [],
      LLVMConstVariable(value, ty, Identifier.none),
      null,
      null,
    );

    _rec(context, variable, (c, v) => drop(c, v, test: test));
  }
}

abstract class Clone {
  static final _onCloneIdent = Identifier.builtIn('onClone');
  static final _cloneCom = Identifier.builtIn('Clone');
  static void onClone(FnBuildMixin context, Variable variable) {
    variable = variable.defaultDeref(context, Identifier.none);
    var ty = variable.ty;

    final impl = context.getImplWithIdent(ty, _cloneCom);
    final onCloneFn = impl?.getFnCopy(ty, _onCloneIdent);

    if (onCloneFn == null) {
      _rec(context, variable, onClone);
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

    _rec(context, variable, onClone);
  }
}
