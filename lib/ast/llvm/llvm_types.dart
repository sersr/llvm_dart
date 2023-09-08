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
  LLVMRawValue(this.ident);
  final Identifier ident;

  String get raw => ident.src;
  String? _rawNumber;
  String get rawNumber => _rawNumber ??= raw.replaceAll('_', '');

  double get value {
    return double.parse(rawNumber);
  }

  int get iValue {
    return int.parse(rawNumber);
  }
}

abstract class LLVMType {
  Ty get ty;
  int getBytes(covariant LLVMTypeMixin c);
  LLVMTypeRef createType(covariant LLVMTypeMixin c);

  LLVMMetadataRef createDIType(covariant LLVMTypeMixin c);

  LLVMAllocaDelayVariable createAlloca(
      BuildContext c, Identifier ident, LLVMValueRef? base) {
    final type = createType(c);
    final val = LLVMAllocaDelayVariable(ty, base, ([alloca, nIdent]) {
      final value = c.alloctor(type, ty: ty, name: nIdent?.src ?? ident.src);
      c.diBuilderDeclare(nIdent ?? ident, value, ty);
      return value;
    }, type);
    if (ident.isValid) {
      val.ident = ident;
    }
    return val;
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
      case LitKind.kStr:
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

  LLVMLitVariable createValue({required Identifier ident}) {
    final raw = LLVMRawValue(ident);
    LLVMValueRef v(Consts c, BuiltInTy? bty) {
      final rTy = bty ?? ty;
      final kind = rTy.ty.convert;

      switch (kind) {
        case LitKind.f32:
        case LitKind.kFloat:
          return c.constF32(raw.rawNumber);
        case LitKind.f64:
        case LitKind.kDouble:
          return c.constF64(raw.rawNumber);
        case LitKind.kStr:
          return c.getString(raw.ident);
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
  int getBytes(LLVMTypeMixin c) {
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
      case LitKind.kStr:
      case LitKind.usize:
        return c.pointerSize();
      case LitKind.kVoid:
      default:
        return 0;
    }
  }

  @override
  LLVMMetadataRef createDIType(LLVMTypeMixin c) {
    final name = ty.ty.name;

    if (ty.ty == LitKind.kVoid) {
      return nullptr;
    }

    var encoding = 5;
    if (ty.ty == LitKind.kStr) {
      final base = BuiltInTy.u8.llvmType.createDIType(c);
      return llvm.LLVMDIBuilderCreatePointerType(
          c.dBuilder!, base, c.pointerSize() * 8, 0, 0, unname, 0);
    }

    if (ty.ty.isFp) {
      encoding = 4;
    } else if (!ty.ty.signed) {
      encoding = 7;
    }
    final (namePointer, nameLength) = name.toNativeUtf8WithLength();

    return llvm.LLVMDIBuilderCreateBasicType(
        c.dBuilder!, namePointer, nameLength, getBytes(c) * 8, encoding, 0);
  }
}

class LLVMFnType extends LLVMType {
  LLVMFnType(this.fn);
  final Fn fn;
  @override
  Ty get ty => fn;

  Variable createAllocaParam(
      BuildContext c, Identifier ident, LLVMValueRef val) {
    return LLVMConstVariable(val, ty);
  }

  @protected
  @override
  LLVMTypeRef createType(BuildContext c) {
    return c.pointer();
  }

  LLVMTypeRef createFnType(BuildContext c, [Set<AnalysisVariable>? variables]) {
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];
    var retTy = fn.getRetTy(c);

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
      return tty.llvmType.createType(c);
    }

    for (var p in params) {
      final realTy = fn.getRty(c, p);
      LLVMTypeRef ty;
      if (p.isRef) {
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

    ret = cType(retTy);

    return c.typeFn(list, ret, fn.fnSign.fnDecl.isVar);
  }

  late final _cacheFns = <ListKey, LLVMConstVariable>{};

  LLVMConstVariable createFunction(
      BuildContext c,
      Set<AnalysisVariable>? variables,
      void Function(LLVMConstVariable fnValue) after) {
    final key = ListKey(variables?.toList() ?? []);

    return _cacheFns.putIfAbsent(key, () {
      final ty = fn.llvmType.createFnType(c, variables);
      var ident = fn.fnSign.fnDecl.ident.src;
      final (namePointer, nameLength) = ident.toNativeUtf8WithLength();

      if (ident.isEmpty) {
        ident = '_fn';
      }
      final extern = ident == 'main';

      if (_cacheFns.isNotEmpty) {
        ident = '${ident}_${_cacheFns.length}';
      }
      final v = llvm.LLVMAddFunction(c.module, ident.toChar(), ty);
      llvm.LLVMSetLinkage(
          v,
          extern
              ? LLVMLinkage.LLVMExternalLinkage
              : LLVMLinkage.LLVMInternalLinkage);
      llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);

      var retTy = fn.getRetTy(c);

      final offset = fn.fnSign.fnDecl.ident.offset;

      final dBuilder = c.dBuilder;
      if (dBuilder != null && fn.block?.stmts.isNotEmpty == true) {
        final file = llvm.LLVMDIScopeGetFile(c.unit);
        final params = <Pointer>[];
        params.add(retTy.llvmType.createDIType(c));

        for (var p in fn.fnSign.fnDecl.params) {
          final realTy = fn.getRty(c, p);
          final ty = realTy.llvmType.createDIType(c);
          params.add(ty);
        }

        final fnTy = llvm.LLVMDIBuilderCreateSubroutineType(
            dBuilder, file, params.toNative(), params.length, 0);
        final fnScope = llvm.LLVMDIBuilderCreateFunction(
            dBuilder,
            c.unit,
            namePointer,
            nameLength,
            unname,
            0,
            file,
            offset.row,
            fnTy,
            LLVMFalse,
            LLVMTrue,
            offset.row,
            0,
            LLVMFalse);

        llvm.LLVMSetSubprogram(v, fnScope);

        c.diSetCurrentLoc(offset);
      }

      c.setLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
      c.setLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
      c.setLLVMAttr(v, -1, LLVMAttr.NoInline); // Function

      final fnVariable = LLVMConstVariable(v, fn);
      after(fnVariable);
      return fnVariable;
    });
  }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    return llvm.LLVMDIBuilderCreateBasicType(
        c.dBuilder!, 'ptr'.toChar(), 3, getBytes(c) * 8, 1, 0);
  }
}

class LLVMStructType extends LLVMType {
  LLVMStructType(this.ty);
  @override
  final StructTy ty;

