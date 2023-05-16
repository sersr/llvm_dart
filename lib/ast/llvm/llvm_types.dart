import 'dart:ffi';

import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../expr.dart';
import '../memory.dart';
import 'build_methods.dart';
import 'llvm_context.dart';
import 'variables.dart';

class LLVMRawValue {
  LLVMRawValue(this._raw);
  final String _raw;

  String get raw => _raw;
  String get rawNumber => _raw.replaceAll('_', '');

  Pointer<Char> toChar() {
    return raw.toChar();
  }

  double get value {
    return double.parse(rawNumber);
  }

  int get iValue {
    return int.parse(rawNumber);
  }
}

abstract class LLVMType {
  Ty get ty;
  int getBytes(BuildContext c);
  LLVMTypeRef createType(BuildContext c);

  StoreVariable createAlloca(BuildContext c, Identifier ident) {
    // final type = createType(c);
    // final v = c.createAlloca(type, name: ident.src);
    // final val = LLVMAllocaVariable(ty, v, type);
    final type = createType(c);
    final val = LLVMAllocaDelayVariable(ty, ([alloca]) {
      return c.alloctor(type, ident.src);
    }, type);
    if (ident.isValid) {
      val.ident = ident;
    }
    return val;
  }

  StoreVariable createMalloc(BuildContext c, Identifier ident) {
    final type = createType(c);
    final v = c.createMalloc(type, name: ident.src);
    return LLVMAllocaVariable(ty, v, type);
  }
}

class LLVMTypeLit extends LLVMType {
  LLVMTypeLit(this.ty);
  @override
  final BuiltInTy ty;

  @override
  LLVMTypeRef createType(BuildContext c) {
    return litType(c);
  }

