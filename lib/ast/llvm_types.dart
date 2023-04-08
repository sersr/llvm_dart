import 'package:llvm_dart/ast/analysis_context.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'llvm_context.dart';
import 'memory.dart';
import 'variables.dart';

abstract class LLVMType {
  Ty get ty;
  int getBytes(BuildContext c);
  LLVMTypeRef createType(BuildContext c);

  StoreVariable createAlloca(BuildContext c, Identifier ident) {
    final type = createType(c);
    final v = c.createAlloca(type, name: ident.src);
    return LLVMAllocaVariable(ty, v, type);
  }

  StoreVariable createMalloc(BuildContext c, Identifier ident) {
    final type = createType(c);
    final v = c.createAlloca(type, name: ident.src);
    return LLVMAllocaVariable(ty, v, type);
  }
}

class LLVMTypeLit extends LLVMType {
  LLVMTypeLit(this.ty);
  @override
  final BuiltInTy ty;

  @override
  LLVMTypeRef createType(BuildContext c) {
    final kind = ty.ty.convert;
    LLVMTypeRef type;
    switch (kind) {
      case LitKind.usize:
        final size = c.pointerSize();
        if (size == 8) {
          type = c.i64;
        } else {
          type = c.i32;
        }
        break;
      case LitKind.kDouble:
      case LitKind.f64:
        type = c.f64;
        break;
      case LitKind.kFloat:
      case LitKind.f32:
        type = c.f32;
        break;
      case LitKind.kBool:
        type = c.i1;
        break;
      case LitKind.i8:
        type = c.i8;
        break;
      case LitKind.i16:
        type = c.i16;
        break;
      case LitKind.i64:
        type = c.i64;
        break;
      case LitKind.i128:
        type = c.i128;
        break;
      case LitKind.kString:
        type = c.pointer();
        break;
      case LitKind.kVoid:
        type = c.typeVoid;
        break;
      case LitKind.i32:
      case LitKind.kInt:
      default:
        type = c.i32;
    }
    return type;
  }

  Variable createValue(BuildContext c, {String str = ''}) {
    LLVMValueRef v(BuildContext c, BuiltInTy? bty) {
      final raw = LLVMRawValue(str);
      final rTy = bty ?? ty;
      final kind = rTy.ty.convert;

      switch (kind) {
        case LitKind.f32:
        case LitKind.kFloat:
          return c.constF32(raw.value);
        case LitKind.f64:
        case LitKind.kDouble:
          return c.constF64(raw.value);
        case LitKind.kString:
          return c.constStr(raw.raw);
        case LitKind.kBool:
          return c.constI1(raw.raw == 'true' ? 1 : 0);
        case LitKind.i8:
          return c.constI8(raw.iValue, kind.signed);
        case LitKind.i16:
          return c.constI16(raw.iValue, kind.signed);
        case LitKind.i64:
          return c.constI64(raw.iValue, kind.signed);
        case LitKind.i128:
          return c.constI128(raw.raw, kind.signed);
        case LitKind.usize:
          return c.pointerSize() == 8
              ? c.constI64(raw.iValue)
              : c.constI32(raw.iValue);
        case LitKind.kInt:
        case LitKind.i32:
        default:
          return c.constI32(raw.iValue, kind.signed);
      }
    }

    return LLVMLitVariable(v, ty);
  }

  @override
  int getBytes(BuildContext c) {
    final kind = ty.ty;
    switch (kind) {
      case LitKind.kDouble:
      case LitKind.f64:
      case LitKind.i64:
        return 8;
      case LitKind.kFloat:
      case LitKind.f32:
      case LitKind.i32:
      case LitKind.kInt:
        return 4;
      case LitKind.kBool:
      case LitKind.i8:
      case LitKind.u8:
        return 1;
      case LitKind.i16:
        return 2;
      case LitKind.i128:
        return 16;
      case LitKind.kString:
        return 1;
      case LitKind.kVoid:
      default:
        return 0;
    }
  }
}

class LLVMFnType extends LLVMType {
  LLVMFnType(this.fn);
  final Fn fn;
  @override
  Ty get ty => fn;

  @override
  StoreVariable createAlloca(BuildContext c, Identifier ident) {
    final type = c.pointer();
    final v = c.createAlloca(type, name: ident.src);
    return LLVMAllocaVariable(ty, v, type);
  }

  @protected
  @override
  LLVMTypeRef createType(BuildContext c) {
    return c.pointer();
  }

  LLVMTypeRef createFnType(BuildContext c, [Set<AnalysisVariable>? variables]) {
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];

    if (fn is ImplFn) {
      final ty = c.pointer();
      list.add(ty);
    }

    for (var p in params) {
      final realTy = p.ty.grt(c);
      LLVMTypeRef ty = realTy.llvmType.createType(c);
      if (p.isRef) {
        ty = c.typePointer(ty);
      } else {
        if (realTy is StructTy && fn.extern) {
          final size = realTy.llvmType.getBytes(c);
          ty = c.getStructExternType(size);
        }
      }
      list.add(ty);
      // }
    }
    final vv = [...fn.variables, ...?variables];
    for (var variable in vv) {
      final v = c.getVariable(variable.ident);
      if (v != null) {
        final dty = v.ty;
        LLVMTypeRef ty = dty.llvmType.createType(c);
        // if (v.isRef) {
        ty = c.typePointer(ty);
        // } else {
        //   if (dty is StructTy && fn.extern) {
        //     final size = dty.llvmType.getBytes(c);
        //     ty = c.getStructExternType(size);
        //   }
        // }
        list.add(ty);
      }
    }