  LLVMTypeRef? _type;

  FieldsSize? _size;

  FieldsSize getFieldsSize(BuildContext c) =>
      _size ??= LLVMEnumItemType.alignType(c, ty.fields, sort: !ty.extern);

  @override
  LLVMTypeRef createType(BuildContext c) {
    if (_type != null) return _type!;
    return _type = getFieldsSize(c).getTypeStruct(c, ty.ident.src, null);
  }

  StoreVariable? getField(
      Variable alloca, BuildContext context, Identifier ident) {
    LLVMTypeRef type = createType(context);

    final fields = ty.fields;
    final index = fields.indexWhere((element) => element.ident == ident);
    if (index == -1) return null;
    final field = fields[index];
    final rTy = field.grt(context);

    final rIndex = _size!.map[field]!.index;
    if (alloca is LLVMAllocaDelayVariable && alloca.isTemp) {
      alloca.create(context);
    }
    LLVMValueRef v = alloca.getBaseValue(context);

    LLVMValueRef fieldValue;

    fieldValue =
        llvm.LLVMBuildStructGEP2(context.builder, type, v, rIndex, unname);

    final val =
        LLVMAllocaVariable(rTy, fieldValue, rTy.llvmType.createType(context));

    return val;
  }

  @override
  int getBytes(BuildContext c) {
    return c.typeSize(createType(c));
  }

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    final name = ty.ident.src;
    final offset = ty.ident.offset;
    final size = getFieldsSize(c);

