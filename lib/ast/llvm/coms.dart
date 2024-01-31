import '../../abi/abi_fn.dart';
import '../../llvm_core.dart';
import '../ast.dart';
import '../tys.dart';
import 'llvm_context.dart';
import 'variables.dart';

abstract class ImplStackTy {
  static final _stackCom = Identifier.builtIn('Stack');
  static final _addStack = Identifier.builtIn('addStack');
  static final _replaceStack = Identifier.builtIn('replaceStack');
  static final _removeStack = Identifier.builtIn('removeStack');
  static final _updateStack = Identifier.builtIn('updateStack');

  static Variable _getDeref(FnBuildMixin context, Variable variable) {
    for (;;) {
      final v = variable.defaultDeref(context, Identifier.none);
      if (variable == v) break;
      variable = v;
    }
    return variable;
  }

  static bool _runStackFn(
      FnBuildMixin context, Variable variable, Identifier fnName,
      {bool Function(LLVMValueRef v)? test,
      List<Variable> args = const [],
      bool ignoreFree = false,
      bool ignoreRef = false,
      bool recursive = true}) {
    if (!ignoreRef) {
      variable = _getDeref(context, variable);
    }

    var ty = variable.ty;

    final stackImpl =
        context.getImplWith(ty, comIdent: _stackCom, fnIdent: fnName);
    final fn = stackImpl?.getFn(fnName);

    if (fn == null) {
      if (recursive) {
        _rec(context, variable, (context, val) {
          _runStackFn(context, val, fnName);
        });
      }
      return false;
    }

    final value = variable.getBaseValue(context);
    if (test != null && test(value)) return false;

    AbiFn.fnCallInternal(
      context,
      fn,
      Identifier.none,
      [],
      valArgs: args,
      ignoreFree: ignoreFree,
      LLVMConstVariable(value, ty, Identifier.none),
      null,
      null,
    );

    if (recursive) {
      _rec(context, variable, (context, val) {
        _runStackFn(context, val, fnName);
      });
    }

    return true;
  }

  static void addStack(FnBuildMixin context, Variable variable,
      {bool ignoreRef = false}) {
    _runStackFn(context, variable, _addStack, ignoreRef: ignoreRef);
  }

  static void updateStack(FnBuildMixin context, Variable variable,
      {bool ignoreRef = false}) {
    _runStackFn(context, variable, _updateStack, ignoreRef: ignoreRef);
  }

  static void removeStack(FnBuildMixin context, Variable variable,
      {bool ignoreRef = false}) {
    _runStackFn(context, variable, _removeStack, ignoreRef: ignoreRef);
  }

  static void replaceStack(FnBuildMixin context, Variable target, Variable src,
      {bool ignoreRef = false}) {
    final hasFn = target.ty.isTy(src.ty) &&
        _runStackFn(
          context,
          target,
          _replaceStack,
          recursive: false,
          ignoreFree: true,
          ignoreRef: ignoreRef,
          args: [
            LLVMConstVariable(
                src.getBaseValue(context), src.ty, Identifier.builtIn('src')),
          ],
        );

    if (!hasFn) {
      addStack(context, src, ignoreRef: ignoreRef);
      removeStack(context, target, ignoreRef: ignoreRef);
    } else {
      if (!ignoreRef) {
        src = _getDeref(context, src);
      }
      _rec(context, src, (context, val) {
        addStack(context, val, ignoreRef: ignoreRef);
      });

      if (!ignoreRef) {
        target = _getDeref(context, target);
      }
      _rec(context, target, (context, val) {
        removeStack(context, val, ignoreRef: ignoreRef);
      });
    }
  }

  static void drop(FnBuildMixin context, Variable variable,
      {bool Function(LLVMValueRef v)? test}) {
    ImplStackTy._runStackFn(context, variable, ImplStackTy._removeStack,
        test: test);
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

abstract class RefDerefCom {
  static ImplFnMixin? getImplFn(
      Tys context, Ty ty, Identifier com, Identifier fnIdent) {
    if (ty is RefTy) {
      ty = ty.baseTy;
    }

    final impl = context.getImplWith(ty, comIdent: com, fnIdent: fnIdent);
    if (impl == null) return null;

    return impl.getFn(fnIdent);
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