  LLVMTypeRef litType(BuildMethods c) {
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

  LLVMLitVariable createValue({String str = ''}) {
    final raw = LLVMRawValue(str);
    LLVMValueRef v(Consts c, BuiltInTy? bty) {
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
          return c.getString(raw.raw);
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

    return LLVMLitVariable(v, ty, raw);
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
      case LitKind.usize:
        return c.pointerSize();
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

  Variable createAllocaParam(
      BuildContext c, Identifier ident, LLVMValueRef val) {
    return LLVMTempVariable(val, ty);
  }

  @protected
  @override
  LLVMTypeRef createType(BuildContext c) {
    return c.pointer();
  }

  LLVMTypeRef createFnType(BuildContext c, [Set<AnalysisVariable>? variables]) {
    // ignore: invalid_use_of_protected_member
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];
    var retTy = fn.getRetTy(c);

    var retIsRet = isSret(c);
    if (retIsRet) {
      list.add(c.typePointer(retTy.llvmType.createType(c)));
    }

    if (fn is ImplFn) {
      LLVMTypeRef ty;
      final tty = (fn as ImplFn).ty;
      if (tty is BuiltInTy) {
        ty = tty.llvmType.createType(c);
      } else {
        ty = c.pointer();
      }
      list.add(ty);
    }

    LLVMTypeRef cType(Ty tty) {
      LLVMTypeRef ty;
      if (tty is StructTy && fn.extern) {
        final size = tty.llvmType.getCBytes(c);
        if (size <= 16) {
          ty = c.getStructExternType(size);
        } else {
          ty = c.pointer();
        }
      } else {
        ty = tty.llvmType.createType(c);
      }
      return ty;
    }

    for (var p in params) {
      final realTy = fn.getRty(c, p);
      LLVMTypeRef ty;
      if (!p.isRef) {
        ty = realTy.llvmType.createType(c);
      } else {
        ty = cType(realTy);
      }
      list.add(ty);
    }
    final vv = [...fn.variables, ...?variables];

    for (var variable in vv) {
      final v = c.getVariable(variable.ident);

      if (v != null) {
        final dty = v.ty;
        LLVMTypeRef ty = dty.llvmType.createType(c);
        ty = c.typePointer(ty);

        list.add(ty);
      }
    }

    LLVMTypeRef ret;

    if (retIsRet) {
      ret = c.typeVoid;
    } else {
      ret = cType(retTy);
    }

    return c.typeFn(list, ret, fn.fnSign.fnDecl.isVar);
  }

  bool isSret(BuildContext c) {
    var retTy = fn.getRetTy(c);
    if (retTy is StructTy) {
      final size = retTy.llvmType.getCBytes(c);
      if (size > 16) return true;
    }
    return false;
  }

  late final _cacheFns = <ListKey, LLVMConstVariable>{};

  LLVMConstVariable createFunction(BuildContext c,
      [Set<AnalysisVariable>? variables]) {
    final key = ListKey(variables?.toList() ?? []);

    return _cacheFns.putIfAbsent(key, () {
      final ty = createFnType(c, variables);
      var ident = fn.fnSign.fnDecl.ident.src;
      if (ident.isEmpty) {
        ident = '_fn';
      }
      final extern = fn.extern || ident == 'main';

      if (_cacheFns.isNotEmpty) {
        ident = '${ident}_${_cacheFns.length}';
      }
      final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
      llvm.LLVMSetLinkage(
          v,
          extern
              ? LLVMLinkage.LLVMExternalLinkage
              : LLVMLinkage.LLVMInternalLinkage);
      // llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);

      var retTy = fn.getRetTy(c);
      if (isSret(c)) {
        LLVMTypeRef ty = c.typePointer(retTy.llvmType.createType(c));

        final attr = llvm.LLVMCreateStructRetAttr(c.llvmContext, ty);

        llvm.LLVMAddAttributeAtIndex(v, 1, attr);
      }

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

  FieldsSize? _size;

  FieldsSize getFieldsSize(BuildContext c) =>
      _size ??= alignType(c, ty.fields, sort: !ty.extern);

  int getMinSize(BuildContext c) {
    return ty.fields.fold<int>(100, (p, e) {
      final size = e.grt(c).llvmType.getBytes(c);
      return p > size ? size : p;
    });
  }

  int getMaxSize(BuildContext c) {
    return ty.fields.fold<int>(100, (p, e) {
      final size = e.grt(c).llvmType.getBytes(c);
      return p < size ? size : p;
    });
  }

  @override
  LLVMTypeRef createType(BuildContext c) {
    final struct = ty;
    final extern = struct.extern;
    if (extern) return cCreateType(c);
    final size = getFieldsSize(c);
    if (_type != null) return _type!;

    final vals = <LLVMTypeRef>[];

    final fields = extern ? struct.fields : size.map.keys.toList();

    for (var field in fields) {
      var rty = field.grt(c);
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

    return _type = c.typeStruct(vals, ty.ident.src);
  }

  LLVMTypeRef? _cType;
  LLVMTypeRef cCreateType(BuildContext c) {
    if (_cType != null) return _cType!;
    final struct = ty;
    final fields = struct.fields;
    final vals = <LLVMTypeRef>[];

    for (var field in fields) {
      var rty = field.grt(c);
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
    return _cType = c.typeStruct(vals, '${ty.ident.src}.c');
  }

  StoreVariable? getField(
      Variable alloca, BuildContext context, Identifier ident,
      {bool useExtern = false}) {
    final extern = useExtern || ty.extern;
    LLVMTypeRef type = useExtern ? cCreateType(context) : createType(context);

    final fields = ty.fields;
    final index = fields.indexWhere((element) => element.ident == ident);
    if (index == -1) return null;
    final field = fields[index];
    final rTy = field.grt(context);

    // if (index == 0) {
    //   final val = LLVMRefAllocaVariable.from(
    //       alloca.getBaseValue(context), rTy, context);
    //   val.isTemp = false;
    //   return val;
    // }

    // final indics = <LLVMValueRef>[];
    final rIndex = extern ? index : _size!.map[field]!.index;
    LLVMValueRef v = alloca.getBaseValue(context);

    // indics.add(context.constI32(0));
    // indics.add(context.constI32(rIndex));
    LLVMValueRef fieldValue;
    // if (alloca is StoreVariable) {
    //   fieldValue = llvm.LLVMBuildInBoundsGEP2(
    //       context.builder, type, v, indics.toNative(), indics.length, unname);
    // } else {
    fieldValue =
        llvm.LLVMBuildStructGEP2(context.builder, type, v, rIndex, unname);
    // }

    final val = LLVMRefAllocaVariable.from(fieldValue, rTy, context);

    val.isTemp = false;
    return val;
  }

  LLVMValueRef load2(BuildContext c, Variable v, bool isExternFnParam) {
    if (!isExternFnParam) {
      final llValue = v.load(c);
      return llValue;
    }

    Variable alloca;

    if (!ty.extern) {
      alloca = _createExternAlloca(c, Identifier.builtIn('${v.ident}_c'));
      for (var p in ty.fields) {
        final srcVal = getField(v, c, p.ident)!;
        final destVal = getField(alloca, c, p.ident, useExtern: true)!;
        destVal.store(c, srcVal.load(c));
      }
    } else {
      alloca = v;
    }

    final size = getCBytes(c);
    if (size <= 16) {
      final loadTy = c.getStructExternType(size);
      final arr = c.createAlloca(loadTy, name: 'struct_arr');
      llvm.LLVMBuildMemCpy(
          c.builder, arr, 4, alloca.getBaseValue(c), 4, c.constI64(size));
      return llvm.LLVMBuildLoad2(c.builder, loadTy, arr, unname);
    }
    return alloca.getBaseValue(c);
  }

  @override
  LLVMAllocaDelayVariable createAlloca(BuildContext c, Identifier ident) {
    final type = createType(c);
    return LLVMAllocaDelayVariable(ty, ([alloca]) {
      return c.alloctor(type, ident.src);
    }, type);
    // return LLVMAllocaVariable(ty, alloca, type);
  }

  LLVMAllocaVariable _createExternAlloca(BuildContext c, Identifier ident) {
    final type = cCreateType(c);
    final alloca = c.alloctor(type, ident.src);
    return LLVMAllocaVariable(ty, alloca, type);
  }

  StoreVariable createAllocaFromParam(BuildContext c, LLVMValueRef value,
      Identifier ident, bool isExternFnParam) {
    final extern = isExternFnParam;
    if (!extern) {
      final v = createAlloca(c, ident);
      c.setName(v.alloca, ident.src);
      v.store(c, value);
      v.isTemp = false;
      return v;
    }
    StoreVariable calloca;

    final size = getCBytes(c);

    if (size <= 16) {
      calloca = _createExternAlloca(c, ident);
      calloca.isTemp = false;

      /// extern "C"
      final size = getBytes(c);
      final loadTy = c.getStructExternType(size); // array
      final arrTy = c.alloctor(loadTy, 'param_$ident');
      llvm.LLVMBuildStore(c.builder, value, arrTy);

      // copy
      llvm.LLVMBuildMemCpy(
          c.builder, calloca.alloca, 4, arrTy, 4, c.constI64(size));
    } else {
      calloca = LLVMAllocaVariable(ty, value, cCreateType(c))..isTemp = false;
      c.setName(calloca.alloca, ident.src);
    }
    // 位置不变 "C"
    if (ty.extern) return calloca;

    final alloca = createAlloca(c, ident);
    for (var p in ty.fields) {
      final srcVal = getField(calloca, c, p.ident, useExtern: true)!;
      final destVal = getField(alloca, c, p.ident)!;
      destVal.store(c, srcVal.load(c));
    }
    return alloca;
  }

  @override
  int getBytes(BuildContext c) {
    return c.typeSize(createType(c));
  }

  int getCBytes(BuildContext c) {
    return c.typeSize(cCreateType(c));
  }

  static FieldsSize alignType(BuildContext c, List<FieldDef> fields,
      {bool sort = false}) {
    var alignSize = fields.fold<int>(0, (previousValue, element) {
      final size = element.grt(c).llvmType.getBytes(c);
      if (previousValue > size) return previousValue;
      return size;
    });
    final targetSize = c.pointerSize();

    if (alignSize > targetSize) {
      alignSize = targetSize;
    }

    final newList = List.of(fields);
    if (sort) {
      newList.sort((p, n) {
        final pre = p.grt(c).llvmType.getBytes(c);
        final next = n.grt(c).llvmType.getBytes(c);
        return pre < next ? 1 : -1;
      });
    }

    var count = 0;
    final map = <FieldDef, FieldIndex>{};
    var index = 0;
    for (var field in newList) {
      var rty = field.grt(c);
      var currentSize = 0;
      if (rty is FnTy) {
        currentSize = c.pointerSize();
      } else {
        final ty = rty.llvmType.createType(c);
        if (field.isRef) {
          currentSize = c.pointerSize();
        } else {
          currentSize = c.typeSize(ty);
        }
      }
      var newCount = count + currentSize;
      final lastIndex = count ~/ targetSize;
      final nextIndex = newCount / targetSize;
      if (lastIndex == nextIndex) {
        count = newCount;
        map[field] = FieldIndex(0, index);
        index += 1;
        continue;
      }
      final whiteSpace = newCount % targetSize;
      if (whiteSpace > 0) {
        final extra = targetSize - whiteSpace;
        map[field] = FieldIndex(extra, index);
        index += 1;
        count = newCount + extra;
      } else {
        map[field] = FieldIndex(0, index);
        count = newCount;
        index += 1;
      }
    }

    return FieldsSize(map, count, alignSize);
  }
}

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
  StoreVariable createAlloca(BuildContext c, Identifier ident,
      {bool isPointer = true}) {
    final type = createType(c);
    final v = c.createAlloca(type, name: ident.src);
    if (isPointer) {
      return LLVMRefAllocaVariable(ty, v);
    } else {
      return LLVMRefValue(parent, v, parent.llvmType.createType(c));
    }
  }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }
}

class LLVMEnumType extends LLVMType {
  LLVMEnumType(this.ty);
  @override
  final EnumTy ty;

  LLVMTypeRef? _type;

  static const int32Max = (1 << 31) - 1;
  static const int8Max = (1 << 7) - 1;

  @override
  LLVMTypeRef createType(BuildContext c) {
    if (_type != null) return _type!;
    final size = getItemBytes(c);
    final index = getIndexType(c);
    final s = getRealIndexType(c);
    LLVMTypeRef tyx;
    if (s == 1) {
      tyx = c.arrayType(c.i8, size - 1);
    } else if (s == 4) {
      final fc = (size / 4).ceil();
      tyx = c.arrayType(c.i32, fc - 1);
    } else {
      final item = c.getStructExternType(size);
      tyx = item;
    }

    return _type = c.typeStruct([index, tyx], ty.ident.src);
  }

  LLVMTypeRef getIndexType(BuildContext c) {
    final size = getRealIndexType(c);
    if (size == 8) {
      return c.i64;
    } else if (size == 4) {
      return c.i32;
    }
    return c.i8;
  }

  int getItemBytes(BuildContext c) {
    final fSize = ty.variants.fold<int>(0, (previousValue, element) {
      final esize = element.llvmType.getSuperBytes(c);
      if (previousValue > esize) return previousValue;
      return esize;
    });
    return fSize;
  }

  LLVMValueRef getIndexValue(BuildContext c, int v) {
    final s = getRealIndexType(c);
    if (s > 4) {
      return c.constI64(v);
    } else if (s > 1) {
      return c.constI32(v);
    }
    return c.constI8(v);
  }

  int? _minSize;

  int getRealIndexType(BuildContext c) {
    if (_minSize != null) return _minSize!;
    final size = ty.variants.length;
    final minSize = ty.variants.fold<int>(100, (previousValue, element) {
      final esize = element.llvmType.getMinSize(c);
      if (esize < previousValue) return esize;
      return previousValue;
    });
    int m;
    if (minSize > 4) {
      m = 8;
    } else if (size > int32Max) {
      m = 8;
    } else if (size > int8Max) {
      m = 4;
    } else if (minSize > 1) {
      m = 4;
    } else {
      m = 1;
    }
    return _minSize = m;
  }

  int? _total;
  @override
  int getBytes(BuildContext c) {
    if (_total != null) return _total!;
    final size = getItemBytes(c);
    final indexSize = getRealIndexType(c);
    final total = size + indexSize;
    final csize = c.pointerSize();
    if (total <= csize) {
      return _total = csize;
    }
    return _total = (total / csize).ceil();
  }
}

class LLVMEnumItemType extends LLVMStructType {
  LLVMEnumItemType(EnumItem super.ty);
  @override
  EnumItem get ty => super.ty as EnumItem;
  LLVMEnumType get pTy => ty.parent.llvmType;

  @override
  LLVMTypeRef createType(BuildContext c, {bool extern = false}) {
    if (_type != null) return _type!;
    final vals = <LLVMTypeRef>[];
    final struct = ty;
    final m = pTy.getRealIndexType(c);
    final size = _size ??=
        alignType(c, struct.ident, struct.fields, initValue: m, sort: true);
    final fields = size.map.keys.toList();

    // 以数组的形式表示占位符
    vals.add(c.arrayType(pTy.getIndexType(c), 1));

    for (var field in fields) {
      var rty = field.grt(c);
      final space = size.map[field]!.space;
      if (space > 0) {
        if (space % 4 == 0) {
          vals.add(c.arrayType(c.i32, space ~/ 4));
        } else {
          vals.add(c.arrayType(c.i8, space));
        }
      }
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

    return _type = c.typeStruct(vals, ty.ident.src);
  }

  static FieldsSize alignType(
      BuildContext c, Identifier ident, List<FieldDef> fields,
      {int initValue = 0, bool sort = false}) {
    final targetSize = c.pointerSize();
    var alignSize = fields.fold<int>(0, (previousValue, element) {
      final size = element.grt(c).llvmType.getBytes(c);
      if (previousValue > size) return previousValue;
      return size;
    });

    if (alignSize > targetSize) {
      alignSize = targetSize;
    }

    final newList = List.of(fields);
    if (sort) {
      newList.sort((p, n) {
        final pre = p.grt(c).llvmType.getBytes(c);
        final next = n.grt(c).llvmType.getBytes(c);
        return pre > next ? 1 : -1;
      });
    }

    var count = initValue;
    var index = 0;
    if (count != 0) {
      index = 1;
    }
    final map = <FieldDef, FieldIndex>{};
    for (var field in newList) {
      var rty = field.grt(c);
      var currentSize = 0;
      if (rty is FnTy) {
        currentSize = c.pointerSize();
      } else {
        final ty = rty.llvmType.createType(c);
        if (field.isRef) {
          currentSize = c.pointerSize();
        } else {
          currentSize = c.typeSize(ty);
        }
      }
      var newCount = count + currentSize;
      final lastIndex = count ~/ alignSize;
      final nextIndex = newCount ~/ alignSize;
      if (lastIndex == nextIndex) {
        // 以最大的
        final nextCount = (newCount / targetSize).ceil() * targetSize;
        var space = nextCount - newCount;
        // 剩下的空间不足,后面的空间大小不会比[currentSize]小
        if (space > 0 && space < currentSize) {
          index += 1;
        } else {
          space = 0;
        }
        map[field] = FieldIndex(space, index);
        index += 1;
        count = newCount + space;
        continue;
      }

      // 超出本机的内存位宽
      var whiteSpace = newCount % alignSize;
      if (whiteSpace > 0) {
        final extra = alignSize - whiteSpace;
        index += 1;

        map[field] = FieldIndex(extra, index);
        index += 1;
        count = newCount + extra;
      } else {
        map[field] = FieldIndex(0, index);
        count = newCount;
        index += 1;
      }
    }

    return FieldsSize(map, count, alignSize);
  }

  // LLVMAllocaVariable _createAlloca(BuildContext c, Identifier ident) {
  //   final type = pTy.createType(c);
  //   final ctype = createType(c);
  //   final alloca = c.alloctor(type, ident.src);
  //   return LLVMAllocaVariable(ty, alloca, ctype);
  // }

  @override
  LLVMAllocaDelayVariable createAlloca(BuildContext c, Identifier ident) {
    final type = pTy.createType(c);
    return LLVMAllocaDelayVariable(ty, ([alloca]) {
      final ctype = createType(c);
      final alloca = c.alloctor(type, ident.src);
      final indices = [c.constI32(0), c.constI32(0)];
      final first = llvm.LLVMBuildInBoundsGEP2(
          c.builder, ctype, alloca, indices.toNative(), indices.length, unname);
      final index = ty.parent.variants.indexOf(ty);
      llvm.LLVMBuildStore(c.builder, pTy.getIndexValue(c, index), first);
      return alloca;
    }, type);
  }

  int load(BuildContext c, Variable parent, List<FieldExpr> params) {
    LLVMValueRef value;
    if (parent is StoreVariable) {
      value = parent.alloca;
    } else {
      value = parent.load(c);
    }
    final type = createType(c);

    final map = _size!.map;
    for (var i = 0; i < ty.fields.length; i++) {
      final f = ty.fields[i];
      final index = map[f]!.index;
      if (i >= params.length) break;
      final p = params[i];
      var ident = f.ident;
      var e = p.expr;
      if (e is RefExpr) {
        e = e.current;
      }
      if (e is VariableIdentExpr) {
        ident = e.ident;
      }

      final indices = [c.constI32(0), c.constI32(index)];
      final t = f.grt(c);
      final llValue = llvm.LLVMBuildInBoundsGEP2(
          c.builder, type, value, indices.toNative(), indices.length, unname);
      final v = llvm.LLVMBuildLoad2(
          c.builder, t.llvmType.createType(c), llValue, unname);
      c.resolveParam(t, v, ident, false);
    }
    return ty.parent.variants.indexOf(ty);
  }

  LLVMValueRef loadIndex(BuildContext c, Variable parent) {
    LLVMValueRef value;
    if (parent is StoreVariable) {
      value = parent.alloca;
    } else {
      value = parent.load(c);
    }

    final indices = [c.constI32(0), c.constI32(0)];
    final t = pTy.getIndexType(c);
    final pt = pTy.createType(c);
    final v = llvm.LLVMBuildInBoundsGEP2(
        c.builder, pt, value, indices.toNative(), indices.length, unname);

    return llvm.LLVMBuildLoad2(c.builder, t, v, unname);
  }

  int getSuperBytes(BuildContext c) {
    return super.getBytes(c);
  }

  @override
  int getBytes(BuildContext c) {
    return pTy.getBytes(c);
  }
}

class FieldIndex {
  FieldIndex(this.space, this.index);
  final int space;
  final int index;
}

class FieldsSize {
  FieldsSize(this.map, this.count, this.alignSize);
  final Map<FieldDef, FieldIndex> map;
  final int count;
  final int alignSize;
}