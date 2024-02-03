part of 'builders.dart';

typedef BlockRetFn = void Function(Block bloc, FnBuildMixin context);

abstract class IfExprBuilder {
  static StoreVariable? createIfBlock(
      IfExprBlock ifb, FnBuildMixin context, Ty? ty, bool isRet, bool hasElse) {
    final noAfter = isRet && hasElse;

    void inner(StoreVariable? variable) {
      final afterBlock = noAfter ? null : context.buildSubBB(name: 'if_after');

      _buildIfExprBlock(ifb, context, (block, context) {
        _blockRetValue(block, context, variable);
      }, isRet, afterBlock);

      if (afterBlock != null) context.insertPointBB(afterBlock);
    }

    if (ty != null) {
      return LLVMAllocaProxyVariable(context, (variable, isProxy) {
        inner(variable);
      }, ty, ty.typeOf(context), Identifier.none);
    }

    inner(null);
    return null;
  }

  static void _blockRetValue(
      Block block, FnBuildMixin context, StoreVariable? variable) {
    if (variable == null) return;

    if (block.lastOrNull case ExprStmt(expr: var expr)) {
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
    IfExprBlock ifEB,
    FnBuildMixin c,
    BlockRetFn blockRetFn,
    bool isRet,
    LLVMBasicBlock? afterBlock, [
    LLVMBasicBlock? current,
  ]) {
    final child = ifEB.child;
    final isElseBlock = ifEB.expr == null;

    final then = isElseBlock
        ? current ?? c.buildSubBB(name: 'else')
        : c.buildSubBB(name: current == null ? 'then' : 'else_if');

    final elseOrAfter = switch (child) {
      != null => c.buildSubBB(name: 'elif_condition'),
      _ => afterBlock,
    };

    final con = ifEB.expr?.build(c)?.variable;

    if (con != null) {
      assert(!isElseBlock);
      LLVMValueRef conv;

      if (con.ty.isTy(LiteralKind.kBool.ty)) {
        conv = con.load(c);
      } else {
        conv = c.math(con, null, OpKind.Ne, Identifier.none).load(c);
      }

      llvm.LLVMBuildCondBr(c.builder, conv, then.bb, elseOrAfter!.bb);
      c.setBr();

      c.appendBB(then);
    }

    ifEB.block.build(then.context, hasRet: isRet);

    if (then.context.canBr) {
      blockRetFn(ifEB.block, then.context);
      then.context.br(afterBlock!.context);
    }

    if (child != null) {
      c.appendBB(elseOrAfter!);
      _buildIfExprBlock(child, elseOrAfter.context, blockRetFn, isRet,
          afterBlock, elseOrAfter);

      if (elseOrAfter.context.canBr) {
        elseOrAfter.context.br(afterBlock!.context);
      }
    }
  }
}
