part of 'builders.dart';

abstract class MatchBuilder {
  static void commonBuilder(MatchItemExpr item, FnBuildMixin context,
      ExprTempValue temp, StoreVariable? retVariable) {
    final then = context.buildSubBB(name: 'm_then');
    final after = context.buildSubBB(name: 'm_after');
    LLVMBasicBlock elseBB;
    final child = item.child;
    if (child != null) {
      elseBB = context.buildSubBB(name: 'm_else');
    } else {
      elseBB = after;
    }

    context.appendBB(then);
    final exprTempValue = item.build3(context, temp);
    final val = exprTempValue?.variable;
    item.block.build(then.context);
    IfExprBuilder._blockRetValue(item.block, then.context, retVariable);
    if (then.context.canBr) {
      then.context.br(after.context);
    }

    if (val != null) {
      llvm.LLVMBuildCondBr(
          context.builder, val.load(context), then.bb, elseBB.bb);
    }

    if (child != null) {
      context.appendBB(elseBB);
      // if (child.isValIdent) {
      //   child.build4(elseBB.context, temp);
      //   IfExprBuilder._blockRetValue(child.block, elseBB.context, retVariable);
      // } else
      if (child.isOther) {
        child.build2(elseBB.context, temp);
        IfExprBuilder._blockRetValue(child.block, elseBB.context, retVariable);
      } else {
        commonBuilder(child, elseBB.context, temp, retVariable);
      }

      if (elseBB.context.canBr) {
        elseBB.context.br(after.context);
      }
    }

    context.insertPointBB(after);
  }

  static void commonExpr(FnBuildMixin context, List<MatchItemExpr> items,
      ExprTempValue temp, StoreVariable? variable) {
    MatchItemExpr? last;
    MatchItemExpr? first;

    final otherItem = items.firstWhereOrNull((element) => element.isOther);

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

    commonBuilder(first!, context, temp, variable);
  }

  static StoreVariable? matchBuilder(FnBuildMixin context,
      List<MatchItemExpr> items, ExprTempValue temp, Ty? retTy, bool isRet) {
    StoreVariable? variable;

    if (retTy != null) {
      if (isRet) {
        final fnContext = context.getLastFnContext()!;
        variable = fnContext.sret ?? fnContext.compileRetValue;
      }

      if (variable == null) {
        variable = retTy.llty.createAlloca(context, Identifier.none);
        if (isRet) {
          context.removeVal(variable);
        }
      }
    }

    _matchBuilder(context, items, temp, variable);

    return variable;
  }

  static void _matchBuilder(FnBuildMixin context, List<MatchItemExpr> items,
      ExprTempValue temp, StoreVariable? retVariable) {
    final parent = temp.variable;
    if (parent == null) return;
    var enumTy = temp.ty;
    if (enumTy is EnumItem) {
      enumTy = enumTy.parent;
    }

    if (enumTy is! EnumTy) {
      commonExpr(context, items, temp, retVariable);
      return;
    }

    var indexValue = enumTy.llty.loadIndex(context, parent);

    final hasOther = items.any((e) => e.isOther);

    /// 变量是否可用
    final varUseable = hasOther || items.length == enumTy.variants.length;

    if (!varUseable) retVariable = null;

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
      final itemIndex = first.build2(then.context, temp);
      IfExprBuilder._blockRetValue(first.block, then.context, retVariable);
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

        child.build2(elseBB.context, temp);
        IfExprBuilder._blockRetValue(child.block, elseBB.context, retVariable);

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
      final v = item.build2(childBb.context, temp);
      if (v != null) {
        llvm.LLVMAddCase(ss, llPty.getIndexValue(context, v), childBb.bb);
      }
      IfExprBuilder._blockRetValue(item.block, childBb.context, retVariable);
      childBb.context.br(after.context);
      index += 1;
    }

    if (after != elseBb) {
      context.insertPointBB(after);
    }
  }
}
