import 'dart:ffi';

import 'package:nop/nop.dart';

import '../../llvm_dart.dart';
import '../ast.dart';
import '../builders/builders.dart';
import '../expr.dart';
import '../memory.dart';
import 'build_context_mixin.dart';
import 'build_methods.dart';
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
  int getBytes(StoreLoadMixin c);
  LLVMTypeRef typeOf(StoreLoadMixin c);

  LLVMMetadataRef createDIType(StoreLoadMixin c);

  LLVMAllocaVariable createAlloca(StoreLoadMixin c, Identifier ident) {
    final type = typeOf(c);

    return LLVMAllocaVariable.delay(() {
      final value = c.alloctor(type, ty: ty, name: ident);
      c.diBuilderDeclare(ident, value, ty);
      return value;
    }, ty, type, ident);
  }
}

class LLVMTypeLit extends LLVMType {
  LLVMTypeLit(this.ty);
  @override
  final BuiltInTy ty;

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return litType(c);
  }

  LLVMTypeRef litType(LLVMTypeMixin c) {
    return switch (ty.literal.convert) {
      LiteralKind.f32 => c.f32,
      LiteralKind.f64 => c.f64,
      LiteralKind.kBool => c.i1,
      LiteralKind.i8 => c.i8,
      LiteralKind.i16 => c.i16,
      LiteralKind.i32 => c.i32,
      LiteralKind.i64 => c.i64,
      LiteralKind.i128 => c.i128,
      LiteralKind.kStr => c.pointer(),
      LiteralKind.isize => c.pointerSize() == 8 ? c.i64 : c.i32,
      LiteralKind.kVoid => c.typeVoid,
      _ => throw "unknown lit ${ty.literal}",
    };
  }

  LLVMLitVariable createValue({required Identifier ident}) {
    final raw = LLVMRawValue(ident);
    LLVMValueRef v(Consts c, BuiltInTy? bty) {
      final rTy = bty ?? ty;
      final lit = rTy.literal;

      return switch (lit.convert) {
        LiteralKind.f32 => c.constF32(raw.rawNumber),
        LiteralKind.f64 => c.constF64(raw.rawNumber),
        LiteralKind.kStr => c.getString(raw.ident),
        LiteralKind.kBool => c.constI1(raw.raw == 'true' ? 1 : 0),
        LiteralKind.i8 => c.constI8(raw.iValue, lit.signed),
        LiteralKind.i16 => c.constI16(raw.iValue, lit.signed),
        LiteralKind.i32 => c.constI32(raw.iValue, lit.signed),
        LiteralKind.i64 => c.constI64(raw.iValue, lit.signed),
        LiteralKind.i128 => c.constI128(raw.raw, lit.signed),
        LiteralKind.isize => c.pointerSize() == 8
            ? c.constI64(raw.iValue, lit.signed)
            : c.constI32(raw.iValue),
        _ => throw "unknown lit $lit",
      };
    }

    return LLVMLitVariable(v, ty, raw, ident);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    final kind = ty.literal.convert;
    return switch (kind) {
      LiteralKind.kBool || LiteralKind.i8 => 1,
      LiteralKind.i16 => 2,
      LiteralKind.i32 || LiteralKind.f32 => 4,
      LiteralKind.f64 || LiteralKind.i64 => 8,
      LiteralKind.i128 => 16,
      LiteralKind.kStr || LiteralKind.isize => c.pointerSize(),
      LiteralKind.kVoid => 0,
      _ => throw "unknown lit ${ty.literal}"
    };
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final name = ty.literal.name;

    if (ty.literal == LiteralKind.kVoid) {
      return nullptr;
    }

    var encoding = 5;
    if (ty.literal == LiteralKind.kStr) {
      final base = LiteralKind.u8.llty.createDIType(c);
      return llvm.LLVMDIBuilderCreatePointerType(
          c.dBuilder!, base, c.pointerSize() * 8, 0, 0, unname, 0);
    }

    if (ty.literal.isFp) {
      encoding = 4;
    } else if (!ty.literal.signed) {
      encoding = 7;
    }
    final (namePointer, nameLength) = name.toNativeUtf8WithLength();

    return llvm.LLVMDIBuilderCreateBasicType(
        c.dBuilder!, namePointer, nameLength, getBytes(c) * 8, encoding, 0);
  }
}