    final elements = <LLVMMetadataRef>[];
    final fields = size.map.keys.toList();
    final file = llvm.LLVMDIScopeGetFile(c.scope);

    for (var field in fields) {
      var rty = field.grt(c);
      LLVMMetadataRef ty;
      int alignSize;
      if (rty is FnTy) {
        ty = rty.llvmType.createDIType(c);
        alignSize = c.pointerSize() * 8;
      } else {
        ty = rty.llvmType.createDIType(c);
        alignSize = rty.llvmType.getBytes(c) * 8;
      }
      final fieldName = field.ident.src;

      final (namePointer, nameLength) = fieldName.toNativeUtf8WithLength();

      ty = llvm.LLVMDIBuilderCreateMemberType(
        c.dBuilder!,
        c.scope,
        namePointer,
        nameLength,
        file,
        field.ident.offset.row,
        alignSize,
        alignSize,
        size.map[field]!.diOffset * 8,
        0,
        ty,
      );
      elements.add(ty);
    }
    final (namePointer, nameLength) = name.toNativeUtf8WithLength();

    return llvm.LLVMDIBuilderCreateStructType(
      c.dBuilder!,
      c.scope,
      namePointer,
      nameLength,
      llvm.LLVMDIScopeGetFile(c.unit),
      offset.row,
      getBytes(c) * 8,
      size.alignSize * 8,
      0,
      nullptr,
      elements.toNative(),
      elements.length,
      0,
      nullptr,
      '0'.toChar(),
      1,
    );
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
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    return llvm.LLVMDIBuilderCreatePointerType(
        c.dBuilder!,
        parent.llvmType.createDIType(c),
        c.pointerSize(),
        c.pointerSize(),
        0,
        unname,
        0);
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
    final minSize = getRealIndexType(c);
    LLVMTypeRef tyx;
    if (minSize == 1) {
      tyx = c.arrayType(c.i8, size - 1);
    } else if (minSize == 4) {
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

  LLVMMetadataRef getIndexDIType(BuildContext c) {
    final size = getRealIndexType(c);
    if (size == 8) {
      return BuiltInTy.i64.llvmType.createDIType(c);
    } else if (size == 4) {
      return BuiltInTy.i32.llvmType.createDIType(c);
    }
    return BuiltInTy.i8.llvmType.createDIType(c);
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

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    final size = getItemBytes(c);
    final index = getIndexDIType(c);
    final minSize = getRealIndexType(c);
    LLVMMetadataRef tyx;
    if (minSize == 1) {
      tyx = llvm.LLVMDIBuilderCreateArrayType(c.dBuilder!, size - 1, size,
          BuiltInTy.i8.llvmType.createDIType(c), nullptr, 0);
    } else if (minSize == 4) {
      final fc = (size / 4).ceil();
      tyx = llvm.LLVMDIBuilderCreateArrayType(c.dBuilder!, fc, size,
          BuiltInTy.i32.llvmType.createDIType(c), nullptr, 0);
    } else {
      final item = c.getStructExternDIType(size);
      tyx = item;
    }

    final name = ty.ident.src;
    final (namePointer, nameLength) = name.toNativeUtf8WithLength();

    final offset = ty.ident.offset;
    final elements = [index, tyx];
    return llvm.LLVMDIBuilderCreateStructType(
      c.dBuilder!,
      c.scope,
      namePointer,
      nameLength,
      llvm.LLVMDIScopeGetFile(c.unit),
      offset.row,
      getBytes(c),
      size,
      0,
      nullptr,
      elements.toNative(),
      elements.length,
      0,
      nullptr,
      nullptr,
      0,
    );
  }
}

class LLVMEnumItemType extends LLVMStructType {
  LLVMEnumItemType(EnumItem super.ty);
  @override
  EnumItem get ty => super.ty as EnumItem;
  LLVMEnumType get pTy => ty.parent.llvmType;

