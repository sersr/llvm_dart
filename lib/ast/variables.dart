import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'context.dart';
import 'memory.dart';
import 'tys.dart';

class LLVMConstVariable extends Variable {
  LLVMConstVariable(this.value, this.ty);
  @override
  final Ty ty;

  final LLVMValueRef value;

  @override
  LLVMValueRef load(BuildContext c) {
    return value;
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(value);
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.create(c, this)..store(c, value);
  }
}

class LLVMAllocaVariable extends StoreVariable {
  LLVMAllocaVariable(this.ty, this.alloca, this.type);
  @override
  final LLVMValueRef alloca;

  final LLVMTypeRef type;

  @override
  final Ty ty;

  @override
  LLVMValueRef load(BuildContext c) {
    final v = llvm.LLVMBuildLoad2(c.builder, type, alloca, unname);
    return v;
  }

  @override
  void store(BuildContext c, LLVMValueRef val) {
    llvm.LLVMBuildStore(c.builder, val, alloca);
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return type;
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.create(c, this)..store(c, alloca);
  }
}

abstract class Deref with Variable {
  Variable getDeref(BuildContext c, {bool mut = true});
}

class LLVMRefAllocaVariable extends StoreVariable implements Deref {
  LLVMRefAllocaVariable(this.parent, this.alloca);
  final Variable parent;
  @override
  final LLVMValueRef alloca;
  @override
  bool get isRef => true;

  static LLVMRefAllocaVariable create(BuildContext c, Variable parent) {
    final t = c.pointer();
    final alloca = c.createAlloca(t);
    return LLVMRefAllocaVariable(parent, alloca);
  }

  @override
  LLVMValueRef load(BuildContext c) {
    return llvm.LLVMBuildLoad2(c.builder, c.pointer(), alloca, unname);
  }

  @override
  void store(BuildContext c, LLVMValueRef val) {
    llvm.LLVMBuildStore(c.builder, val, alloca);
  }

  @override
  Ty get ty => parent.ty;

  @override
  Variable getDeref(BuildContext c, {bool mut = true}) {
    final type = parent.getDerefType(c);
    final pTy = ty;
    if (pTy is RefTy) {
      final sv =
          (ty as RefTy).llvmType.createAlloca(c, Identifier.builtIn('_deref'));
      final v = load(c);
      final vv = llvm.LLVMBuildLoad2(c.builder, type, v, unname);
      sv.store(c, vv);
      return sv;
    }
    // 不可变会少一次分配
    if (!mut) {
      if (parent is LLVMRefAllocaVariable) {
        return parent;
      }

      final v = load(c);
      return LLVMAllocaVariable(ty, v, type)..isTemp = false;
    }

    StoreVariable sv;
    if (parent is LLVMRefAllocaVariable) {
      sv = LLVMRefAllocaVariable(
          (parent as LLVMRefAllocaVariable).parent, alloca);
    } else {
      final v = load(c);
      sv = LLVMAllocaVariable(ty, v, type)..isTemp = false;
    }
    return sv;
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return c.pointer();
  }

  @override
  Variable getRef(BuildContext c) {
    return create(c, this)..store(c, alloca);
  }
}

class LLVMStructAllocaVariable extends LLVMAllocaVariable {
  LLVMStructAllocaVariable(super.ty, super.alloca, super.type, this.loadTy);
  final LLVMTypeRef loadTy;

  LLVMValueRef load2(BuildContext c, bool extern) {
    if (extern) {
      final arr = c.createAlloca(loadTy, name: 'struct_arr');
      llvm.LLVMBuildMemCpy(
          c.builder, arr, 4, alloca, 4, c.constI64(ty.llvmType.getBytes(c)));
      final v = llvm.LLVMBuildLoad2(c.builder, loadTy, arr, unname);
      return v;
    }
    return load(c);
  }
}

class LLVMTempVariable extends Variable {
  LLVMTempVariable(this.value, this.ty);
  final LLVMValueRef value;

  @override
  final Ty ty;

  @override
  LLVMValueRef load(BuildContext c) {
    return value;
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(value);
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.create(c, this)..store(c, value);
  }
}

class LLVMLitVariable extends Variable {
  LLVMLitVariable(this._load, this.ty);
  @override
  final BuiltInTy ty;
  final LLVMValueRef Function(BuildContext c, BuiltInTy? ty) _load;
  LLVMValueRef? _cache;
  @override
  LLVMValueRef load(BuildContext c, {BuiltInTy? ty}) {
    return _cache ??= _load(c, ty);
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(load(c));
  }

  StoreVariable createAlloca(BuildContext c, [BuiltInTy? tty]) {
    // 需要分配内存地址
    final alloca = ty.llvmType.createAlloca(c, Identifier.builtIn('_ref'));
    final rValue = load(c, ty: tty);
    alloca.store(c, rValue);
    return alloca;
  }

  @override
  Variable getRef(BuildContext c) {
    final alloca = createAlloca(c);
    return LLVMRefAllocaVariable.create(c, alloca)..store(c, alloca.alloca);
  }
}

class LLVMTempOpVariable extends Variable {
  LLVMTempOpVariable(this.ty, this.isFloat, this.isSigned, this.value);
  final bool isSigned;
  final bool isFloat;
  final LLVMValueRef value;
  @override
  final Ty ty;

  @override
  LLVMValueRef load(BuildContext c) {
    return value;
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return llvm.LLVMTypeOf(value);
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.create(c, this)..store(c, value);
  }
}
