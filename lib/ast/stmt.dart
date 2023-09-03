import 'dart:ffi';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'context.dart';
import 'expr.dart';
import 'llvm/variables.dart';
import 'memory.dart';

class LetStmt extends Stmt {
  LetStmt(this.isFinal, this.ident, this.nameIdent, this.rExpr, this.ty);
  final Identifier ident;
  final Identifier nameIdent;
  final Expr? rExpr;
  final PathTy? ty;
  final bool isFinal;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    rExpr?.incLevel(count);
  }

  @override
  Stmt clone() {
    return LetStmt(isFinal, ident, nameIdent, rExpr?.clone(), ty);
  }

  @override
  String toString() {
    final tyy = ty == null ? '' : ' : $ty';
    final rE = rExpr == null ? '' : ' = $rExpr';

    return '${pad}let $nameIdent$tyy$rE';
  }

  @override
  void build(BuildContext context) {
    final realTy = ty?.grt(context);
    ExprTempValue? val = LiteralExpr.run(() {
      return rExpr?.build(context);
    }, realTy);

    context.diSetCurrentLoc(nameIdent.offset);

    final tty = realTy ?? val?.ty;
    if (tty != null) {
      final variable = val?.variable;
      if (variable is LLVMLitVariable) {
        if (tty is BuiltInTy) {
          if (isFinal) {
            context.pushVariable(nameIdent, variable);
            return;
          }

          final alloca = variable.createAlloca(context, nameIdent, tty);

          alloca.create(context);

          alloca.isTemp = false;
          context.pushVariable(nameIdent, alloca);
          return;
        }
        // error
      }

      StoreVariable? alloca;
      final (sret, delayAlloca) = context.sretVariable(nameIdent, variable);

      /// 当前的变量是 sret 时才有效
      if (sret != null) {
        alloca = delayAlloca;
        delayAlloca?.ident = nameIdent;
      }

      if (variable is StoreVariable && variable.isTemp) {
        variable.isTemp = false;
        variable.ident = nameIdent;
        context.setName(variable.alloca, nameIdent.src);
        context.pushVariable(nameIdent, variable);
        return;
        // } else if (variable is LLVMAllocaVariable && variable.ty is StructTy) {
        //   alloca = tty.llvmType.createAlloca(context, nameIdent);
        //   final rValue = variable.load(context);
        //   alloca.store(context, rValue);
      }

      bool wrapRef = variable?.isRef == true;
      // if (alloca == null) {
      //   if (wrapRef) {
      //     if (tty is BuiltInTy) {
      //       alloca = tty.llvmType.createAlloca(context, nameIdent);
      //     } else {
      //       alloca = RefTy(tty)
      //           .llvmType
      //           .createAlloca(context, nameIdent, isPointer: false);
      //     }
      //   } else {
      //     alloca = tty.llvmType.createAlloca(context, nameIdent);
      //   }
      // }
      alloca ??= tty.llvmType.createAlloca(context, nameIdent, null);

      LLVMValueRef? rValue;
      if (variable != null) {
        if (variable is LLVMAllocaDelayVariable) {
          variable.create(context);
        }
        if (wrapRef) {
          rValue = variable.getBaseValue(context);
        } else {
          rValue = variable.load(context, val!.currentIdent.offset);
        }
      }
      if (rValue != null) {
        alloca.store(context, rValue, nameIdent.offset);
      }

      alloca.isTemp = false;
      context.pushVariable(nameIdent, alloca);
    }
  }

  @override
  List<Object?> get props => [ident, nameIdent, ty, rExpr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final v = LiteralExpr.run(() {
      return rExpr?.analysis(context);
    }, realTy);

    if (v == null) return;
    final value = v.copy(ty: realTy, ident: nameIdent);
    context.pushVariable(nameIdent, value);
  }
}

class ExprStmt extends Stmt {
  ExprStmt(this.expr);
  final Expr expr;
  @override
  Stmt clone() {
    return ExprStmt(expr.clone());
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    expr.incLevel(count);
  }

  @override
  String toString() {
    if (expr is FnExpr) return '$expr';
    return '$pad$expr';
  }

  @override
  void build(BuildContext context) {
    expr.build(context);
  }

  @override
  List<Object?> get props => [expr];

