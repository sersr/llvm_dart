import 'dart:ffi';

import 'package:characters/characters.dart';

import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../../parsers/token_it.dart';
import '../ast.dart';
import '../memory.dart';
import 'variables.dart';

mixin BuildMethods {
  LLVMModuleRef get module;
  LLVMContextRef get llvmContext;
  LLVMBuilderRef get builder;
  BuildMethods? get parent;

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

  LLVMMetadataRef getStructExternDIType(int count) {
    LLVMMetadataRef loadTy;
    var size = pointerSize();
    if (count > size) {
      final d = count / size;
      count = d.ceil();
      loadTy = llvm.LLVMDIBuilderCreateArrayType(
          dBuilder!,
          count,
          size,
          llvm.LLVMDIBuilderCreateBasicType(
              dBuilder!, 'i64'.toChar(), 3, 64, 1, 0),
          nullptr,
          0);
    } else {
      if (count > 4) {
        loadTy = llvm.LLVMDIBuilderCreateBasicType(
            dBuilder!, 'i64'.toChar(), 3, 64, 1, 0);
      } else {
        loadTy = llvm.LLVMDIBuilderCreateBasicType(
            dBuilder!, 'i32'.toChar(), 3, 32, 1, 0);
      }
    }
    return loadTy;
  }

  bool isFnBBContext = false;
  LLVMValueRef? _allocaInst;
  BuildMethods? getLastFnContext() {
    if (isFnBBContext) return this;
    return parent?.getLastFnContext();
  }

  LLVMValueRef get fnValue;

  LLVMBuilderRef? get allocaBuilder {
    final fnContext = getLastFnContext();
    if (fnContext != null) {
      final alloca = fnContext._allocaInst;
      final b = llvm.LLVMCreateBuilderInContext(llvmContext);
      final fnEntry = llvm.LLVMGetFirstBasicBlock(fnValue);
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
    return null;
  }

  void setLastAlloca(LLVMValueRef val) {
    final fnContext = getLastFnContext();
    if (fnContext != null) {
      fnContext._allocaInst = val;
    }
  }

  LLVMMetadataRef get unit;
  LLVMMetadataRef get scope;

  LLVMDIBuilderRef? get dBuilder;

  LLVMValueRef alloctor(LLVMTypeRef type, {Ty? ty, String name = '_'}) {
    final nb = allocaBuilder;
    llvm.LLVMSetCurrentDebugLocation2(nb ?? builder, nullptr);
    final alloca = llvm.LLVMBuildAlloca(nb ?? builder, type, name.toChar());

    if (ty != null) {
      addFree(LLVMAllocaVariable(ty, alloca, type));
    }
    setLastAlloca(alloca);
    if (nb != null) {
      llvm.LLVMDisposeBuilder(nb);
    }
    return alloca;
  }

  void setName(LLVMValueRef ref, String name) {
    llvm.LLVMSetValueName(ref, name.toChar());
  }

  void addFree(Variable val) {}

  void dropAll() {}

  void diBuilderDeclare(Identifier ident, LLVMValueRef alloca, Ty ty) {
    final name = ident.src;
    final dBuilder = this.dBuilder;
    if (dBuilder == null) return;
    final dTy = ty.llvmType.createDIType(this);
    final dvariable = llvm.LLVMDIBuilderCreateParameterVariable(
        dBuilder,
        scope,
        name.toChar(),
        name.length,
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

  void diSetCurrentLoc(Offset offset) {
    if (!offset.isValid) return;
    final loc = llvm.LLVMDIBuilderCreateDebugLocation(
        llvmContext, offset.row, offset.column, scope, nullptr);

    llvm.LLVMSetCurrentDebugLocation2(builder, loc);
  }

  LLVMValueRef load2(
      LLVMTypeRef ty, LLVMValueRef alloca, String name, Offset offset) {
    final value = llvm.LLVMBuildLoad2(builder, ty, alloca, name.toChar());
    if (offset.isValid) {
      diSetCurrentLoc(offset);
    }
    return value;
  }
}

mixin Consts on BuildMethods {
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

  LLVMValueRef constF32(double v) {
    return llvm.LLVMConstReal(f32, v);
  }

  LLVMValueRef constF64(double v) {
    return llvm.LLVMConstReal(f64, v);
  }

  final _globalString = <String, LLVMValueRef>{};

  Consts? _root;
  Consts get root {
    if (_root != null) return _root!;
    Consts? c = this;
    while (c != null) {
      final parent = c.parent as Consts?;
      if (parent == null) {
        break;
      }
      c = parent;
    }
    return _root = c ?? this;
  }

  LLVMValueRef getString(String v) {
    final ss = v.substring(1, v.length - 1);
    return root._globalString.putIfAbsent(ss, () {
      final str = regSrc(v);
      return llvm.LLVMBuildGlobalStringPtr(
          builder, str.toChar(), 'str'.toChar());
    });
  }

  static String regSrc(String str) {
    final buf = StringBuffer();
    var lastChar = '';
    final isSingle = str.characters.first == "'";
    final slice = str.substring(1, str.length - 1);
    final it = slice.characters.toList().tokenIt;
    bool? eatLn;

    void eatLine() {
      loop(it, () {
        final char = it.current;
        if (char == ' ') {
          return false;
        }
        it.moveBack();
        return true;
      });
    }

    loop(it, () {
      final char = it.current;
      // 两个反义符号
      if (lastChar == '\\') {
        if (isSingle && char == '"') {
          buf.write('\\"');
        } else if (!isSingle && char == "'") {
          buf.write("\\'");
        } else if (char == 'n') {
          buf.write('\n');
        } else if (char == '\n') {
          if (eatLn != false) {
            eatLn = true;
            eatLine();
          }
        } else if (char == '\\') {
          buf.write('\\');
        }
        lastChar = '';
        return false;
      }

      if (eatLn == null) {
        if (char == '\n') {
          eatLn = false;
        }
      }

      if (eatLn == true && char == '\n') {
        eatLine();
        lastChar = '';
      } else {
        lastChar = char;
        if (lastChar != '\\') buf.write(char);
      }

      return false;
    });
    return buf.toString();
  }

  LLVMValueRef constStr(String str) {
    final ss = regSrc(str);
    return llvm.LLVMConstStringInContext(
        llvmContext, ss.toChar(), ss.length, LLVMFalse);
  }

  LLVMValueRef constArray(LLVMTypeRef ty, List<LLVMValueRef> vals) {
    final alloca = llvm.LLVMConstArray(ty, vals.toNative(), vals.length);
    return alloca;
  }

  LLVMValueRef createArray(LLVMTypeRef ty, LLVMValueRef size, {String? name}) {
    final n = name ?? '_';
    return alloctorArr(ty, size, n);
  }

  LLVMValueRef usizeValue(int size) {
    return BuiltInTy.lit(LitKind.usize)
        .llvmType
        .createValue(str: '$size')
        .getValue(this);
  }

  LLVMValueRef alloctorArr(LLVMTypeRef type, LLVMValueRef size, String name) {
    final nb = allocaBuilder;
    final alloca =
        llvm.LLVMBuildArrayAlloca(nb ?? builder, type, size, name.toChar());
    setLastAlloca(alloca);

    if (nb != null) {
      llvm.LLVMDisposeBuilder(nb);
    }
    return alloca;
  }

  LLVMValueRef createMalloc(LLVMTypeRef type, {String? name}) {
    final n = name ?? '_';
    return llvm.LLVMBuildMalloc(builder, type, n.toChar());
  }

  LLVMValueRef createMallocArr(LLVMTypeRef type, int size, {String? name}) {
    final n = name ?? '_';
    return llvm.LLVMBuildArrayMalloc(builder, type, constI64(size), n.toChar());
  }
}

mixin Cast on BuildMethods {
  LLVMValueRef castLit(LitKind src, LLVMValueRef value, LitKind dest) {
    final ty = BuiltInTy.from(dest.lit)!;
    final llty = ty.llvmType.litType(this);
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
