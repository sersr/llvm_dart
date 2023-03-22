import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llvm_dart/ast/expr.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'context.dart';

class LLVMBasicBlock extends BasicBlock {
  LLVMBasicBlock(this.bb, this.context, this.inserted);
  final LLVMBasicBlockRef bb;
  final BuildContext context;
  bool inserted = false;
}

abstract class LLVMVariable extends Variable {
  LLVMVariable(super.ty);

  LLVMValueRef load(LLVMBackendBuildContext c);
}

class LLVMConstVariable extends LLVMVariable {
  LLVMConstVariable(this.value, super.ty);
  final Pointer<LLVMOpaqueValue> value;

  @override
  LLVMValueRef load(LLVMBackendBuildContext c) {
    return value;
  }
}

class LLVMAllocaVariable extends LLVMVariable {
  LLVMAllocaVariable(super.ty, this.alloca, this.type);
  final LLVMValueRef alloca;
  final LLVMTypeRef type;

  @override
  LLVMValueRef load(LLVMBackendBuildContext c) {
    return llvm.LLVMBuildLoad2(c.builder, type, alloca, unname);
  }

  void store(LLVMBackendBuildContext c, LLVMValueRef val) {
    llvm.LLVMBuildStore(c.builder, val, alloca);
  }
}

LLVMCore get llvm => LLVMInstance.getInstance();

class LLVMBackendBuildContext extends BuildContext {
  LLVMBackendBuildContext._(LLVMBackendBuildContext parent) : super(parent) {
    kModule = parent.kModule;
    _init();
  }

  LLVMBackendBuildContext.root([String name = 'root']) : super(null) {
    kModule = llvm.createKModule(name.toChar());
    _init();
  }

  @override
  LLVMBackendBuildContext get parent => super.parent as LLVMBackendBuildContext;

  void _init() {
    module = llvm.getModule(kModule);
    llvmContext = llvm.getLLVMContext(kModule);
    fpm = llvm.getFPM(kModule);
    builder = llvm.LLVMCreateBuilderInContext(llvmContext);
  }

  late final KModuleRef kModule;
  late final LLVMModuleRef module;
  late final LLVMContextRef llvmContext;
  late final LLVMBuilderRef builder;
  late final LLVMPassManagerRef fpm;

  late LLVMConstVariable fn;
  @override
  LLVMBackendBuildContext createChildContext() {
    return LLVMBackendBuildContext._(this);
  }

  LLVMBasicBlock buildBB(LLVMConstVariable val, {String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, val.value, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, true);
  }