  int getMinSize(BuildContext c) {
    return ty.fields.fold<int>(100, (p, e) {
      final size = e.grt(c).llvmType.getBytes(c);
      return p > size ? size : p;
    });
  }

  @override
  LLVMTypeRef createType(BuildContext c) {
    if (_type != null) return _type!;

    final m = pTy.getRealIndexType(c);
    final size = _size ??= alignType(c, ty.fields, initValue: m, sort: true);

    // 以数组的形式表示占位符
    final idnexType = c.arrayType(pTy.getIndexType(c), 1);
    return _type = size.getTypeStruct(c, ty.ident.src, idnexType);
  }

  static FieldsSize alignType(BuildContext c, List<FieldDef> fields,
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
        map[field] = FieldIndex(space, index, count);
        index += 1;
        count = newCount + space;
        continue;
      }

      // 超出本机的内存位宽
      var whiteSpace = newCount % alignSize;
      if (whiteSpace > 0) {
        final extra = alignSize - whiteSpace;
        index += 1;

        map[field] = FieldIndex(extra, index, count);
        index += 1;
        count = newCount;
      } else {
        map[field] = FieldIndex(0, index, count);
        count = newCount;
        index += 1;
      }
    }

    return FieldsSize(map, count, alignSize);
  }

  @override
  LLVMAllocaDelayVariable createAlloca(
      BuildContext c, Identifier ident, LLVMValueRef? base) {
    final type = pTy.createType(c);
    return LLVMAllocaDelayVariable(ty, base, ([alloca, nIdent]) {
      final ctype = createType(c);
      final alloca = c.alloctor(type, ty: ty, name: nIdent?.src ?? ident.src);
      c.diBuilderDeclare(nIdent ?? ident, alloca, ty);
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
      value = parent.load(c, Offset.zero);
    }
    final type = createType(c);

    final map = _size!.map;

    if (ty.fields.length == params.length || params.isEmpty) {
      for (var i = 0; i < ty.fields.length; i++) {
        final f = ty.fields[i];
        var ident = f.ident;
        final index = map[f]!.index;
        if (i < params.length) {
          final p = params[i];
          var e = p.expr;
          if (e is RefExpr) {
            e = e.current;
          }
          if (e is VariableIdentExpr) {
            ident = e.ident;
          }
        }

        final indices = [c.constI32(0), c.constI32(index)];
        final t = f.grt(c);
        final llValue = llvm.LLVMBuildInBoundsGEP2(
            c.builder, type, value, indices.toNative(), indices.length, unname);
        final val = LLVMAllocaVariable(t, llValue, t.llvmType.createType(c));
        val.isTemp = false;
        c.pushVariable(ident, val);
      }
    }
    return ty.parent.variants.indexOf(ty);
  }

  LLVMValueRef loadIndex(BuildContext c, Variable parent) {
    LLVMValueRef value;
    if (parent is StoreVariable) {
      value = parent.alloca;
    } else {
      value = parent.load(c, Offset.zero);
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
  FieldIndex(this.space, this.index, this.offset);
  final int space;
  final int index;

  /// 与起点的便宜量
  final int offset;

  int get diOffset => space + offset;
}

class FieldsSize {
  FieldsSize(this.map, this.count, this.alignSize);
  final Map<FieldDef, FieldIndex> map;
  final int count;
  final int alignSize;

  LLVMTypeRef getTypeStruct(
      BuildContext c, String? ident, LLVMTypeRef? enumIndexTy) {
    final vals = <LLVMTypeRef>[];
    final fields = map.keys.toList();
    if (enumIndexTy != null) {
      // 以数组的形式表示占位符
      vals.add(c.arrayType(enumIndexTy, 1));
    }

    for (var field in fields) {
      var rty = field.grt(c);
      final space = map[field]!.space;
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
    return c.typeStruct(vals, ident);
  }
}
