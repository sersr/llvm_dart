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

  static Variable _getDeref(FnBuildMixin context, Variable variable) {
    for (;;) {
      final v = variable.defaultDeref(context, Identifier.none);
      if (variable == v) break;
      variable = v;
    }
    return variable;
  }

  static void _runStackFn(
      FnBuildMixin context, Variable variable, Identifier fnName,
      {bool Function(LLVMValueRef v)? test}) {
    variable = _getDeref(context, variable);

    var ty = variable.ty;

    final stackImpl =
        context.getImplWith(ty, comIdent: _stackCom, fnIdent: fnName);
    final fn = stackImpl?.getFn(fnName);

    if (fn == null) {
      _rec(context, variable, (context, val) {
        _runStackFn(context, val, fnName);
      });
      return;
    }

    final value = variable.getBaseValue(context);
    if (test != null && test(value)) return;

    AbiFn.fnCallInternal(
      context,
      fn,
      Identifier.none,
      [],
      LLVMConstVariable(value, ty, Identifier.none),
      null,
      null,
    );

    _rec(context, variable, (context, val) {
      _runStackFn(context, val, fnName);
    });
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