  LLVMBasicBlock createBB({String name = 'entry'}) {
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, false);
  }

  void insertAfterBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    bb.inserted = true;
  }

  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    bb.inserted = true;
  }

  @override
  void buildFnBB(Fn fn, void Function(LLVMBackendBuildContext child) action) {
    final fv = buildFn(fn.fnSign);
    final bbContext = createChildContext();
    bbContext.fn = fv;
    bbContext.buildBB(fv);
    action(bbContext);
  }

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = createChildContext();
    child.fn = fn;
    return child.createBB(name: name);
  }

  @override
  void ret(LLVMConstVariable? val) {
    if (val == null) {
      llvm.LLVMBuildRetVoid(builder);
    } else {
      final v = val.load(this);
      llvm.LLVMBuildRet(builder, v);
    }
  }

  @override
  LLVMValueRef? buildIfExprBlock(IfExprBlock ifEB) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = buildSubBB(name: 'then');
    final elseBB = buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
    final afterBB = buildSubBB(name: 'after');

    final con = ifEB.expr.build(this) as LLVMConstVariable?;
    if (con == null) return null;

    insertAfterBB(then);
    if (onlyIf) {
      llvm.LLVMBuildCondBr(builder, con.value, then.bb, afterBB.bb);
    } else {
      llvm.LLVMBuildCondBr(builder, con.value, then.bb, elseBB.bb);
    }
    ifEB.block.build(then.context);
    then.context.br(afterBB.context);

    if (elseifBlock != null) {
      insertAfterBB(elseBB);
      elseBB.context.buildIfExprBlock(elseifBlock);
      elseBB.context.br(afterBB.context);
    } else if (elseBlock != null) {
      insertAfterBB(elseBB);
      ifEB.elseBlock?.build(elseBB.context);
      elseBB.context.br(afterBB.context);
    }
    insertPointBB(afterBB);

    // final ty = llvm.LLVMInt32Type();
    // final tNull = llvm.LLVMConstNull(ty);
    // final phi = llvm.LLVMBuildPhi(builder, ty, unname);
    // final listT = [tNull, tNull].toNative();
    // final bbs = [then.bb, elseBB.bb].toNative();
    // llvm.LLVMAddIncoming(phi, listT.cast(), bbs.cast(), 2);
    return null;
  }

  @override
  IfBuildContext buildIf(LLVMConstVariable val) {
    final v = val.load(this);
    final then = createChildContext();
    final elseContext = createChildContext();

    final thenBB = then.buildBB(fn, name: 'then');
    final elseBB = elseContext.buildBB(fn, name: 'else');

    llvm.LLVMBuildCondBr(builder, v, thenBB.bb, elseBB.bb);

    return IfBuildContext(val, then, elseContext);
  }

  @override
  void br(LLVMBackendBuildContext to) {
    llvm.LLVMBuildBr(builder, llvm.LLVMGetInsertBlock(to.builder));
  }

  LLVMConstVariable createIntValue(Ty ty, int value) {
    final type = llvm.LLVMInt32TypeInContext(llvmContext);
    final v = llvm.LLVMConstInt(type, value, 32);
    return LLVMConstVariable(v, ty);
  }

  LLVMConstVariable createFloatValue(Ty ty, double value) {
    final type = llvm.LLVMDoubleTypeInContext(llvmContext);
    final v = llvm.LLVMConstReal(type, value);
    return LLVMConstVariable(v, ty);
  }

  LLVMConstVariable createStringValue(Ty ty, String value) {
    final v = value.toChar();

    final str = llvm.LLVMConstStringInContext(llvmContext, v, value.length, 1);

    return LLVMConstVariable(str, ty);
  }

  LLVMConstVariable createVoidValue(Ty ty) {
    final t = llvm.LLVMVoidTypeInContext(llvmContext);
    final s = llvm.LLVMConstNull(t);
    return LLVMConstVariable(s, ty);
  }

  @override
  Variable buildVariable(Ty ty, String ident) {
    if (ty is BuiltInTy) {
      final kind = ty.ty;
      if (kind == LitKind.kInt) {
        return createIntValue(ty, int.parse(ident));
      } else if (kind == LitKind.kDouble) {
        return createFloatValue(ty, double.parse(ident));
      } else if (kind == LitKind.kString) {
        return createStringValue(ty, ident);
      } else if (kind == LitKind.kVoid) {
        return createVoidValue(ty);
      }
    }
    throw UnimplementedError('');
  }

  LLVMTypeRef? createType(Ty ty) {
    if (ty is PathTy) {
      final tySrc = ty.ident.src;
      var t = BuiltInTy.from(ty.ident, tySrc);
      if (t != null) {
        ty = t;
      }
    }
    if (ty is BuiltInTy) {
      final k = ty.ty;
      if (k == LitKind.kInt) {
        return llvm.LLVMInt32TypeInContext(llvmContext);
      } else if (k == LitKind.kDouble) {
        return llvm.LLVMDoubleTypeInContext(llvmContext);
      } else if (k == LitKind.kString) {
        return null;
      } else if (k == LitKind.kVoid) {
        return null;
      }
    }
    return null;
  }

  @override
  Variable buildAlloca(LLVMConstVariable val, {Ty? ty}) {
    ty ??= val.ty;
    final t = createType(ty);
    if (t == null) {
      return val;
    }
    final s = llvm.LLVMBuildAlloca(builder, t, unname);
    llvm.LLVMBuildStore(builder, val.value, s);
    return LLVMAllocaVariable(ty, s, t);
  }

  @override
  Variable buildAllocaNull(Ty ty) {
    final t = createType(ty);
    if (t == null) return DeclVariable(ty, null);

    final s = llvm.LLVMBuildAlloca(builder, t, unname);
    return LLVMAllocaVariable(ty, s, t);
  }

  @override
  Variable math(LLVMVariable lhs, LLVMVariable rhs, OpKind op) {
    final lIsInt = lhs.isInt;
    final l = lhs.load(this);
    final r = rhs.load(this);
    LLVMValueRef value;
    if (lIsInt) {
      if (op == OpKind.Sub) {
        value = llvm.LLVMBuildSub(builder, l, r, unname);
      } else if (op == OpKind.Lt) {
        value = llvm.LLVMBuildICmp(
            builder, LLVMIntPredicate.LLVMIntULT, l, r, unname);
      } else {
        value = llvm.LLVMBuildAdd(builder, l, r, unname);
      }
    } else {
      if (op == OpKind.Sub) {
        value = llvm.LLVMBuildFSub(builder, l, r, unname);
      } else {
        value = llvm.LLVMBuildFAdd(builder, l, r, unname);
      }
    }
    // final rIsInt = lhs.isInt;
    return LLVMConstVariable(value, lhs.ty);
  }

  @override
  LLVMConstVariable buildFn(FnSign fn) {
    final params = fn.fnDecl.params;
    final list = <LLVMTypeRef>[];
    for (var p in params) {
      final ty = createType(p.ty);
      if (ty != null) {
        list.add(ty);
      }
    }
    final pr = list.toNative();

    var ret = createType(fn.fnDecl.returnTy) ?? llvm.LLVMVoidType();

    final fnty = llvm.LLVMFunctionType(ret, pr.cast(), list.length, LLVMFalse);
    final llvmFn = llvm.LLVMAddFunction(module, 'main'.toChar(), fnty);
    return LLVMConstVariable(llvmFn, fn.fnDecl.returnTy);
  }
}

