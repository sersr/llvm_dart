import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../context.dart';
import '../memory.dart';
import '../tys.dart';

abstract class Variable extends IdentVariable {
  bool isRef = false;
  LLVMValueRef load(BuildContext c);
  LLVMTypeRef getDerefType(BuildContext c);
  Variable getRef(BuildContext c);

  LLVMValueRef getBaseValue(BuildContext c) => load(c);
  Ty get ty;
}

abstract class StoreVariable extends Variable {
  /// 一般是未命名的，右表达式生成的
  bool isTemp = true;
  LLVMValueRef get alloca;
  LLVMValueRef store(BuildContext c, LLVMValueRef val);

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return alloca;
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
    return LLVMRefAllocaVariable.cc(c, this, value);
  }
}

mixin DelayVariableMixin {
  LLVMValueRef Function([StoreVariable? alloca]) get _create;

  LLVMValueRef? _alloca;

  bool _created = false;

  bool create([StoreVariable? alloca]) {
    final result = _alloca == null;
    _alloca ??= _inCreate(alloca);
    return result;
  }

  LLVMValueRef _inCreate([StoreVariable? alloca]) {
    _created = true;
    return _create(alloca);
  }

  LLVMValueRef get alloca => _alloca ??= _inCreate();
}

/// [unused]
class LLVMAllocaDelayVariable extends StoreVariable with DelayVariableMixin {
  LLVMAllocaDelayVariable(this.ty, this._create, this.type) : _allocaI = null;
  LLVMAllocaDelayVariable.def(
      this.ty, LLVMValueRef this._allocaI, this._create, this.type);
  @override
  final LLVMValueRef Function([StoreVariable? alloca]) _create;
  final LLVMValueRef? _allocaI;
  @override
  final Ty ty;

  final LLVMTypeRef type;
  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return type;
  }

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    if (_allocaI != null && !_created) {
      return _allocaI!;
    }
    return super.getBaseValue(c);
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.cc(c, this, alloca);
  }

  @override
  LLVMValueRef load(BuildContext c) {
    if (_allocaI != null && !_created) {
      return _allocaI!;
    }
    return llvm.LLVMBuildLoad2(c.builder, type, alloca, unname);
  }

  @override
  LLVMValueRef store(BuildContext c, LLVMValueRef val) {
    return llvm.LLVMBuildStore(c.builder, val, alloca);
  }
}

class LLVMRefValue extends StoreVariable implements Deref {
  LLVMRefValue(this.ty, this.alloca, this.type);
  final LLVMTypeRef type;
  @override
  final Ty ty;
  @override
  final LLVMValueRef alloca;

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return ty.llvmType.createType(c);
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable(RefTy(ty), alloca);
  }

  @override
  LLVMValueRef load(BuildContext c) {
    final ptr = llvm.LLVMBuildLoad2(c.builder, c.pointer(), alloca, unname);
    return llvm.LLVMBuildLoad2(c.builder, type, ptr, unname);
  }

  @override
  LLVMValueRef store(BuildContext c, LLVMValueRef val) {
    return llvm.LLVMBuildStore(c.builder, val, alloca);
  }

  @override
  Variable getDeref(BuildContext c) {
    final cTy = ty;
    final v = load(c);

    StoreVariable val;
    if (cTy is RefTy) {
      final parent = cTy.parent;
      if (parent is RefTy) {
        val = LLVMRefAllocaVariable(parent, v);
      } else {
        final type = parent.llvmType.createType(c);
        val = LLVMAllocaVariable(parent, v, type);
      }
    } else {
      final type = cTy.llvmType.createType(c);
      val = LLVMAllocaVariable(cTy, v, type);
    }
    val.isTemp = false;
    return val;
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
  LLVMValueRef store(BuildContext c, LLVMValueRef val) {
    return llvm.LLVMBuildStore(c.builder, val, alloca);
  }

  @override
  LLVMTypeRef getDerefType(BuildContext c) {
    return type;
  }

  @override
  Variable getRef(BuildContext c) {
    return LLVMRefAllocaVariable.cc(c, this, alloca);
  }
}

abstract class Deref extends Variable {
  Variable getDeref(BuildContext c);
}

class LLVMRefAllocaVariable extends StoreVariable
    with DelayVariableMixin
    implements Deref {
  LLVMRefAllocaVariable(this.ty, this._allocaI);
  LLVMRefAllocaVariable.delay(
    this.ty,
    this._allocaI,
    this._create,
  );

  final LLVMValueRef _allocaI;

  static LLVMRefAllocaVariable cc(
      BuildContext c, Variable parent, LLVMValueRef ref) {
    final rr = RefTy(parent.ty);
    return LLVMRefAllocaVariable.delay(rr, ref, ([StoreVariable? alloca]) {
      final alloca = rr.llvmType.createAlloca(c, Identifier.none);
      return alloca.alloca;
    });
  }

  static StoreVariable from(LLVMValueRef value, Ty ty, BuildContext c) {
    if (ty is RefTy) {
      return LLVMRefAllocaVariable(ty, value);
    }
    final type = ty.llvmType.createType(c);
    return LLVMAllocaVariable(ty, value, type);
  }

  bool _stored = false;
  @override
  LLVMValueRef load(BuildContext c) {
    if (!_stored) {
      return _allocaI;
    }
    return llvm.LLVMBuildLoad2(c.builder, c.pointer(), alloca, unname);
  }

  @override
  LLVMValueRef store(BuildContext c, LLVMValueRef val) {
    _stored = true;
    return llvm.LLVMBuildStore(c.builder, val, alloca);
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
    return cc(c, this, alloca);
  }

  @override
  late LLVMValueRef Function([StoreVariable? alloca]) _create = _defCreate;

  LLVMValueRef _defCreate([StoreVariable? alloca]) {
    return _allocaI;
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
    return LLVMRefAllocaVariable.cc(c, this, value);
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
    // final rty = tty ?? ty;
    final rValue = load(c, ty: tty);
    final alloca = ty.llvmType.createAlloca(c, Identifier.builtIn('_ref'));
    alloca.store(c, rValue);

    // string 以指针形式存在，访问一次[load]会加载指针，以引用作为基本形式
    // if (rty.ty == LitKind.kString) {
    //   return LLVMRefAllocaVariable.create(c, alloca)..store(c, alloca.load(c));
    // }

    return alloca;
  }

  @override
  LLVMRefAllocaVariable getRef(BuildContext c) {
    final alloca = createAlloca(c);
    return LLVMRefAllocaVariable.cc(c, alloca, alloca.alloca);
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
    return LLVMRefAllocaVariable.cc(c, this, value);
  }

  @override
  LLVMValueRef getBaseValue(BuildContext c) {
    return value;
  }
}

abstract class UnimplVariable extends Variable {
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

class TyVariable extends UnimplVariable {
  TyVariable(this.ty);
  @override
  final Ty ty;
}
