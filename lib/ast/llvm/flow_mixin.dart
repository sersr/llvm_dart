part of 'build_context_mixin.dart';

mixin FlowMixin on BuildContext, FreeMixin {
  bool _breaked = false;
  bool _returned = false;
  bool get canBr => !_returned && !_breaked;

  void ret(Variable? val, {bool isLastStmt = false}) {
    if (!canBr) return;

    _returned = true;

    final fn = getLastFnContext();
    if (fn == null) return;
    if (fn._updateRunAfter(val, this, isLastStmt)) return;

    final retOffset = val?.offset ?? Offset.zero;

    final fnty = fn.currentFn!;
    if (fnty.getRetTy(this).isTy(LiteralKind.kVoid.ty) || val == null) {
      freeHeap();
      diSetCurrentLoc(retOffset);
      llvm.LLVMBuildRetVoid(builder);
      return;
    }

    if (!removeVal(val)) {
      freeAddStack(val);
    }

    freeHeap();

    final sret = fn.sret;

    /// return variable
    if (sret == null) {
      final v = AbiFn.fnRet(this, fnty, val);
      diSetCurrentLoc(retOffset);
      llvm.LLVMBuildRet(builder, v);

      return;
    }

    /// struct ret
    sretRet(sret, val);

    diSetCurrentLoc(retOffset);
    llvm.LLVMBuildRetVoid(builder);
  }

  void sretRet(StoreVariable sret, Variable val);
  void freeAddStack(Variable val);

  void instertFnEntryBB({String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, getLastFnContext()!.fnValue, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
  }

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = createChildContext();
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());

    llvm.LLVMPositionBuilderAtEnd(child.builder, bb);
    return LLVMBasicBlock(bb, child, false);
  }

  void appendBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(getLastFnContext()!.fnValue, bb.bb);
    bb.inserted = true;
  }

  // 切换到另一个 BasicBlock
  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    appendBB(bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    _breaked = false;
  }

  /// 流程控制，loop/if/match

  final loopBBs = <LLVMBasicBlock>[];

  LLVMBasicBlock getLoopBB(String? label) {
    if (label == null) {
      return _getLast();
    }
    var bb = _getLable(label);
    bb ??= _getLast();

    return bb;
  }

  FlowMixin? get parent;

  LLVMBasicBlock _getLast() {
    if (loopBBs.isEmpty) {
      return parent!._getLast();
    }
    return loopBBs.last;
  }

  LLVMBasicBlock? _getLable(String label) {
    var bb = loopBBs.lastWhereOrNull((element) => element.label == label);
    if (bb == null) {
      return parent?._getLable(label);
    }
    return bb;
  }

  void forLoop(Block block, String? label, Expr? expr) {
    final loopBB = buildSubBB(name: 'loop');
    final loopAfter = buildSubBB(name: 'loop_after');
    loopAfter.label = label;
    loopAfter.parent = loopBB;
    loopBBs.add(loopAfter);
    br(loopBB.context);
    insertPointBB(loopBB);

    if (expr != null) {
      final v = expr.build(loopBB.context);
      final variable = v?.variable;
      if (variable != null) {
        final bb = buildSubBB(name: 'loop_body');
        final v = variable.load(loopBB.context);
        llvm.LLVMBuildCondBr(loopBB.context.builder, v, bb.bb, loopAfter.bb);
        appendBB(bb);
        block.build(bb.context);
        bb.context.br(this);
      }
    } else {
      block.build(loopBB.context);
      loopBB.context.br(this);
    }
    insertPointBB(loopAfter);
    loopBBs.remove(loopAfter);
  }

  void br(FlowMixin to) {
    if (!canBr) return;
    freeBr(null);
    _br(to);
  }

  void _br(FlowMixin to) {
    _breaked = true;
    llvm.LLVMBuildBr(builder, llvm.LLVMGetInsertBlock(to.builder));
  }

  void setBr() {
    _breaked = true;
  }

  void brLoop() {
    if (!canBr) return;
    final from = getLoopBB(null);
    freeBr(from.context);

    _breaked = true;
    llvm.LLVMBuildBr(builder, from.bb);
  }

  void brContinue() {
    if (!canBr) return;
    final from = getLoopBB(null).parent!;
    freeBr(from.context);

    _breaked = true;
    llvm.LLVMBuildBr(builder, from.bb);
  }

  void freeBr(FnBuildMixin? from);

  /// math
  Variable math(Variable lhs, Variable? rhs, OpKind op, Identifier opId) {
    return OverflowMath.math(this, lhs, rhs, op, opId);
  }
}
