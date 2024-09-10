import '../../abi/abi_fn.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../expr.dart';
import '../tys.dart';
import '../llvm/llvm_context.dart';
import '../llvm/variables.dart';

abstract class ImplStackTy {
  static final _stackCom = 'Stack'.ident;
  static final _addStack = 'addStack'.ident;
  static final _replaceStack = 'replaceStack'.ident;
  static final _removeStack = 'removeStack'.ident;
  static final _updateStack = 'updateStack'.ident;
  static final _srcIdent = 'src'.ident;

  static Variable _getDeref(FnBuildMixin context, Variable variable) {
    for (;;) {
      if (variable.ty is RefTy) {
        break;
      }

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
    if (variable.isIgnore) return false;
    if (!ignoreRef) {
      variable = _getDeref(context, variable);
    }

    var ty = variable.ty;

    final fn = getImplFn(context, ty, _stackCom, fnName);

    if (fn == null) {
      if (recursive) {
        _rec(
          context,
          variable,
          (context, val) => _runStackFn(context, val, fnName),
          (context, ty) => _checkStack(context, ty, _stackCom, fnName),
        );
      }
      return false;
    }
    if (test != null && test(variable.getBaseValue(context))) return false;

    final fnValue = fn.genFn(ignoreFree);
    AbiFn.fnCallInternal(
      context: context,
      fn: fnValue,
      decl: fn.fnDecl,
      struct: variable,
      valArgs: args,
      ignoreFree: ignoreFree,
    );

    if (recursive) {
      _rec(
        context,
        variable,
        (context, val) => _runStackFn(context, val, fnName),
        (context, ty) => _checkStack(context, ty, _stackCom, fnName),
      );
    }

    return true;
  }

  static bool hasStack(FnBuildMixin context, Ty ty) {
    if (ty is RefTy && !ty.isPointer) {
      ty = ty.baseTy;
    }

    final stackImpl = context.getImplWith(ty, comIdent: _stackCom);
    if (stackImpl != null) return true;

    if (ty is StructTy) {
      for (var field in ty.fields) {
        final ty = field.grt(context);
        final exist = hasStack(context, ty);
        if (exist) {
          return true;
        }
      }
    } else if (ty is EnumTy) {
      for (var item in ty.variants) {
        if (hasStack(context, item)) return true;
      }
    }

    return false;
  }

  static void addStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _addStack, ignoreRef: true);
  }

  static void updateStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _updateStack, ignoreRef: true);
  }

  static void removeStack(FnBuildMixin context, Variable variable) {
    _runStackFn(context, variable, _removeStack, ignoreRef: true);
  }

  static void replaceStack(
      FnBuildMixin context, Variable target, Variable src) {
    final fn = getImplFn(context, target.ty, _stackCom, _replaceStack);

    final srcIdent = fn?.fnDecl.fields.firstOrNull?.ident ?? _srcIdent;
    var arg = LLVMConstVariable(src.getBaseValue(context), src.ty, srcIdent);

    var hasFn = false;
    if (target.ty.isTy(src.ty)) {
      hasFn = _runStackFn(
        context,
        target,
        _replaceStack,
        recursive: false,
        ignoreFree: true,
        ignoreRef: true,
        args: [arg],
      );
    }

    if (!hasFn) {
      addStack(context, src);
      removeStack(context, target);
    } else {
      _rec(
        context,
        src,
        (context, val) => addStack(context, val),
        (context, ty) => _checkStack(context, ty, _stackCom, _addStack),
      );

      _rec(
        context,
        target,
        (context, val) => removeStack(context, val),
        (context, ty) => _checkStack(context, ty, _stackCom, _removeStack),
      );
    }
  }

  static void drop(FnBuildMixin context, Variable variable,
      bool Function(LLVMValueRef v)? test) {
    ImplStackTy._runStackFn(context, variable, _removeStack, test: test);
  }
}

void _rec(
    FnBuildMixin context,
    Variable value,
    void Function(FnBuildMixin context, Variable val) action,
    bool Function(FnBuildMixin context, Ty ty) testTy) {
  final ty = value.ty;
  if (ty is StructTy) {
    for (final field in ty.fields) {
      final val = ty.llty.getField(value, context, field.ident);
      if (val != null) {
        action(context, val);
      }
    }
  } else if (ty is EnumTy) {
    final newVariants = ty.variants.where((e) => testTy(context, e)).toList();
    if (newVariants.isEmpty) return;

    final after = context.buildSubBB(name: 'match_after');
    var indexValue = ty.llty.loadIndex(context, value);

    final ss = llvm.LLVMBuildSwitch(
        context.builder, indexValue, after.bb, newVariants.length);

    final llPty = ty.llty;

    for (var i = 0; i < newVariants.length; i++) {
      final item = newVariants[i];

      LLVMBasicBlock childBb;
      childBb = context.buildSubBB(name: 'match_bb_$i');
      context.appendBB(childBb);

      final v = item.llty.checkStack(
          childBb.context, value, (v) => action(childBb.context, v));

      llvm.LLVMAddCase(ss, llPty.getIndexValue(context, v), childBb.bb);
      childBb.context.br(after.context);
    }

    context.insertPointBB(after);
  }
}

bool _checkStack(
    FnBuildMixin context, Ty ty, Identifier com, Identifier fnIdent) {
  if (ty is StructTy) {
    for (final field in ty.fields) {
      final fieldTy = field.grtOrT(context);
      if (fieldTy != null) {
        if (_checkStack(context, fieldTy, com, fnIdent)) return true;
      }
    }
  } else if (ty is EnumTy) {
    final variants = ty.variants;
    for (var item in variants) {
      if (_checkStack(context, item, com, fnIdent)) return true;
    }
  }

  return getImplFn(context, ty, com, fnIdent) != null;
}

ImplFnMixin? getImplFn(Tys context, Ty ty, Identifier com, Identifier fnIdent) {
  final fn =
      context.getImplWith(ty, comIdent: com, fnIdent: fnIdent)?.getFn(fnIdent);
  if (fn != null) return fn;
  final current = ty.currentContext;

  if (current == context || current == null) return null;
  return current
      .getImplWith(ty, comIdent: com, fnIdent: fnIdent)
      ?.getFn(fnIdent);
}

abstract class RefDerefCom {
  static final _derefComIdent = 'Deref'.ident;
  static final _derefIdent = 'deref'.ident;

  static Variable getDeref(FnBuildMixin context, Variable variable) {
    var ty = variable.ty;
    if (ty is RefTy) {
      ty = ty.parent;
    }

    final fn = getImplFn(context, ty, _derefComIdent, _derefIdent);

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

abstract class ArrayOpImpl {
  static final _arrayOpCom = 'ArrayOp'.ident;
  static final _arrayOpIdent = 'elementAt'.ident;
  static final _index = 'index'.ident;

  static ExprTempValue? elementAt(
      FnBuildMixin context, Variable variable, Identifier ident, Expr param) {
    final fn = getImplFn(context, variable.ty, _arrayOpCom, _arrayOpIdent);
    if (fn == null) return null;
    final pIdent = fn.fnDecl.fields.firstOrNull?.ident ?? _index;

    final fnValue = fn.genFn();
    return AbiFn.fnCallInternal(
      context: context,
      fn: fnValue,
      decl: fn.fnDecl,
      params: [FieldExpr(param, pIdent)],
      struct: variable,
    );
  }

  static Ty? elementAtTy(Tys context, Ty struct) {
    final fn = getImplFn(context, struct, _arrayOpCom, _arrayOpIdent);
    if (fn == null) return null;

    return fn.fnDecl.getRetTyOrT(context);
  }
}
