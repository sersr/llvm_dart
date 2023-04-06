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

  // @override
  // LLVMRefAllocaVariable getRef(BuildContext c) {
  //   final v = c.createAlloca(type, null, name: 'ref');
  //   final parentType = ty.llvmType.createType(c);
  //   final parentV = LLVMAllocaVariable(ty, v, parentType);
  //   return LLVMRefAllocaVariable(parentV, v);
  //   // return LLVMRefAllocaVariable.create(c, this);
  // }
}

class LLVMRefAllocaVariable extends StoreVariable {
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

  Variable getDeref(BuildContext c, {bool mut = true}) {
    final v = load(c);
    final type = parent.getDerefType(c);

    // 不可变会少一次分配
    if (!mut) {
      if (parent is LLVMRefAllocaVariable) {
        return LLVMRefAllocaVariable(
            (parent as LLVMRefAllocaVariable).parent, v);
      }
      return LLVMAllocaVariable(ty, v, type);
    }

    final vv = llvm.LLVMBuildLoad2(c.builder, type, v, unname);
    final alloca = c.createAlloca(type, name: 'deref');
    StoreVariable sv;
    if (parent is LLVMRefAllocaVariable) {
      sv = LLVMRefAllocaVariable(
          (parent as LLVMRefAllocaVariable).parent, alloca);
    } else {
      sv = LLVMAllocaVariable(ty, alloca, type);
    }
    sv.store(c, vv);
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

// class LLVMRefAndVariable extends StoreVariable
//     implements LLVMRefAllocaVariable {
//   LLVMRefAndVariable(this.parent);
//   @override
//   final LLVMAllocaVariable parent;

//   LLVMValueRef? _alloca;
//   @override
//   LLVMValueRef get alloca => _alloca ?? parent.alloca;
//   @override
//   Ty get ty => parent.ty;

//   @override
//   LLVMValueRef load(BuildContext c) {
//     return alloca;
//   }

//   @override
//   Variable getDeref(BuildContext c, {bool mut = true}) {
//     return parent;
//   }

//   @override
//   LLVMTypeRef getDerefType(BuildContext c) {
//     return parent.type;
//   }

//   @override
//   void store(BuildContext c, LLVMValueRef val) {
//     _alloca = val;
//   }

//   @override
//   Variable getRef(BuildContext c) {
//     return this;
//   }
// }

class LLVMStructAllocaVariable extends LLVMAllocaVariable {
  LLVMStructAllocaVariable(super.ty, super.alloca, super.type, this.loadTy);
  final LLVMTypeRef loadTy;

  LLVMValueRef load2(BuildContext c, bool extern) {
    if (extern) {
      // final ss = llvm.LLVMBuildBitCast(
      //     c.builder, alloca, c.typePointer(type), '.s.s.'.toChar());
      // final ss = llvm.LLVMBuildPointerCast(
      //     c.builder, alloca, c.typePointer(type), 'ssaxx'.toChar());
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