    LLVMTypeRef ret;
    var retTy = fn.fnSign.fnDecl.returnTy.grt(c);
    if (fn.extern && retTy is StructTy) {
      final size = retTy.llvmType.getBytes(c);
      ret = c.getStructExternType(size);
      // ret = c.typePointer();
    } else {
      ret = retTy.llvmType.createType(c);
    }

    return c.typeFn(list, ret);
  }

  late final _cacheFns = <ListKey, LLVMConstVariable>{};

  LLVMConstVariable createFunction(BuildContext c,
      [Set<AnalysisVariable>? variables]) {
    final key = ListKey(variables?.toList() ?? []);

    return _cacheFns.putIfAbsent(key, () {
      final ty = createFnType(c, variables);
      final ident = fn.fnSign.fnDecl.ident.src;
      final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
      llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);
      return LLVMConstVariable(v, fn);
    });
  }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }
}

class LLVMStructType extends LLVMType {
  LLVMStructType(this.ty);
  @override
  final StructTy ty;

  LLVMTypeRef? _type;
  @override
  LLVMTypeRef createType(BuildContext c) {
    if (_type != null) return _type!;
    final vals = <LLVMTypeRef>[];
    final struct = ty;

    for (var field in struct.fields) {
      var rty = field.ty.grt(c);
      if (rty is FnTy) {
        vals.add(c.pointer());
      } else {
        final ty = rty.llvmType.createType(c);
        if (field.isRef) {
          vals.add(c.typePointer(ty));
        } else {
          vals.add(ty);
        }
      }
    }

    return _type = c.typeStruct(vals, ty.ident);
  }

  Variable? getField(
      StoreVariable alloca, BuildContext context, Identifier ident) {
    final index = ty.fields.indexWhere((element) => element.ident == ident);
    if (index == -1) return null;
    final indics = <LLVMValueRef>[];
    final field = ty.fields[index];
    indics.add(context.constI32(0));
    indics.add(context.constI32(index));
    LLVMValueRef v = alloca.alloca;
    LLVMTypeRef type = createType(context);
    if (alloca is LLVMRefAllocaVariable) {
      v = alloca.load(context);
      type = context.pointer();
    }

    final c = llvm.LLVMBuildInBoundsGEP2(
        context.builder, type, v, indics.toNative(), indics.length, unname);
    final grt = field.ty.grt(context);
    var fty = grt.llvmType.createType(context);

    final value = LLVMAllocaVariable(grt, c, fty)..isTemp = false;
    final newVal = PointerKind.refDerefs(value, context, field.kinds);
    return newVal ?? value;
  }

  LLVMStructAllocaVariable createValue(BuildContext c) {
    final type = createType(c);

    final size = getBytes(c);
    final loadTy = c.getStructExternType(size);

    final alloca = c.alloctor(type, '_');
    return LLVMStructAllocaVariable(ty, alloca, type, loadTy);
  }

  @override
  LLVMStructAllocaVariable createAlloca(BuildContext c, Identifier ident) {
    final type = createType(c);
    final size = getBytes(c);
    final loadTy = c.getStructExternType(size);
    final alloca = c.alloctor(type, ident.src);
    return LLVMStructAllocaVariable(ty, alloca, type, loadTy);
  }

  LLVMStructAllocaVariable createAllocaFromParam(
      BuildContext c, LLVMValueRef value, Identifier ident, bool extern) {
    final allx = createAlloca(c, ident);
    if (!extern) return allx;

    /// extern "C"
    final type = createType(c);
    final size = getBytes(c);
    final loadTy = c.getStructExternType(size); // array
    final arrTy = c.alloctor(loadTy, 'param_$ident');
    llvm.LLVMBuildStore(c.builder, value, arrTy);

    // copy
    llvm.LLVMBuildMemCpy(
        c.builder, allx.alloca, 4, arrTy, 4, c.constI64(getBytes(c)));

    return LLVMStructAllocaVariable(ty, arrTy, loadTy, type);
  }

  @override
  int getBytes(BuildContext c) {
    var size = 0;
    for (var field in ty.fields) {
      final tsize = field.ty.grt(c).llvmType.getBytes(c);
      size += tsize;
    }
    return size;
  }
}

// class PointerTy extends Ty {
//   @override
//   void analysis(AnalysisContext context) {}

//   @override
//   void build(BuildContext context) {}

//   @override
//   LLVMType get llvmType => LLVMPointerType(this);

//   @override
//   List<Object?> get props => throw UnimplementedError();
// }

// class LLVMPointerType extends LLVMType {
//   LLVMPointerType(this.ty);
//   final PointerTy ty;
//   @override
//   LLVMTypeRef createType(BuildContext c) {
//     throw UnimplementedError();
//   }

//   @override
//   int getBytes(BuildContext c) {
//     throw UnimplementedError();
//   }
// }

class LLVMRefType extends LLVMType {
  LLVMRefType(this.ty);
  @override
  final RefTy ty;
  Ty get parent => ty.parent;
  @override
  LLVMTypeRef createType(BuildContext c) {
    return ref(c);
  }

  LLVMTypeRef ref(BuildContext c) {
    return c.typePointer(parent.llvmType.createType(c));
  }

  @override
  LLVMRefAllocaVariable createAlloca(BuildContext c, Identifier ident) {
    final type = createType(c);
    final v = c.createAlloca(type, name: ident.src);
    final parentType = parent.llvmType.createType(c);
    final parentV = LLVMAllocaVariable(parent, v, parentType);
    return LLVMRefAllocaVariable(parentV, v);
  }

  // Variable createRefAlloca(
  //     BuildContext c, LLVMValueRef alloca, Identifier ident) {
  //   final t = createType(c);
  //   final allt = LLVMAllocaVariable(ty, alloca, t);
  //   return LLVMRefAllocaVariable.create(c, allt);
  // }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }
}