class LLVMFnDeclType extends LLVMType {
  LLVMFnDeclType(this.ty);
  @override
  final FnDecl ty;

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return c.pointer();
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.pointerSize();
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    return llvm.LLVMDIBuilderCreateBasicType(
        c.dBuilder!, 'ptr'.toChar(), 3, getBytes(c) * 8, 1, 0);
  }

  LLVMTypeRef createFnType(StoreLoadMixin context) {
    final decl = ty;
    final fields = decl.fields;
    final list = <LLVMTypeRef>[];
    var retTy = decl.getRetTy(context);
    if (decl is FnClosure) {
      list.add(context.pointer());
    }

    var retIsSret = retTy.llty.getBytes(context) > 8;
    if (retIsSret) {
      list.add(context.typePointer(retTy.typeOf(context)));
    }

    if (decl case ImplFnDecl(implFn: ImplFnMixin(isStatic: false))) {
      LLVMTypeRef forTy;
      final tty = decl.implFn.implty.ty;
      if (tty is BuiltInTy) {
        forTy = tty.typeOf(context);
      } else {
        forTy = context.pointer();
      }
      list.add(forTy);
    }

    for (var p in fields) {
      final realTy = ty.getFieldTy(context, p);

      LLVMTypeRef type = realTy.llty.getBytes(context) > 8
          ? context.pointer()
          : realTy.typeOf(context);

      list.add(type);
    }

    final size = switch (decl) {
      FnCatch decl => decl.analysisVariables.length,
      _ => 0,
    };

    final type = context.pointer();
    list.addAll(List.generate(size, (index) => type));

    for (var p in fields) {
      final pty = ty.getFieldTy(context, p);
      if (pty is FnCatch) {
        for (var _ in pty.analysisVariables) {
          list.add(context.pointer());
        }
      }
    }

    final LLVMTypeRef ret;
    if (retIsSret) {
      ret = context.typeVoid;
    } else {
      ret = retTy.typeOf(context);
    }

    return context.typeFn(list, ret, ty.isVar);
  }
}

class LLVMFnClosureType extends LLVMFnDeclType {
  LLVMFnClosureType(FnClosure super.ty);

  @override
  FnClosure get ty => super.ty as FnClosure;

