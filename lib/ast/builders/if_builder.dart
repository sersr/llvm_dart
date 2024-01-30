part of 'builders.dart';

abstract class IfExprBuilder {
  static StoreVariable? createIfBlock(
      IfExprBlock ifb, FnBuildMixin context, Ty? ty, bool isRetValue) {
    StoreVariable? variable;
    if (ty != null) {
      if (isRetValue) {
        final fnContext = context.getLastFnContext()!;
        variable = fnContext.sret ?? fnContext.compileRetValue;
      }

      if (variable == null) {
        variable = ty.llty.createAlloca(context, Identifier.none);
        if (isRetValue) {
          context.removeVal(variable);
        }
      }
    }

    _buildIfExprBlock(ifb, context, variable);

    return variable;
  }

  static void _blockRetValue(
      Block block, FnBuildMixin context, StoreVariable? variable) {
    if (variable == null) return;

    final lastStmt = block.lastOrNull;
    if (lastStmt is ExprStmt) {
      final expr = lastStmt.expr;
      if (expr is! RetExpr) {
        // 获取缓存的value
        final temp = expr.build(context);
        final val = temp?.variable;
        if (val == null) {
          // error
        } else {
          if (val is LLVMAllocaProxyVariable && !val.created) {
            val.initProxy(proxy: variable);
          } else {
            variable.store(context, val.load(context));
          }
        }
      }
    }
  }

  static void _buildIfExprBlock(
      IfExprBlock ifEB, FnBuildMixin c, StoreVariable? variable) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = c.buildSubBB(name: 'then');
    late final afterBB = c.buildSubBB(name: 'after');
    LLVMBasicBlock? elseBB;

    bool hasAfterBb = false;

    final conTemp = ifEB.expr.build(c);
    final con = conTemp?.variable;
    if (con == null) return;

    LLVMValueRef conv;
    if (con.ty.isTy(BuiltInTy.kBool)) {
      conv = con.load(c);
    } else {
      conv = c.math(con, null, OpKind.Ne, Identifier.none).load(c);
    }

    c.appendBB(then);
    ifEB.block.build(then.context);

    if (onlyIf) {
      hasAfterBb = true;
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, afterBB.bb);
      c.setBr();
    } else {
      elseBB = c.buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, elseBB.bb);
      c.appendBB(elseBB);
      c.setBr();
      if (elseifBlock != null) {
        _buildIfExprBlock(elseifBlock, elseBB.context, variable);
      } else if (elseBlock != null) {
        elseBlock.build(elseBB.context);
      }
    }
    var canBr = then.context.canBr;
    if (canBr) {
      hasAfterBb = true;
      _blockRetValue(ifEB.block, then.context, variable);
      then.context.br(afterBB.context);
    }

    if (elseBB != null) {
      final elseCanBr = elseBB.context.canBr;
      if (elseCanBr) {
        hasAfterBb = true;
        if (elseBlock != null) {
          _blockRetValue(elseBlock, elseBB.context, variable);
        } else if (elseifBlock != null) {
          _blockRetValue(elseifBlock.block, elseBB.context, variable);
        }
        elseBB.context.br(afterBB.context);
      }
    }
    if (hasAfterBb) c.insertPointBB(afterBB);
  }
}
