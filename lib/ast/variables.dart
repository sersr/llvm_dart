import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'context.dart';
import 'memory.dart';
import 'tys.dart';

class EnumItemVariable extends Variable {
  EnumItemVariable(this.ty);
  @override
  final EnumItem ty;
  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  Variable getRef(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  LLVMValueRef load(BuildContext c) {
    throw UnimplementedError();
  }

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    throw UnimplementedError();
  }
}

class LLVMConstVariable extends Variable {
  LLVMConstVariable(this.value, this.ty);
  @override
  final Ty ty;

  final LLVMValueRef value;

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return value;
  }

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

abstract class Deref extends Variable {
  Variable getDeref(BuildContext c);
}

class LLVMRefAllocaVariable extends StoreVariable implements Deref {
  LLVMRefAllocaVariable(this.ty, this.alloca);
  @override
  final LLVMValueRef alloca;
  @override
  bool get isRef => true;

  static LLVMRefAllocaVariable create(BuildContext c, Variable parent) {
    final rr = RefTy(parent.ty);
    final alloca = rr.llvmType.createAlloca(c, Identifier.none);
    return LLVMRefAllocaVariable(rr, alloca.alloca);
  }

  static StoreVariable from(LLVMValueRef value, Ty ty, BuildContext c) {
    if (ty is RefTy) {
      return LLVMRefAllocaVariable(ty, value);
    }
    final type = ty.llvmType.createType(c);
    return LLVMAllocaVariable(ty, value, type);
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
  late final RefTy ty;

  @override
  Variable getDeref(BuildContext c) {
    final parentTy = ty.parent;
    final type = parentTy.llvmType.createType(c);
    final v = load(c);

    StoreVariable val;
    if (parentTy is RefTy) {
      val = LLVMRefAllocaVariable(parentTy, v);
    } else {
      val = LLVMAllocaVariable(parentTy, v, type);
    }
    val.isTemp = false;
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
  LLVMStructAllocaVariable(super.ty, super.alloca, super.type, this.loadTy,
      {this.isCurrent = false});
  final LLVMTypeRef loadTy;
  bool extern = false;

  final bool isCurrent;
  @override
  LLVMValueRef load(BuildContext c) {
    if (isCurrent) return alloca;
    return super.load(c);
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

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return value;
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

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return value;
  }
}