  LLVMTypeRef? _type;
  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    if (_type != null) return _type!;
    return _type = c.typeStruct([c.pointer(), c.pointer()], null);
  }

  LLVMTypeRef closureTypeOf(StoreLoadMixin c, List<Variable> variables) {
    final vals = <LLVMTypeRef>[c.pointer()];
    for (var _ in variables) {
      vals.add(c.pointer());
    }

    return c.typeStruct(vals, null);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.pointerSize() * 2;
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final fnClosure = c.global.getStdTy(c, 'FnClosure'.ident);

    final name = fnClosure?.ident.src ?? 'FnClosure';
    final offset = fnClosure?.ident.offset ?? Offset.zero;

    final elements = <LLVMMetadataRef>[];
    final file = llvm.LLVMDIScopeGetFile(c.scope);

    var start = 0;
    final p = RefTy(LiteralKind.kVoid.ty);
    for (var field in [p, p]) {
      var rty = field;

      final ty = rty.llty.createDIType(c);
      final alignSize = rty.llty.getBytes(c) * 8;

      final fieldName = field.ident.src;

      final (namePointer, nameLength) = fieldName.toNativeUtf8WithLength();

      final member = llvm.LLVMDIBuilderCreateMemberType(
        c.dBuilder!,
        c.scope,
        namePointer,
        nameLength,
        file,
        field.ident.offset.row,
        alignSize,
        alignSize,
        start,
        0,
        ty,
      );
      elements.add(member);
      start += alignSize;
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
      64,
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

  static LLVMValueRef callClosure(
      FnBuildMixin context, Variable fn, List<LLVMValueRef> args) {
    final type =
        context.typeStruct([context.pointer(), context.pointer()], null);
    final base = fn.getBaseValue(context);
    final ref = RefTy(LiteralKind.kVoid.ty);

    final fnAddr =
        llvm.LLVMBuildStructGEP2(context.builder, type, base, 0, unname);

    final sec =
        llvm.LLVMBuildStructGEP2(context.builder, type, base, 1, unname);
    final secVal =
        LLVMAllocaVariable(sec, ref, ref.typeOf(context), Identifier.none);
    args.add(secVal.load(context));

    return LLVMAllocaVariable(fnAddr, ref, ref.typeOf(context), Identifier.none)
        .load(context);
  }

  LLVMValueRef load(FnBuildMixin context, LLVMValueRef fn, FnCatch fnCatch,
      List<LLVMValueRef> args) {
    final ptr = fn;
    final type = closureTypeOf(context, fnCatch.getVariables());

    final ref = RefTy(LiteralKind.kVoid.ty);
    final fnValue =
        llvm.LLVMBuildStructGEP2(context.builder, type, ptr, 0, unname);
    final fnVariable =
        LLVMAllocaVariable(fnValue, ref, ref.typeOf(context), Identifier.none);
    final variables = fnCatch.getVariables();

    for (var i = 0; i < variables.length; i++) {
      final value =
          llvm.LLVMBuildStructGEP2(context.builder, type, ptr, i + 1, unname);

      final item = variables[i];

      final field =
          LLVMAllocaVariable(value, ref, ref.typeOf(context), item.ident);

      args.add(field.load(context));
    }

    return fnVariable.load(context);
  }
}

class LLVMFnType extends LLVMType {
  LLVMFnType(this.fn);
  final Fn fn;
  @override
  FnDecl get ty => fn.fnDecl;

  late final _cacheFns = <ListKey, LLVMConstVariable>{};

  LLVMConstVariable createFunction(StoreLoadMixin c) {
    final type = ty.llty.createFnType(c);
    var ident = fn.fnName.src;
    if (ident.isEmpty) {
      ident = '_fn';
    }
    final extern = ident == 'main';

    if (_cacheFns.isNotEmpty) {
      ident = '${ident}_${_cacheFns.length}';
    }
    final v = llvm.LLVMAddFunction(c.module, ident.toChar(), type);
    llvm.LLVMSetLinkage(
        v,
        extern
            ? LLVMLinkage.LLVMExternalLinkage
            : LLVMLinkage.LLVMInternalLinkage);
    llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);

    final scope = createScope(c);
    if (scope != null) {
      llvm.LLVMSetSubprogram(v, scope);
    }

    c.setFnLLVMAttr(v, -1, LLVMAttr.OptimizeNone); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.StackProtect); // Function
    c.setFnLLVMAttr(v, -1, LLVMAttr.NoInline); // Function

    return LLVMConstVariable(v, ty, fn.fnName);
  }

  LLVMMetadataRef? _scope;
  LLVMMetadataRef? createScope(StoreLoadMixin c) {
    final dBuilder = c.dBuilder;
    if (dBuilder == null) return null;

    if (_scope != null) return _scope;
    var retTy = ty.getRetTy(c);

    if (fn.block?.isNotEmpty == true) {
      final offset = fn.fnName.offset;
      final (namePointer, nameLength) = fn.fnName.src.toNativeUtf8WithLength();
      final file = llvm.LLVMDIScopeGetFile(c.unit);
      final params = <Pointer>[];
      params.add(retTy.llty.createDIType(c));

      for (var p in ty.fields) {
        final realTy = ty.getFieldTy(c, p);
        final fieldTy = realTy.llty.createDIType(c);
        params.add(fieldTy);
      }

      final fnTy = llvm.LLVMDIBuilderCreateSubroutineType(
          dBuilder, file, params.toNative(), params.length, 0);
      return _scope = llvm.LLVMDIBuilderCreateFunction(
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
    }
    return null;
  }

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return ty.typeOf(c);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return ty.llty.getBytes(c);
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    return ty.llty.createDIType(c);
  }

  LLVMConstVariable? _externFn;

  LLVMConstVariable getOrCreate(
      StoreLoadMixin c, LLVMConstVariable Function() action) {
    if (_externFn != null) return _externFn!;
    final value = _externFn = action();
    final meta = createScope(c);

    if (meta != null) {
      llvm.LLVMSetSubprogram(value.value, meta);
    }

    return value;
  }
}

