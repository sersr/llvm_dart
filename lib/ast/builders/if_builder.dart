part of 'builders.dart';

typedef BlockRetFn = void Function(Block bloc, FnBuildMixin context);

abstract class IfExprBuilder {
  static StoreVariable? createIfBlock(
      IfExprBlock ifb, FnBuildMixin context, Ty? ty, bool isRetValue) {
    if (ty != null && !isRetValue) {
      return LLVMAllocaProxyVariable(context, (variable, isProxy) {
        _buildIfExprBlock(ifb, context, (block, context) {
          _blockRetValue(block, context, variable);
        }, false);
      }, ty, ty.typeOf(context), Identifier.none);
    }

    _buildIfExprBlock(ifb, context, (block, context) {}, isRetValue);

    return null;
  }

  static void _blockRetValue(
      Block block, FnBuildMixin context, StoreVariable? variable) {
    if (variable == null) return;
    final lastStmt = block.lastOrNull;

    if (lastStmt case ExprStmt(expr: var expr)) {
      // 获取缓存的value
      final temp = expr.build(context);
      final val = temp?.variable;
      if (val == null) return;

      if (val is LLVMAllocaProxyVariable && !val.created) {
        val.initProxy(proxy: variable);
      } else {
        variable.store(context, val.load(context));
      }
    }
  }

  static void _buildIfExprBlock(
      IfExprBlock ifEB, FnBuildMixin c, BlockRetFn blockRetFn, bool isRet) {
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
    ifEB.block.build(then.context, hasRet: isRet);

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
        _buildIfExprBlock(elseifBlock, elseBB.context, blockRetFn, isRet);
      } else if (elseBlock != null) {
        elseBlock.build(elseBB.context, hasRet: isRet);
      }
    }

    var canBr = then.context.canBr;
    if (canBr) {
      hasAfterBb = true;
      blockRetFn(ifEB.block, then.context);
      then.context.br(afterBB.context);
    }

    if (elseBB != null) {
      final elseCanBr = elseBB.context.canBr;
      if (elseCanBr) {
        hasAfterBb = true;
        if (elseBlock != null) {
          if (!isRet) blockRetFn(elseBlock, elseBB.context);
        } else if (elseifBlock != null) {
          if (!isRet) blockRetFn(elseifBlock.block, elseBB.context);
        }
        elseBB.context.br(afterBB.context);
      }
    }
    if (hasAfterBb) c.insertPointBB(afterBB);
  }
}