  @override
  void analysis(AnalysisContext context) {
    expr.analysis(context);
  }
}

class StaticStmt extends Stmt {
  StaticStmt(this.ident, this.expr, this.ty, this.isConst);
  final bool isConst;
  @override
  Stmt clone() {
    return StaticStmt(ident, expr.clone(), ty, isConst).._done = _done;
  }

  final Identifier ident;
  final PathTy? ty;
  final Expr expr;

  @override
  String toString() {
    final y = ty == null ? '' : ' : $ty';
    return '${pad}static $ident$y = $expr';
  }

  bool _done = false;

  bool _run = false;
  @override
  void build(BuildContext context) {
    if (_run) return;
    final realTy = ty?.grtOrT(context);
    if (ty != null && realTy == null) return;

    final e = LiteralExpr.run(() => expr.build(context), realTy);

    final rty = realTy ?? e?.ty;
    final val = e?.variable;
    if (e == null || val == null) return;
    // if (rty != null && e.ty != rty) {
    //   Log.e('$ty = ${e.ty}');
    //   return;
    // }
    final y = rty ?? e.ty;
    final type = y.llvmType.createType(context);

    context.diSetCurrentLoc(ident.offset);

    LLVMValueRef llValue;
    Variable v;
    final data = val.getBaseValue(context);
    // final isStr = y is BuiltInTy && y.ty == LitKind.kStr;

    // if (isStr) {
    //     }

    llValue = llvm.LLVMAddGlobal(context.module, type, ident.src.toChar());

    v = LLVMAllocaVariable(y, llValue, type);
    llvm.LLVMSetLinkage(llValue, LLVMLinkage.LLVMInternalLinkage);
    llvm.LLVMSetGlobalConstant(llValue, isConst.llvmBool);

    llvm.LLVMSetInitializer(llValue, data);
    llvm.LLVMSetAlignment(llValue, context.getAlignSize(y));

    final diBuilder = context.dBuilder;
    if (diBuilder != null) {
      final file = llvm.LLVMDIScopeGetFile(context.scope);
      final diType = y.llvmType.createDIType(context);
      final name = ident.src;
      final expr = llvm.LLVMDIBuilderCreateExpression(diBuilder, nullptr, 0);

      final globalExpr = llvm.LLVMDIBuilderCreateGlobalVariableExpression(
          context.dBuilder!,
          context.scope,
          name.toChar(),
          name.length,
          unname,
          0,
          file,
          ident.offset.row,
          diType,
          LLVMTrue,
          expr,
          nullptr,
          0);

      llvm.LLVMGlobalSetMetadata(
          llValue, llvm.LLVMGetMDKindID("dbg".toChar(), 3), globalExpr);
    }

    context.pushVariable(ident, v);
    _run = true;
  }

  @override
  List<Object?> get props => [ident, ty, expr];

  @override
  void analysis(AnalysisContext context) {
    final realTy = ty?.grt(context);
    final val = LiteralExpr.run(() => expr.analysis(context), realTy);
    final vTy = realTy ?? val?.ty;
    if (vTy == null || val == null) return;
    context.pushVariable(
        ident, val.copy(ty: vTy, ident: ident, isGlobal: true));
  }
}

class TyStmt extends Stmt {
  TyStmt(this.ty);
  final Ty ty;
  @override
  Stmt clone() {
    return TyStmt(ty);
  }

  @override
  void build(BuildContext context) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }

  @override
  String toString() {
    return '$pad$ty';
  }

  @override
  List<Object?> get props => [ty];
}

class StructStmt extends Stmt {
  StructStmt(this.ty);
  @override
  Stmt clone() {
    return StructStmt(ty);
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final StructTy ty;

  @override
  void build(BuildContext context) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  String toString() {
    return '$pad$ty';
  }

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }
}

class EnumStmt extends Stmt {
  EnumStmt(this.ty);
  @override
  Stmt clone() {
    return EnumStmt(ty);
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    ty.incLevel(count);
  }

  final EnumTy ty;

  @override
  void build(BuildContext context) {
    ty.currentContext ??= context;
    ty.build();
  }

  @override
  List<Object?> get props => [ty];

  @override
  void analysis(AnalysisContext context) {
    ty.analysis(context);
  }
}
