import 'dart:ffi';

import '../../fs/fs.dart';
import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../../parsers/str.dart';
import '../ast.dart';
import '../context.dart';
import '../memory.dart';
import '../tys.dart';
import 'intrinsics.dart';
import 'variables.dart';

mixin LLVMTypeMixin {
  LLVMModuleRef get module => root.module;
  LLVMContextRef get llvmContext => root.llvmContext;
  LLVMTargetMachineRef get tm => root.tm;

  RootBuildContext get root => this as RootBuildContext;

  LLVMTypeRef get typeVoid {
    return llvm.LLVMVoidTypeInContext(llvmContext);
  }

  LLVMTypeRef get i1 {
    return llvm.LLVMInt1TypeInContext(llvmContext);
  }

  LLVMTypeRef get i8 {
    return llvm.LLVMInt8TypeInContext(llvmContext);
  }

  LLVMTypeRef get i16 {
    return llvm.LLVMInt16TypeInContext(llvmContext);
  }

  LLVMTypeRef get i32 {
    return llvm.LLVMInt32TypeInContext(llvmContext);
  }

  LLVMTypeRef get i64 {
    return llvm.LLVMInt64TypeInContext(llvmContext);
  }

  LLVMTypeRef get i128 {
    return llvm.LLVMInt128TypeInContext(llvmContext);
  }

  LLVMTypeRef get f32 {
    return llvm.LLVMFloatTypeInContext(llvmContext);
  }

  LLVMTypeRef get f64 {
    return llvm.LLVMDoubleTypeInContext(llvmContext);
  }

  LLVMTypeRef arrayType(LLVMTypeRef type, int count) {
    return llvm.LLVMArrayType(type, count);
  }

  LLVMTypeRef vectorType(LLVMTypeRef type, int count) {
    return llvm.LLVMVectorType(type, count);
  }

  LLVMTypeRef typeFn(List<LLVMTypeRef> params, LLVMTypeRef ret, bool isVar) {
    final type = llvm.LLVMFunctionType(
        ret, params.toNative(), params.length, isVar.llvmBool);
    return type;
  }

  LLVMTypeRef typeStruct(List<LLVMTypeRef> types, String? ident) {
    if (ident == null) {
      return llvm.LLVMStructTypeInContext(
          llvmContext, types.toNative(), types.length, LLVMFalse);
    }
    final struct =
        llvm.LLVMStructCreateNamed(llvmContext, 'struct_$ident'.toChar());
    llvm.LLVMStructSetBody(struct, types.toNative(), types.length, LLVMFalse);

    return struct;
  }

  LLVMTypeRef pointer() {
    return llvm.LLVMPointerTypeInContext(llvmContext, 0);
  }

  LLVMTypeRef typePointer(LLVMTypeRef? type) {
    if (type == null) {
      return pointer();
    }
    return llvm.LLVMPointerType(type, 0);
  }

  int pointerSize() {
    final td = llvm.LLVMGetModuleDataLayout(module);
    return llvm.LLVMPointerSize(td);
  }

  int typeSize(LLVMTypeRef type) {
    final td = llvm.LLVMGetModuleDataLayout(module);
    return llvm.LLVMABISizeOfType(td, type);
  }

  LLVMTypeRef getStructExternType(int count) {
    LLVMTypeRef loadTy;
    var size = pointerSize();
    if (count > size) {
      final d = count / size;
      count = d.ceil();
      loadTy = arrayType(i64, count);
    } else {
      if (count > 4) {
        loadTy = i64;
      } else {
        loadTy = i32;
      }
    }
    return loadTy;
  }

  void setName(LLVMValueRef ref, String name) {
    llvm.LLVMSetValueName(ref, name.toChar());
  }

  void setFnLLVMAttr(LLVMValueRef value, int index, int kind, {int val = 0}) {
    final attr = llvm.LLVMCreateEnumAttribute(llvmContext, kind, val);
    llvm.LLVMAddAttributeAtIndex(value, index, attr);
  }

  void setFnStringLLVMAttr(LLVMValueRef value, String key, String kValue) {
    final (nc, length) = key.toNativeUtf8WithLength();
    final (vname, vlength) = kValue.toNativeUtf8WithLength();
    final vv =
        llvm.LLVMCreateStringAttribute(llvmContext, nc, length, vname, vlength);

    llvm.LLVMAddAttributeAtIndex(value, -1, vv);
  }

  void setFnTypeAttr(LLVMValueRef value, int index, int kind, LLVMTypeRef ty) {
    final attr = llvm.LLVMCreateTypeAttribute(llvmContext, kind, ty);
    llvm.LLVMAddAttributeAtIndex(value, index, attr);
  }

  void setCallLLVMAttr(LLVMValueRef value, int index, int kind, {int val = 0}) {
    final attr = llvm.LLVMCreateEnumAttribute(llvmContext, kind, val);
    llvm.LLVMAddCallSiteAttribute(value, index, attr);
  }

  void setCallTypeAttr(
      LLVMValueRef value, int index, int kind, LLVMTypeRef ty) {
    final attr = llvm.LLVMCreateTypeAttribute(llvmContext, kind, ty);
    llvm.LLVMAddCallSiteAttribute(value, index, attr);
  }
}

