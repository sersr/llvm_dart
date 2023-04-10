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
  Variable getDeref(BuildContext c);
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
  late final Ty ty = parent.ty;

  @override
  Variable getDeref(BuildContext c) {
    final type = parent.getDerefType(c);
    final v = load(c);
    final parentTy = parent.ty;
    StoreVariable val;
    if (parentTy is RefTy) {
      val = parentTy.llvmType.createAlloca(c, Identifier.builtIn('_deref'));
      final vv = llvm.LLVMBuildLoad2(c.builder, type, v, unname);
      val.store(c, vv);
    } else {
      val = LLVMAllocaVariable(parentTy, v, type)..isTemp = false;
    }
    return val;
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
    final rty = tty ?? ty;
    final rValue = load(c, ty: tty);
    final alloca = ty.llvmType.createAlloca(c, Identifier.builtIn('_ref'));
    alloca.store(c, rValue);

    // string 以指针形式存在，访问一次[load]会加载指针，以引用作为基本形式
    if (rty.ty == LitKind.kString) {
      return LLVMRefAllocaVariable.create(c, alloca)..store(c, alloca.alloca);
    }

    return alloca;
  }

  @override
  LLVMRefAllocaVariable getRef(BuildContext c) {
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