class LLVMStructType extends LLVMType {
  LLVMStructType(this.ty);
  @override
  final StructTy ty;

  LLVMTypeRef? _type;

  FieldsSize? _size;

  FieldsSize getFieldsSize(StoreLoadMixin c) =>
      _size ??= LLVMEnumItemType.alignType(c, ty, sort: !ty.extern);

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    if (_type != null) return _type!;
    return _type = getFieldsSize(c).getTypeStruct(c, ty.ident.src, null);
  }

  void setIndex(StoreLoadMixin c, LLVMValueRef alloca) {
    assert(false, "used by enum.");
  }

  Ty get valTy => ty;

  LLVMAllocaProxyVariable buildStruct(
      FnBuildMixin context, List<FieldExpr> params,
      {bool isSort = false}) {
    final structType = ty.typeOf(context);
    final fields = ty.fields;
    final sortFields = isSort ? params : alignParam(params, fields);

    void create(LLVMAllocaProxyVariable? value, bool isProxy) {
      if (value == null) return;
      final resetEnumIndex = ty is EnumItem;

      context.diSetCurrentLoc(value.ident.offset);

      if (sortFields.length != fields.length) {
        value.store(context, llvm.LLVMConstNull(structType));
      } else if (resetEnumIndex) {
        setIndex(context, value.getBaseValue(context));
      }

      for (var i = 0; i < sortFields.length; i++) {
        final f = sortFields[i];
        final fd = fields[i];

        final temp = f.temp;
        final v = temp?.variable;
        if (v == null) {
          Log.e('${(f.ident ?? fd.ident).light} return null.', showTag: false);
          continue;
        }
        final vv = getField(value, context, f.ident ?? fd.ident)!;
        vv.storeVariable(context, v, isNew: true);
      }
    }

    return LLVMAllocaProxyVariable(
        context, create, valTy, valTy.typeOf(context), Identifier.none);
  }

  LLVMAllocaVariable? getField(
      Variable alloca, StoreLoadMixin context, Identifier ident,
      {int? index}) {
    LLVMTypeRef type = typeOf(context);

    final fields = ty.fields;

    var fi = index;
    if (fi == null) {
      fi = fields.indexWhere((element) => element.ident == ident);
      if (fi == -1) return null;
    }

    final field = fields[fi];
    final pty = field.grt(context);

    final ind = getFieldsSize(context).map[field]!.index;

    final val = LLVMAllocaVariable.delay(() {
      final ptr = alloca.getBaseValue(context);
      context.diSetCurrentLoc(ident.offset);

      return llvm.LLVMBuildStructGEP2(context.builder, type, ptr, ind, unname);
    }, pty, pty.typeOf(context), ident);

    return val;
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.typeSize(typeOf(c));
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final name = ty.ident.src;
    final offset = ty.ident.offset;
    final size = getFieldsSize(c);

    final elements = <LLVMMetadataRef>[];
    final fields = size.map.keys.toList();
    final file = llvm.LLVMDIScopeGetFile(c.scope);

    for (var field in fields) {
      var rty = field.grt(c);
      LLVMMetadataRef ty;

      ty = rty.llty.createDIType(c);
      final alignSize = rty.llty.getBytes(c) * 8;

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
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return c.pointer();
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.pointerSize();
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    return llvm.LLVMDIBuilderCreatePointerType(
        c.dBuilder!,
        parent.llty.createDIType(c),
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
  LLVMTypeRef typeOf(StoreLoadMixin c) {
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

  LLVMTypeRef getIndexType(StoreLoadMixin c) {
    final size = getRealIndexType(c);
    return switch (size) {
      == 8 => c.i64,
      == 4 => c.i32,
      _ => c.i8,
    };
  }

  LLVMMetadataRef getIndexDIType(StoreLoadMixin c) {
    final size = getRealIndexType(c);
    return switch (size) {
      == 8 => LiteralKind.i64.llty.createDIType(c),
      == 4 => LiteralKind.i32.llty.createDIType(c),
      _ => LiteralKind.i8.llty.createDIType(c),
    };
  }

  int getItemBytes(StoreLoadMixin c) {
    final fSize = ty.variants.fold<int>(0, (previousValue, element) {
      final esize = element.llty.getSuperBytes(c);
      if (previousValue > esize) return previousValue;
      return esize;
    });
    return fSize;
  }

  LLVMValueRef getIndexValue(StoreLoadMixin c, int v) {
    final s = getRealIndexType(c);
    if (s > 4) {
      return c.constI64(v);
    } else if (s > 1) {
      return c.constI32(v);
    }
    return c.constI8(v);
  }

  int? _minSize;

  int getRealIndexType(StoreLoadMixin c) {
    if (_minSize != null) return _minSize!;
    final size = ty.variants.length;
    final minSize = ty.variants.fold<int>(100, (previousValue, element) {
      final esize = element.llty.getMinSize(c);
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

  LLVMValueRef loadIndex(StoreLoadMixin c, Variable parent) {
    LLVMValueRef value;
    if (parent is StoreVariable) {
      value = parent.alloca;
    } else {
      value = parent.load(c);
    }

    final indices = [c.constI32(0), c.constI32(0)];
    final t = getIndexType(c);
    final pt = typeOf(c);
    final v = llvm.LLVMBuildInBoundsGEP2(
        c.builder, pt, value, indices.toNative(), indices.length, unname);

    return llvm.LLVMBuildLoad2(c.builder, t, v, unname);
  }

  int? _total;
  @override
  int getBytes(StoreLoadMixin c) {
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
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final size = getItemBytes(c);
    final index = getIndexDIType(c);
    final minSize = getRealIndexType(c);
    LLVMMetadataRef tyx;
    if (minSize == 1) {
      tyx = llvm.LLVMDIBuilderCreateArrayType(c.dBuilder!, size - 1, size,
          LiteralKind.i8.llty.createDIType(c), nullptr, 0);
    } else if (minSize == 4) {
      final fc = (size / 4).ceil();
      tyx = llvm.LLVMDIBuilderCreateArrayType(c.dBuilder!, fc, size,
          LiteralKind.i32.llty.createDIType(c), nullptr, 0);
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
  LLVMEnumType get pTy => ty.parent.llty;

  int getMinSize(StoreLoadMixin c) {
    return ty.fields.fold<int>(100, (p, e) {
      final size = e.grt(c).llty.getBytes(c);
      return p > size ? size : p;
    });
  }

  @override
  Ty get valTy => ty.parent;

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    if (_type != null) return _type!;

    final m = pTy.getRealIndexType(c);
    final size = _size ??= alignType(c, ty, initValue: m, sort: true, up: true);

    // 以数组的形式表示占位符
    final indexType = c.arrayType(pTy.getIndexType(c), 1);
    return _type = size.getTypeStruct(c, ty.ident.src, indexType);
  }

  static FieldsSize alignType(StoreLoadMixin c, NewInst ty,
      {int initValue = 0, bool sort = false, bool up = false}) {
    final targetSize = c.pointerSize();
    final fields = ty.fields;

    var alignSize = fields.fold<int>(0, (previousValue, element) {
      final size = element.grt(c).llty.getBytes(c);
      if (previousValue > size) return previousValue;
      return size;
    });

    if (alignSize > targetSize) {
      alignSize = targetSize;
    }

    final newList = List.of(fields);
    if (sort) {
      newList.sort((p, n) {
        final pre = p.grt(c).llty.getBytes(c);
        final next = n.grt(c).llty.getBytes(c);
        if (pre == next) return 0;

        if (up) {
          return pre > next ? 1 : -1;
        } else {
          return pre > next ? -1 : 1;
        }
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

      final ty = rty.typeOf(c);
      final currentSize = c.typeSize(ty);

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
  LLVMAllocaVariable createAlloca(StoreLoadMixin c, Identifier ident) {
    final type = pTy.typeOf(c);
    return LLVMAllocaVariable.delay(() {
      final alloca = c.alloctor(type, ty: ty, name: ident);

      c.diBuilderDeclare(ident, alloca, ty);
      setIndex(c, alloca);
      return alloca;
    }, ty, type, ident);
  }

  @override
  void setIndex(StoreLoadMixin c, LLVMValueRef alloca) {
    final indices = [c.constI32(0), c.constI32(0)];
    final ctype = typeOf(c);

    final first = llvm.LLVMBuildInBoundsGEP2(
        c.builder, ctype, alloca, indices.toNative(), indices.length, unname);
    final index = ty.parent.variants.indexOf(ty);
    llvm.LLVMBuildStore(c.builder, pTy.getIndexValue(c, index), first);
  }

  int load(StoreLoadMixin c, Variable parent, List<FieldExpr> params) {
    final type = typeOf(c);

    final map = _size!.map;

    final value = parent.getBaseValue(c);
    final keyList = _size!.idents;
    final keys = map.keys.toList();

    final enumIsNamed = ty.fields.every((e) => e.ident.isValid);

    for (var i = 0; i < params.length; i++) {
      final ident = params[i].pattern;

      if (ident == null) {
        Log.e('${params[i]} error.');
        continue;
      }

      int fIndex;
      if (enumIsNamed) {
        fIndex = keyList.indexOf(ident);
      } else {
        fIndex = keys.indexOf(ty.fields[i]);
      }

      final fd = keys.elementAt(fIndex);
      final index = map[fd]!.index;

      final indices = [c.constI32(0), c.constI32(index)];
      final t = fd.grt(c);

      final val = LLVMAllocaVariable.delay(() {
        return llvm.LLVMBuildInBoundsGEP2(
            c.builder, type, value, indices.toNative(), indices.length, unname);
      }, t, t.typeOf(c), ident);

      c.pushVariable(val);
    }
    return ty.parent.variants.indexOf(ty);
  }

  int checkStack(
      StoreLoadMixin c, Variable parent, void Function(Variable v) test) {
    final type = typeOf(c);

    final map = _size!.map;

    for (var entry in map.entries) {
      final fd = entry.key;
      final index = entry.value.index;
      final ident = fd.ident;

      final indices = [c.constI32(0), c.constI32(index)];
      final t = fd.grt(c);

      final val = LLVMAllocaVariable.delay(() {
        final value = parent.getBaseValue(c);
        return llvm.LLVMBuildInBoundsGEP2(
            c.builder, type, value, indices.toNative(), indices.length, unname);
      }, t, t.typeOf(c), ident);

      test(val);
    }

    return ty.parent.variants.indexOf(ty);
  }

  int getSuperBytes(StoreLoadMixin c) {
    return super.getBytes(c);
  }

  @override
  int getBytes(StoreLoadMixin c) {
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

  List<Identifier>? _identList;

  List<Identifier> get idents =>
      _identList ??= map.keys.map((e) => e.ident).toList();

  LLVMTypeRef getTypeStruct(
      StoreLoadMixin c, String? ident, LLVMTypeRef? enumIndexTy,
      {int initSize = 0}) {
    final vals = <LLVMTypeRef>[];
    final tys = <Ty>[];
    final fields = map.keys.toList();
    if (enumIndexTy != null) {
      vals.add(enumIndexTy);
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

      tys.add(rty);
      vals.add(rty.typeOf(c));
    }
    if (map.isNotEmpty) {
      final last = map.entries.last;
      final itemSize = last.key.grt(c).llty.getBytes(c);
      final edge = itemSize + last.value.diOffset;
      final extra = edge % alignSize;
      if (extra > 0) {
        vals.add(c.arrayType(c.i8, alignSize - extra));
      }
    }
    return c.typeStruct(vals, ident, tys: tys);
  }
}

class SliceLLVMType extends LLVMType {
  SliceLLVMType(this.ty);

  @override
  final SliceTy ty;
  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return c.arrayType(ty.elementTy.typeOf(c), 0);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.typeSize(typeOf(c));
  }

  Variable getLen(StoreLoadMixin c, Variable src) {
    final base = src.getBaseValue(c);
    final ty = llvm.LLVMTypeOf(base);
    final tyKind = llvm.LLVMGetTypeKind(ty);
    final sizeTy = LiteralKind.usize.ty;
    if (tyKind == LLVMTypeKind.LLVMArrayTypeKind) {
      final len = llvm.LLVMGetArrayLength(ty);
      return sizeTy.llty.createValue(ident: '$len'.ident);
    }

    final indics = [c.constI32(0), c.constI32(1)];
    final value = llvm.LLVMBuildInBoundsGEP2(
        c.builder, ty, base, indics.toNative(), indics.length, unname);
    final v = c.load2(sizeTy.typeOf(c), value, '', Offset.zero);
    return LLVMConstVariable(v, sizeTy, Identifier.none);
  }

  Variable getElement(
      StoreLoadMixin c, Variable value, LLVMValueRef index, Identifier id) {
    final indics = <LLVMValueRef>[c.constI32(0), index];

    final type = ty.typeOf(c);

    final vv = LLVMAllocaVariable.delay(() {
      c.diSetCurrentLoc(id.offset);
      final p = value.getBaseValue(c);
      return llvm.LLVMBuildInBoundsGEP2(
          c.builder, type, p, indics.toNative(), indics.length, unname);
    }, ty.elementTy, ty.elementTy.typeOf(c), id);

    return vv;
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    final size = ty.elementTy.llty.getBytes(c);
    return llvm.LLVMDIBuilderCreatePointerType(c.dBuilder!,
        ty.elementTy.llty.createDIType(c), size, size, 0, unname, 0);
  }
}

class ArrayLLVMType extends SliceLLVMType {
  ArrayLLVMType(ArrayTy super.ty);

  @override
  ArrayTy get ty => super.ty as ArrayTy;

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return c.arrayType(ty.elementTy.typeOf(c), ty.size);
  }

  @override
  LLVMAllocaVariable createAlloca(StoreLoadMixin c, Identifier ident) {
    final val = LLVMAllocaVariable.delay(() {
      final count = c.constI64(ty.size);
      return c.createArray(ty.elementTy.typeOf(c), count, name: ident.src);
    }, ty, typeOf(c), ident);

    return val;
  }

  LLVMConstVariable createArray(StoreLoadMixin c, List<LLVMValueRef> values) {
    final value = c.constArray(ty.elementTy.typeOf(c), values);
    return LLVMConstVariable(value, ty, Identifier.none);
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    return llvm.LLVMDIBuilderCreateArrayType(
        c.dBuilder!,
        ty.size,
        ty.elementTy.llty.getBytes(c),
        ty.elementTy.llty.createDIType(c),
        nullptr,
        0);
  }
}

class LLVMAliasType extends LLVMType {
  LLVMAliasType(this.ty);

  @override
  final TypeAliasTy ty;

  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return ty.aliasTy.grt(c).typeOf(c);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return ty.aliasTy.grt(c).llty.getBytes(c);
  }

  @override
  LLVMMetadataRef createDIType(StoreLoadMixin c) {
    return ty.aliasTy.grt(c).llty.createDIType(c);
  }
}
