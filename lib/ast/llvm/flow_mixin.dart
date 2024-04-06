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

    if (val != null) {
      final sret = fn.sret;
      final isSretRet = sret != null;
      if (isSretRet) sretRet(sret, val);

      if (!removeVal(val)) {
        freeAddStack(val);
      }

      freeHeap();

      /// return variable
      if (!isSretRet && !fnty.fnDecl.isVoidRet(this)) {
        final v = AbiFn.fnRet(this, fnty, val);
        diSetCurrentLoc(retOffset);
        llvm.LLVMBuildRet(builder, v);

        return;
      }
    }

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

  FnBuildMixin createBlockContext({String name = 'entry'}) {
    final child = createChildContext();
    child.copyBuilderFrom(this);
    return child;
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

  void painc() {
    llvm.LLVMBuildUnreachable(builder);
  }

  /// math
  Variable math(Variable lhs, Variable? rhs, OpKind op, Identifier opId) {
    var isFloat = false;
    var signed = false;
    var ty = lhs.ty;
    LLVMTypeRef? type;

    var l = lhs.load(this);
    var r = rhs?.load(this);

    if (r == null || rhs == null) {
      LLVMValueRef? value;

      if (op == OpKind.Eq) {
        value = llvm.LLVMBuildIsNull(builder, l, unname);
      } else {
        assert(op == OpKind.Ne);
        value = llvm.LLVMBuildIsNotNull(builder, l, unname);
      }
      return LLVMConstVariable(value, LiteralKind.kBool.ty, opId);
    }

    if (ty is BuiltInTy && ty.literal.isNum) {
      final kind = ty.literal;
      final rty = rhs.ty;
      if (rty is BuiltInTy) {
        final rSize = rty.llty.getBytes(this);
        final lSize = ty.llty.getBytes(this);
        final max = rSize > lSize ? rty : ty;
        type = max.typeOf(this);
        ty = max;
      }
      if (kind.isFp) {
        isFloat = true;
      } else if (kind.isInt) {
        signed = kind.signed;
      }
    } else if (ty is RefTy) {
      ty = rhs.ty;
      type = ty.typeOf(this);
      l = llvm.LLVMBuildPtrToInt(builder, l, type, unname);
    }

    type ??= ty.typeOf(this);

    if (isFloat) {
      l = llvm.LLVMBuildFPCast(builder, l, type, unname);
      r = llvm.LLVMBuildFPCast(builder, r, type, unname);
    } else {
      l = llvm.LLVMBuildIntCast2(builder, l, type, signed.llvmBool, unname);
      r = llvm.LLVMBuildIntCast2(builder, r, type, signed.llvmBool, unname);
    }

    if (op == OpKind.And || op == OpKind.Or) {
      final after = buildSubBB(name: 'op_after');
      final opBB = buildSubBB(name: 'op_bb');
      final allocaValue = alloctor(i1);
      final variable =
          LLVMAllocaVariable(allocaValue, LiteralKind.kBool.ty, i1, opId);

      variable.store(this, l);
      appendBB(opBB);

      if (op == OpKind.And) {
        llvm.LLVMBuildCondBr(builder, l, opBB.bb, after.bb);
      } else {
        llvm.LLVMBuildCondBr(builder, l, after.bb, opBB.bb);
      }
      final c = opBB.context;

      variable.store(c, r);
      c.br(after.context);
      insertPointBB(after);
      return variable;
    }

    LLVMValueRef Function(LLVMBuilderRef b, LLVMValueRef l, LLVMValueRef r,
        Pointer<Char> name)? llfn;

    diSetCurrentLoc(opId.offset);

    if (isFloat) {
      final id = op.getFCmpId(true);
      if (id != null) {
        final v = llvm.LLVMBuildFCmp(builder, id, l, r, unname);
        return LLVMConstVariable(v, LiteralKind.kBool.ty, opId);
      }
      LLVMValueRef? value;
      switch (op) {
        case OpKind.Add:
          value = llvm.LLVMBuildFAdd(builder, l, r, unname);
        case OpKind.Sub:
          value = llvm.LLVMBuildFSub(builder, l, r, unname);
        case OpKind.Mul:
          value = llvm.LLVMBuildFMul(builder, l, r, unname);
        case OpKind.Div:
          value = llvm.LLVMBuildFDiv(builder, l, r, unname);
        case OpKind.Rem:
          value = llvm.LLVMBuildFRem(builder, l, r, unname);
        case OpKind.BitAnd:
        case OpKind.BitOr:
        case OpKind.BitXor:
        // value = llvm.LLVMBuildAnd(builder, l, r, unname);
        // value = llvm.LLVMBuildOr(builder, l, r, unname);
        // value = llvm.LLVMBuildXor(builder, l, r, unname);
        default:
      }
      if (value != null) {
        return LLVMConstVariable(value, ty, opId);
      }
    }

    final isConst = lhs is LLVMLitVariable && rhs is LLVMLitVariable;
    final cmpId = op.getICmpId(signed);
    if (cmpId != null) {
      final v = llvm.LLVMBuildICmp(builder, cmpId, l, r, unname);
      return LLVMConstVariable(v, LiteralKind.kBool.ty, opId);
    }

    LLVMValueRef? value;

    LLVMIntrisics? k;
    switch (op) {
      case OpKind.Add:
        if (isConst) {
          llfn = llvm.LLVMBuildAdd;
        } else {
          k = LLVMIntrisics.getAdd(ty, signed, this);
        }
        break;
      case OpKind.Sub:
        if (!signed || isConst) {
          llfn = llvm.LLVMBuildSub;
        } else {
          k = LLVMIntrisics.getSub(ty, signed, this);
        }
        break;
      case OpKind.Mul:
        if (isConst) {
          llfn = llvm.LLVMBuildMul;
        } else {
          k = LLVMIntrisics.getMul(ty, signed, this);
        }
        break;
      case OpKind.Div:
        llfn = signed ? llvm.LLVMBuildSDiv : llvm.LLVMBuildUDiv;
        break;
      case OpKind.Rem:
        llfn = signed ? llvm.LLVMBuildSRem : llvm.LLVMBuildURem;
        break;
      case OpKind.BitAnd:
        llfn = llvm.LLVMBuildAnd;
        break;
      case OpKind.BitOr:
        llfn = llvm.LLVMBuildOr;
        break;
      case OpKind.BitXor:
        llfn = llvm.LLVMBuildXor;
        break;
      case OpKind.Shl:
        llfn = llvm.LLVMBuildShl;
        break;
      case OpKind.Shr:
        llfn = signed ? llvm.LLVMBuildAShr : llvm.LLVMBuildLShr;
        break;
      default:
    }

    assert(k != null || llfn != null);

    if (k != null) {
      final mathValue = root.oMath(l, r, k, this);
      final after = buildSubBB(name: 'math');
      final panicBB = buildSubBB(name: 'panic');
      appendBB(panicBB);
      expect(mathValue.condition, v: false);
      llvm.LLVMBuildCondBr(builder, mathValue.condition, panicBB.bb, after.bb);
      panicBB.context.diSetCurrentLoc(opId.offset);
      panicBB.context.painc();
      insertPointBB(after);

      return LLVMConstVariable(mathValue.value, ty, opId);
    }
    if (llfn != null) {
      value = llfn(builder, l, r, unname);
    }

    return LLVMConstVariable(value ?? l, ty, opId);
  }
}