mixin Consts on LLVMTypeMixin {
  LLVMValueRef constI1(int v) {
    return llvm.LLVMConstInt(i1, v, LLVMFalse);
  }

  LLVMValueRef constI8(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i8, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI16(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i16, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI32(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i32, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI64(int v, [bool signed = false]) {
    return llvm.LLVMConstInt(i64, v, signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constI128(String v, [bool signed = false]) {
    return llvm.LLVMConstIntOfString(
        i128, v.toChar(), signed ? LLVMTrue : LLVMFalse);
  }

  LLVMValueRef constF32(String v) {
    return llvm.LLVMConstRealOfString(f32, v.toChar());
  }

  LLVMValueRef constF64(String v) {
    return llvm.LLVMConstRealOfString(f64, v.toChar());
  }

  LLVMValueRef usizeValue(int size) {
    return BuiltInTy.usize.llty
        .createValue(ident: Identifier.builtIn('$size'))
        .getValue(this);
  }

  LLVMValueRef getString(Identifier ident) {
    var src = ident.src;
    var key = src;

    if (!ident.isStr) {
      key = key.substring(1, key.length - 1);
    }

    return root.globalStringPut(key, () {
      if (!ident.isStr) {
        src = parseStr(src);
      }

      final (strPtr, length) = src.toNativeUtf8WithLength();
      final strData = constStr('', strPtr: strPtr, length: length);

      final type = arrayType(BuiltInTy.u8.llty.litType(this), length + 1);
      final value = llvm.LLVMAddGlobal(module, type, '.str'.toChar());
      llvm.LLVMSetLinkage(value, LLVMLinkage.LLVMPrivateLinkage);
      llvm.LLVMSetGlobalConstant(value, LLVMTrue);
      llvm.LLVMSetInitializer(value, strData);
      llvm.LLVMSetUnnamedAddress(value, LLVMUnnamedAddr.LLVMGlobalUnnamedAddr);
      return value;
    });
  }

  /// length: 是 UTF-8 编码形式的数组长度，不可直接从 [String.length] 获取
  LLVMValueRef constStr(String str, {Pointer<Char>? strPtr, int? length}) {
    assert(strPtr == null || length != null);

    if (length == null || strPtr == null) {
      final (value, nLength) = str.toNativeUtf8WithLength();
      strPtr = value;
      length = nLength;
    }

    return llvm.LLVMConstStringInContext(
        llvmContext, strPtr, length, LLVMFalse);
  }

  LLVMValueRef constArray(LLVMTypeRef ty, List<LLVMValueRef> vals) {
    final alloca = llvm.LLVMConstArray(ty, vals.toNative(), vals.length);
    return alloca;
  }
}

mixin BuildMethods on LLVMTypeMixin {
  LLVMBuilderRef get builder;

  bool get isFnBBContext;
  LLVMValueRef? _allocaInst;

  LLVMValueRef get fnValue;
  BuildMethods? getLastFnContext();

  LLVMBuilderRef? _allocaBuilder;

  LLVMBuilderRef get allocaBuilder {
    final fnContext = getLastFnContext()!;

    final alloca = fnContext._allocaInst;
    final b = fnContext._allocaBuilder ??=
        llvm.LLVMCreateBuilderInContext(llvmContext);
    final fnEntry = llvm.LLVMGetFirstBasicBlock(fnContext.fnValue);
    if (alloca != null) {
      // 在 entry 中分配
      final next = llvm.LLVMGetNextInstruction(alloca);
      llvm.LLVMPositionBuilder(b, fnEntry, next);
    } else {
      final first = llvm.LLVMGetFirstInstruction(fnEntry);
      llvm.LLVMPositionBuilder(b, fnEntry, first);
    }
    return b;
  }

  LLVMValueRef alloctor(LLVMTypeRef type, {Ty? ty, Identifier? name}) {
    final alloca =
        llvm.LLVMBuildAlloca(allocaBuilder, type, name?.src.toChar() ?? unname);

    if (ty != null) {
      addFree(LLVMAllocaVariable(alloca, ty, type, name ?? Identifier.none));
    }
    setLastAlloca(alloca);

    return alloca;
  }

  void setLastAlloca(LLVMValueRef val) {
    final fnContext = getLastFnContext();
    if (fnContext != null) {
      fnContext._allocaInst = val;
    }
  }

  void addFree(Variable val) {}

  LLVMMetadataRef get unit;
  LLVMMetadataRef get scope;

  LLVMDIBuilderRef? get dBuilder;

  void diSetCurrentLoc(Offset offset) {
    if (!offset.isValid) return;
    if (dBuilder == null) return;
    final loc = llvm.LLVMDIBuilderCreateDebugLocation(
        llvmContext, offset.row, offset.column, scope, nullptr);

    llvm.LLVMSetCurrentDebugLocation2(builder, loc);
  }

  void diClearLoc() {
    llvm.LLVMSetCurrentDebugLocation2(builder, nullptr);
  }

  LLVMValueRef load2(
      LLVMTypeRef ty, LLVMValueRef alloca, String name, Offset offset) {
    if (offset.isValid) {
      diSetCurrentLoc(offset);
    }
    final value = llvm.LLVMBuildLoad2(builder, ty, alloca, name.toChar());

    return value;
  }

  LLVMValueRef store(LLVMValueRef alloca, LLVMValueRef val, Offset offset) {
    if (offset.isValid) {
      diSetCurrentLoc(offset);
    }
    return llvm.LLVMBuildStore(builder, val, alloca);
  }

  LLVMValueRef createArray(LLVMTypeRef ty, LLVMValueRef size, {String? name}) {
    final n = name ?? '_';
    return alloctorArr(ty, size, n);
  }

  LLVMValueRef alloctorArr(LLVMTypeRef type, LLVMValueRef size, String name) {
    final alloca =
        llvm.LLVMBuildArrayAlloca(allocaBuilder, type, size, name.toChar());
    setLastAlloca(alloca);

    return alloca;
  }
}

mixin Cast on BuildMethods {
  LLVMValueRef castLit(LitKind src, LLVMValueRef value, LitKind dest) {
    final ty = BuiltInTy.from(dest.lit)!;
    final llty = ty.llty.litType(this);
    if (src.isInt != dest.isInt) {
      final op = getCastOp(src, dest)!;
      return llvm.LLVMBuildCast(builder, op, value, llty, unname);
    }
    if (dest.isInt) {
      return llvm.LLVMBuildIntCast2(
          builder, value, llty, dest.signed ? LLVMTrue : LLVMFalse, unname);
    }

    return llvm.LLVMBuildFPCast(builder, value, llty, unname);
  }

  static int? getCastOp(LitKind src, LitKind dest) {
    if (src.isInt && dest.isFp) {
      if (src.signed) {
        return LLVMOpcode.LLVMSIToFP;
      } else {
        return LLVMOpcode.LLVMUIToFP;
      }
    } else if (src.isFp && dest.isInt) {
      if (dest.signed) {
        return LLVMOpcode.LLVMFPToSI;
      }
      return LLVMOpcode.LLVMFPToUI;
    }
    return null;
  }
}

mixin DebugMixin on BuildMethods {
  /// ----

  LLVMMetadataRef? _unit;
  @override
  LLVMMetadataRef get unit => _unit!;

  LLVMDIBuilderRef? _dBuilder;

  @override
  LLVMDIBuilderRef? get dBuilder => _dBuilder;

  void init(DebugMixin parent) {
    _unit = parent._unit;
    _dBuilder = parent._dBuilder;
  }

  String get currentPath;

  bool _isRoot = false;

  void debugInit() {
    if (!root.isDebug) return;
    assert(_unit == null && _dBuilder == null);
    _dBuilder = llvm.LLVMCreateDIBuilder(module);
    final path = currentDir.childFile(currentPath);
    final dir = path.parent.path;

    _isRoot = true;

    _unit = llvm.LLVMCreateCompileUnit(
        _dBuilder!, path.basename.toChar(), dir.toChar());
  }

  void finalize() {
    if (_isRoot && _dBuilder != null) {
      llvm.LLVMDIBuilderFinalize(_dBuilder!);
    }
  }

  void dispose() {
    if (_isRoot && _dBuilder != null) {
      llvm.LLVMDisposeDIBuilder(_dBuilder!);
      _dBuilder = null;
    }
    if (_allocaBuilder != null) {
      llvm.LLVMDisposeBuilder(_allocaBuilder!);
    }
  }
}

/// 隐藏[BuildContext]内容，为[LLVMType],[Variable] 提供类型支持
mixin StoreLoadMixin
    on Tys<Variable>, BuildMethods, Consts, DebugMixin, OverflowMath {
  int getAlignSize(Ty ty) {
    final size = ty.llty.getBytes(this);
    final max = pointerSize();
    if (size >= max) {
      return max;
    } else if (size >= 4) {
      return 4;
    }
    return 1;
  }

  int getBaseAlignSize(Ty ty) {
    final type = ty.typeOf(this);
    final td = llvm.LLVMGetModuleDataLayout(module);
    return llvm.LLVMABIAlignmentOfType(td, type);
  }

  LLVMMetadataRef getStructExternDIType(int count) {
    LLVMMetadataRef loadTy;
    var size = pointerSize();
    if (count > size) {
      final d = count / size;
      count = d.ceil();
      loadTy = llvm.LLVMDIBuilderCreateArrayType(dBuilder!, count, size,
          BuiltInTy.i64.llty.createDIType(this), nullptr, 0);
    } else {
      if (count > 4) {
        loadTy = BuiltInTy.i64.llty.createDIType(this);
      } else {
        loadTy = BuiltInTy.i32.llty.createDIType(this);
      }
    }
    return loadTy;
  }

  void diBuilderDeclare(Identifier ident, LLVMValueRef alloca, Ty ty) {
    if (!ident.isValid) return;
    final name = ident.src;
    final (namePointer, length) = name.toNativeUtf8WithLength();
    final dBuilder = this.dBuilder;
    if (dBuilder == null) return;
    final dTy = ty.llty.createDIType(this);
    final dvariable = llvm.LLVMDIBuilderCreateParameterVariable(
        dBuilder,
        scope,
        namePointer,
        length,
        0,
        llvm.LLVMDIScopeGetFile(unit),
        ident.offset.row,
        dTy,
        LLVMFalse,
        0);

    final expr = llvm.LLVMDIBuilderCreateExpression(dBuilder, nullptr, 0);
    final loc = llvm.LLVMDIBuilderCreateDebugLocation(
        llvmContext, ident.offset.row, ident.offset.column, scope, nullptr);

    final bb = llvm.LLVMGetInsertBlock(builder);
    llvm.LLVMDIBuilderInsertDeclareAtEnd(
        dBuilder, alloca, dvariable, expr, loc, bb);
  }

  LLVMValueRef expect(LLVMValueRef lhs, {bool v = true}) {
    final fn = root.maps.putIfAbsent("llvm.expect.i1",
        () => FunctionDeclare([i1, i1], 'llvm.expect.i1', i1));
    final f = fn.build(this);
    return llvm.LLVMBuildCall2(builder, fn.type, f,
        [lhs, constI1(v.llvmBool)].toNative(), 2, 'bool'.toChar());
  }

  LLVMValueRef assume(LLVMValueRef expr) {
    final fn = root.maps.putIfAbsent(
        "llvm.assume", () => FunctionDeclare([i1], 'llvm.assume', typeVoid));

    return llvm.LLVMBuildCall2(
        builder, fn.type, fn.build(this), [expr].toNative(), 1, unname);
  }
}