class LLVMAllocator implements Allocator {
  LLVMAllocator();

  final _caches = <Pointer>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = malloc.allocate<T>(byteCount, alignment: alignment);
    _caches.add(p);
    return p;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    _caches.remove(pointer);
    malloc.free(pointer);
  }

  void releaseAll() {
    for (var p in _caches) {
      malloc.free(p);
    }
    _caches.clear();
  }
}

final _llvmMalloc = LLVMAllocator();

Pointer<Char> get unname {
  return ''.toChar();
}

LLVMAllocator get llvmMalloc {
  final z = Zone.current[#llvmZone];
  if (z is LLVMAllocator) {
    return z;
  }
  return _llvmMalloc;
}

T runLLVMZoned<T>(T Function() body, {LLVMAllocator? malloc}) {
  return runZoned(body, zoneValues: {#llvmZone: malloc ?? _llvmMalloc});
}

extension StringToChar on String {
  Pointer<Char> toChar({Allocator? malloc}) {
    malloc ??= llvmMalloc;
    final u = toNativeUtf8(allocator: malloc);
    return u.cast();
  }
}

extension ArrayExt<T extends NativeType> on List<Pointer<T>> {
  Pointer<Pointer> toNative() {
    final arr = llvmMalloc<Pointer>(length);
    for (var i = 0; i < length; i++) {
      arr[i] = this[i];
    }
    return arr;
  }
}

class LLVMIfBuildContext extends IfBuildContext {
  LLVMIfBuildContext(this.value, super.val, super.then, super.elseContext);
  final LLVMValueRef value;
}
