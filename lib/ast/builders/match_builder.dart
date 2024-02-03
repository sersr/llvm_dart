part of 'builders.dart';

abstract class MatchBuilder {
  static void commonBuilder(
    MatchItemExpr item,
    FnBuildMixin context,
    ExprTempValue temp,
    BlockRetFn blockRetFn,
    bool isRet,
    LLVMBasicBlock? afterBlock, [
    LLVMBasicBlock? current,
  ]) {
    final child = item.child;

    final then =
        context.buildSubBB(name: current == null ? 'm_then' : 'm_else_if');

    final elseBB = switch (child) {
      != null => context.buildSubBB(name: 'm_condition'),
      _ => afterBlock,
    };

    final exprTempValue = item.build3(context, temp);
    final val = exprTempValue?.variable;

    if (val != null) {
      llvm.LLVMBuildCondBr(
          context.builder, val.load(context), then.bb, elseBB!.bb);
      context.setBr();
    }

    context.appendBB(then);

    item.block.build(then.context, hasRet: isRet);

    if (then.context.canBr) {
      blockRetFn(item.block, then.context);
      then.context.br(afterBlock!.context);
    }

    if (child != null) {
      context.appendBB(elseBB!);
      if (child.isValIdent) {
        child.build4(elseBB.context, temp, isRet);
        if (elseBB.context.canBr) blockRetFn(child.block, elseBB.context);
      } else if (child.isOther) {
        child.build2(elseBB.context, temp, isRet);
        if (elseBB.context.canBr) blockRetFn(child.block, elseBB.context);
      } else {
        commonBuilder(
            child, elseBB.context, temp, blockRetFn, isRet, afterBlock, elseBB);
      }

      if (elseBB.context.canBr) {
        elseBB.context.br(afterBlock!.context);
      }
    }
  }

  static void commonExpr(FnBuildMixin context, List<MatchItemExpr> items,
      ExprTempValue temp, BlockRetFn blockRetFn, bool isRet) {
    MatchItemExpr? last;
    MatchItemExpr? first;

    final otherItem = items.firstWhereOrNull((element) => element.isValIdent);

    for (var item in items) {
      if (item == otherItem) continue;
      if (last == null) {
        last = item;
        first = item;
        continue;
      }
      last.child = item;
      last = item;
    }
    last?.child = otherItem;
    last = otherItem;

    final afterBlock =
        isRet && otherItem != null ? null : context.buildSubBB(name: 'm_after');

    commonBuilder(first!, context, temp, blockRetFn, isRet, afterBlock);
    if (afterBlock != null) context.insertPointBB(afterBlock);
  }

  static StoreVariable? matchBuilder(FnBuildMixin context,
      List<MatchItemExpr> items, ExprTempValue temp, Ty? retTy, bool isRet) {
    if (items.isEmpty) return null;

    if (retTy != null) {
      return LLVMAllocaProxyVariable(context, (proxy, isProxy) {
        _matchBuilder(context, items, temp, (block, context) {
          IfExprBuilder._blockRetValue(block, context, proxy);
        }, isRet);
      }, retTy, retTy.typeOf(context), Identifier.none);
    }

    _matchBuilder(context, items, temp, (block, context) {}, isRet);

    return null;
  }

  static void _matchBuilder(FnBuildMixin context, List<MatchItemExpr> items,
      ExprTempValue temp, BlockRetFn blockRetFn, bool isRet) {
    final parent = temp.variable;
    if (parent == null) return;
    var enumTy = temp.ty;
    if (enumTy is EnumItem) {
      enumTy = enumTy.parent;
    }

    if (enumTy is! EnumTy) {
      commonExpr(context, items, temp, blockRetFn, isRet);
      return;
    }

    var indexValue = enumTy.llty.loadIndex(context, parent);

    final hasOther = items.any((e) => e.isOther);

    var length = items.length;

    if (length <= 2) {
      final first = items.first;
      final child = items.lastOrNull;

      final then = context.buildSubBB(name: 'm_then');
      final after = context.buildSubBB(name: 'm_after');
      LLVMBasicBlock elseBB;

      if (child != null) {
        elseBB = context.buildSubBB(name: 'm_else');
      } else {
        elseBB = after;
      }

      context.appendBB(then);
      final itemIndex = first.build2(then.context, temp, isRet);
      blockRetFn(first.block, then.context);
      if (then.context.canBr) {
        then.context.br(after.context);
      }
      assert(itemIndex != null, "$first error.");

      final con = llvm.LLVMBuildICmp(
          context.builder,
          LLVMIntPredicate.LLVMIntEQ,
          indexValue,
          enumTy.llty.getIndexValue(context, itemIndex!),
          unname);
      llvm.LLVMBuildCondBr(context.builder, con, then.bb, elseBB.bb);

      if (child != null) {
        context.appendBB(elseBB);

        child.build2(elseBB.context, temp, isRet);
        blockRetFn(child.block, elseBB.context);

        if (elseBB.context.canBr) {
          elseBB.context.br(after.context);
        }
      }

      context.insertPointBB(after);
      return;
    }

    final elseBb = context.buildSubBB(name: 'match_else');
    LLVMBasicBlock after = elseBb;

    if (hasOther) {
      length -= 1;
      context.appendBB(elseBb);
      after = context.buildSubBB(name: 'match_after');
    }

    final ss =
        llvm.LLVMBuildSwitch(context.builder, indexValue, elseBb.bb, length);
    var index = 0;
    final llPty = enumTy.llty;

    for (var item in items) {
      LLVMBasicBlock childBb;
      if (item.isOther) {
        childBb = elseBb;
      } else {
        childBb = context.buildSubBB(name: 'match_bb_$index');
        context.appendBB(childBb);
      }
      final v = item.build2(childBb.context, temp, isRet);
      if (v != null) {
        llvm.LLVMAddCase(ss, llPty.getIndexValue(context, v), childBb.bb);
      }
      blockRetFn(item.block, childBb.context);
      childBb.context.br(after.context);
      index += 1;
    }

    if (after != elseBb) {
      context.insertPointBB(after);
    }
  }
}
