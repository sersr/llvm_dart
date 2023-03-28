import 'dart:ffi';

import 'package:collection/collection.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/stmt.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import 'ast.dart';
import 'build_methods.dart';
import 'memory.dart';

class LLVMValue {}

class LLVMRawValue extends LLVMValue {
  LLVMRawValue(this.raw);
  final String raw;

  Pointer<Char> toChar() {
    return raw.toChar();
  }

  double get value {
    return double.parse(raw);
  }

  int get iValue {
    return int.parse(raw);
  }
}

class LLVMStructValue extends LLVMValue {
  LLVMStructValue(this.params);
  final List<Variable> params;
}

abstract class LLVMType {
  int getBytes(BuildContext c);
  LLVMTypeRef createType(BuildContext c);
  Variable createValue(BuildContext c);
}

class LLVMTypeLit extends LLVMType {
  LLVMTypeLit(this.ty);
  final BuiltInTy ty;

  @override
  LLVMTypeRef createType(BuildContext c) {
    final kind = ty.ty;
    LLVMTypeRef type;
    switch (kind) {
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
        type = c.i8;
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

  @override
  Variable createValue(BuildContext c, {String str = ''}) {
    final raw = LLVMRawValue(str);
    final kind = ty.ty;
    switch (kind) {
      case LitKind.f32:
      case LitKind.kFloat:
        return LLVMTempVariable(c.constF32(raw.value));
      case LitKind.kDouble:
        return LLVMTempVariable(c.constF64(raw.value));
      case LitKind.kString:
        return LLVMTempVariable(c.constStr(raw.raw));
      case LitKind.kInt:
      default:
        return LLVMTempVariable(c.constI32(raw.iValue));
    }
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

class LLVMPathType extends LLVMType {
  LLVMPathType(this.ty);
  final PathTy ty;
  @override
  LLVMTypeRef createType(BuildContext c) {
    final ident = ty.ident;
    final tySrc = ident.src;
    var t = BuiltInTy.from(ident, tySrc);
    if (t != null) {
      return t.llvmType.createType(c);
    }
    Ty? tty = c.getStruct(ident);
    tty ??= c.getFn(ident);
    tty ??= c.getEnum(ident) ?? c.getImpl(ident) ?? c.getComponent(ident);
    return tty!.llvmType.createType(c);
  }

  @override
  Variable createValue(BuildContext c) {
    final ident = ty.ident;
    final tySrc = ident.src;
    var t = BuiltInTy.from(ident, tySrc);
    if (t != null) {
      return t.llvmType.createValue(c);
    }
    Ty? tty = c.getStruct(ident);
    tty ??= c.getFn(ident);
    tty ??= c.getEnum(ident) ?? c.getImpl(ident) ?? c.getComponent(ident);
    if (tty == null) {
      throw 'unknown ty $ty';
    }
    return tty.llvmType.createValue(c);
  }

  @override
  int getBytes(BuildContext c) {
    final ident = ty.ident;
    final tySrc = ident.src;
    var t = BuiltInTy.from(ident, tySrc);
    if (t != null) {
      return t.llvmType.getBytes(c);
    }
    Ty? tty = c.getStruct(ident);
    tty ??= c.getFn(ident);
    tty ??= c.getEnum(ident) ?? c.getImpl(ident) ?? c.getComponent(ident);
    if (tty == null) {
      throw 'unknown ty $ty';
    }
    return tty.llvmType.getBytes(c);
  }
}

class LLVMFnType extends LLVMType {
  LLVMFnType(this.fn);
  final Fn fn;
  @override
  LLVMTypeRef createType(BuildContext c) {
    final params = fn.fnSign.fnDecl.params;
    final list = <LLVMTypeRef>[];
    for (var p in params) {
      final realTy = p.ty.getRealTy(c);
      LLVMTypeRef ty;
      if (p.isRef) {
        ty = c.pointer();
      } else {
        if (realTy is StructTy) {
          final size = realTy.llvmType.getBytes(c);
          var count = 1;
          if (size > 8) {
            final c = size / 8;
            count = c.ceil();
          }
          ty = c.arrayType(c.i64, count);
        } else {
          ty = realTy.llvmType.createType(c);
        }
      }
      list.add(ty);
      // }
    }

    var ret = fn.fnSign.fnDecl.returnTy.llvmType.createType(c);

    return c.typeFn(list, ret);
  }

  LLVMConstVariable? _value;
  @override
  LLVMConstVariable createValue(BuildContext c) {
    if (_value != null) return _value!;

    final ident = fn.fnSign.fnDecl.ident.src;
    final v = llvm.LLVMAddFunction(c.module, ident.toChar(), createType(c));
    llvm.LLVMSetFunctionCallConv(v, LLVMCallConv.LLVMCCallConv);
    return _value = LLVMConstVariable(v, fn);
  }

  @override
  int getBytes(BuildContext c) {
    return 8;
  }
}

class LLVMStructType extends LLVMType {
  LLVMStructType(this.ty);
  final StructTy ty;

  LLVMTypeRef? _type;
  @override
  LLVMTypeRef createType(BuildContext c) {
    if (_type != null) return _type!;
    final vals = <LLVMTypeRef>[];
    final struct = ty;

    for (var field in struct.fields) {
      final ty = field.ty.llvmType.createType(c);
      vals.add(ty);
    }

    return _type = c.typeStruct(vals, ty.ident);
  }

  LLVMAllocaVariable? getField(
      LLVMAllocaVariable alloca, BuildContext context, Identifier ident) {
    final index = ty.fields.indexWhere((element) => element.ident == ident);
    if (index == -1) return null;
    final indics = <LLVMValueRef>[];
    final field = ty.fields[index];
    Log.w('.. $index $ty');
    indics.add(context.constI32(0));
    indics.add(context.constI32(index));
    final c = llvm.LLVMBuildInBoundsGEP2(context.builder, createType(context),
        alloca.alloca, indics.toNative().cast(), indics.length, unname);
    return LLVMAllocaVariable(
        field.ty, c, field.ty.llvmType.createType(context));
  }

  @override
  LLVMStructAllocaVariable createValue(BuildContext c) {
    final type = createType(c);

    final size = getBytes(c);
    var count = 1;
    if (size > 8) {
      final c = size / 8;
      count = c.ceil();
    }
    final loadTy = c.arrayType(c.i64, count);

    final alloca = llvm.LLVMBuildAlloca(c.builder, type, unname);
    llvm.LLVMSetAlignment(alloca, 4);
    return LLVMStructAllocaVariable(ty, alloca, type, loadTy);
  }

  @override
  int getBytes(BuildContext c) {
    var size = 0;
    for (var field in ty.fields) {
      final tsize = field.ty.llvmType.getBytes(c);
      size += tsize;
    }
    return size;
  }
}

class LLVMBasicBlock {
  LLVMBasicBlock(this.bb, this.context, this.inserted);
  final LLVMBasicBlockRef bb;
  final BuildContext context;
  String? label;
  LLVMBasicBlock? parent;
  bool inserted = false;
}

class LLVMConstVariable extends Variable {
  LLVMConstVariable(this.value, this.ty);

  @override
  final Ty ty;
  @protected
  final Pointer<LLVMOpaqueValue> value;

  @override
  LLVMValueRef load(BuildContext c) {
    return value;
  }
}

class LLVMAllocaVariable extends Variable {
  LLVMAllocaVariable(this.ty, this.alloca, this.type);
  final LLVMValueRef alloca;
  final LLVMTypeRef type;
  @override
  final Ty ty;

  bool _isRef = false;
  LLVMAllocaVariable clone(bool isRef) {
    if (isRef == _isRef) return this;
    final inst = LLVMAllocaVariable(ty, alloca, type);
    inst._isRef = isRef;
    return inst;
  }

  @protected
  @override
  LLVMValueRef load(BuildContext c) {
    if (_isRef) return alloca;
    return llvm.LLVMBuildLoad2(c.builder, type, alloca, unname);
  }

  void store(BuildContext c, LLVMValueRef val) {
    llvm.LLVMBuildStore(c.builder, val, alloca);
  }
}

class LLVMStructAllocaVariable extends LLVMAllocaVariable {
  LLVMStructAllocaVariable(super.ty, super.alloca, super.type, this.loadTy);
  final LLVMTypeRef loadTy;
  @override
  LLVMAllocaVariable clone(bool isRef) {
    if (isRef == _isRef) return this;
    final inst = LLVMStructAllocaVariable(ty, alloca, type, loadTy);
    inst._isRef = isRef;
    return inst;
  }

  LLVMValueRef load2(BuildContext c, bool extern) {
    if (extern && !_isRef) {
      return llvm.LLVMBuildLoad2(c.builder, loadTy, alloca, 'extern_'.toChar());
    }
    return load(c);
  }
}

class LLVMTempVariable extends Variable {
  LLVMTempVariable(this.value);
  final LLVMValueRef value;

  @override
  final Ty ty = Ty.unknown;

  @override
  LLVMValueRef load(BuildContext c) {
    return value;
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
}

LLVMCore get llvm => LLVMInstance.getInstance();

class BuildContext with Tys<BuildContext>, BuildMethods, Consts {
  BuildContext._(BuildContext this.parent) {
    kModule = parent!.kModule;
    _init();
  }

  BuildContext.root([String name = 'root']) : parent = null {
    kModule = llvm.createKModule(name.toChar());
    _init();
  }

  @override
  final BuildContext? parent;
  final List<BuildContext> children = [];

  void _init() {
    module = llvm.getModule(kModule);
    llvmContext = llvm.getLLVMContext(kModule);
    fpm = llvm.getFPM(kModule);
    builder = llvm.LLVMCreateBuilderInContext(llvmContext);
  }

  late final KModuleRef kModule;
  @override
  late final LLVMModuleRef module;
  @override
  late final LLVMContextRef llvmContext;
  @override
  late final LLVMBuilderRef builder;

  late final LLVMPassManagerRef fpm;

  late LLVMConstVariable fn;

  void dispose() {
    llvm.LLVMDisposeBuilder(builder);
    for (var child in children) {
      child.dispose();
    }
    if (parent == null) {
      llvm.destory(kModule);
    }
  }

  BuildContext createChildContext() {
    final child = BuildContext._(this);
    children.add(child);
    return child;
  }

  LLVMBasicBlock createAndInsertBB(LLVMConstVariable val,
      {String name = 'entry'}) {
    final bb = llvm.LLVMAppendBasicBlockInContext(
        llvmContext, val.value, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, true);
  }

  LLVMBasicBlock createBB({String name = 'entry'}) {
    final bb = llvm.LLVMCreateBasicBlockInContext(llvmContext, name.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);
    return LLVMBasicBlock(bb, this, false);
  }

  void insertAfterBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    bb.inserted = true;
  }

  void insertPointBB(LLVMBasicBlock bb) {
    assert(!bb.inserted);
    llvm.LLVMAppendExistingBasicBlock(fn.value, bb.bb);
    llvm.LLVMPositionBuilderAtEnd(builder, bb.bb);
    bb.inserted = true;
  }

  void buildFnBB(Fn fn) {
    final fv = fn.llvmType.createValue(this);
    final isDecl = fn.block.stmts.isEmpty;

    if (isDecl) return;
    final bbContext = createChildContext();
    bbContext.fn = fv;
    bbContext.createAndInsertBB(fv);
    fn.block.build(bbContext);

    void voidRet() {
      final decl = fn.fnSign.fnDecl;
      if (decl.returnTy is BuiltInTy) {
        final lit = (decl.returnTy as BuiltInTy).ty;
        if (lit != LitKind.kVoid) {
          /// error
        }
        bbContext.ret(null);
      }
    }

    if (fn.block.stmts.isNotEmpty) {
      final lastStmt = fn.block.stmts.last;
      if (lastStmt is ExprStmt) {
        final expr = lastStmt.expr;
        if (expr is! RetExpr) {
          // 获取缓存的value
          final val = expr.build(bbContext)?.variable;
          if (val == null) {
            // error
          }
          bbContext.ret(val);
        }
      } else {
        voidRet();
      }
    } else {
      voidRet();
    }
    // mem2reg pass
    // llvm.LLVMRunFunctionPassManager(fpm, fv.value);
  }

  LLVMBasicBlock buildSubBB({String name = 'entry'}) {
    final child = createChildContext();
    child.fn = fn;
    return child.createBB(name: name);
  }

  bool _returned = false;
  void ret(Variable? val) {
    if (_returned) {
      // error
      return;
    }
    _returned = true;
    if (val == null) {
      llvm.LLVMBuildRetVoid(builder);
    } else {
      final v = val.load(this);
      llvm.LLVMBuildRet(builder, v);
    }
  }

  final loopBBs = <LLVMBasicBlock>[];

  LLVMBasicBlock getLoopBB(String? label) {
    if (label == null) {
      return _getLast();
    }
    var bb = _getLable(label);
    bb ??= _getLast();

    return bb;
  }

  LLVMBasicBlock _getLast() {
    if (loopBBs.isEmpty) {
      return parent!._getLast();
    }
    return loopBBs.last;
  }

  LLVMBasicBlock? _getLable(String label) {
    var bb = loopBBs.lastWhereOrNull((element) => element.label == label);
    if (bb == null) {
      return parent?._getLable(label);
    }
    return bb;
  }

  void forLoop(Block block, String? label, Expr? expr) {
    final loopBB = buildSubBB(name: 'loop');
    final loopAfter = buildSubBB(name: 'loop_after');
    loopAfter.label = label;
    loopAfter.parent = loopBB;
    loopBBs.add(loopAfter);
    br(loopBB.context);
    insertPointBB(loopBB);

    if (expr != null) {
      final v = expr.build(loopBB.context);
      final variable = v?.variable;
      if (variable != null) {
        final bb = buildSubBB(name: 'loop_body');
        llvm.LLVMBuildCondBr(
            loopBB.context.builder, variable.load(this), bb.bb, loopAfter.bb);
        insertPointBB(bb);
        block.build(bb.context);
        bb.context.br(this);
      }
    } else {
      block.build(loopBB.context);
      loopBB.context.br(this);
    }
    insertPointBB(loopAfter);
    loopBBs.remove(loopAfter);
  }

  LLVMTempVariable? createIfBlock(IfExprBlock ifb) {
    final v = buildIfExprBlock(ifb);
    if (v == null) return null;
    return LLVMTempVariable(v);
  }

  LLVMValueRef? buildIfExprBlock(IfExprBlock ifEB) {
    final elseifBlock = ifEB.child;
    final elseBlock = ifEB.elseBlock;
    final onlyIf = elseifBlock == null && elseBlock == null;
    assert(onlyIf || (elseBlock != null) != (elseifBlock != null));
    final then = buildSubBB(name: 'then');
    final elseBB = buildSubBB(name: elseifBlock == null ? 'else' : 'elseIf');
    final afterBB = buildSubBB(name: 'after');

    final con = ifEB.expr.build(this)?.variable;
    if (con == null) return null;

    insertAfterBB(then);
    if (onlyIf) {
      llvm.LLVMBuildCondBr(builder, con.load(this), then.bb, afterBB.bb);
    } else {
      llvm.LLVMBuildCondBr(builder, con.load(this), then.bb, elseBB.bb);
    }
    ifEB.block.build(then.context);
    then.context.br(afterBB.context);

    if (elseifBlock != null) {
      insertAfterBB(elseBB);
      elseBB.context.buildIfExprBlock(elseifBlock);
      elseBB.context.br(afterBB.context);
    } else if (elseBlock != null) {
      insertAfterBB(elseBB);
      ifEB.elseBlock?.build(elseBB.context);
      elseBB.context.br(afterBB.context);
    }
    insertPointBB(afterBB);

    // final ty = llvm.LLVMInt32Type();
    // final tNull = llvm.LLVMConstNull(ty);
    // final phi = llvm.LLVMBuildPhi(builder, ty, unname);
    // final listT = [tNull, tNull].toNative();
    // final bbs = [then.bb, elseBB.bb].toNative();
    // llvm.LLVMAddIncoming(phi, listT.cast(), bbs.cast(), 2);
    return null;
  }

  bool _breaked = false;

  void br(BuildContext to) {
    if (_breaked) return;
    _breaked = true;
    llvm.LLVMBuildBr(builder, llvm.LLVMGetInsertBlock(to.builder));
  }

  void brLoop() {
    if (_breaked) return;

    _breaked = true;

    llvm.LLVMBuildBr(builder, getLoopBB(null).bb);
  }

  void contine() {
    if (_breaked) return;
    _breaked = true;

    llvm.LLVMBuildBr(builder, getLoopBB(null).parent!.bb);
  }

  LLVMValueRef createAlloca(LLVMTypeRef type, Identifier ident) {
    // 在 entry 中分配
    // final builder = llvm.LLVMCreateBuilderInContext(llvmContext);
    // final fnEntry = llvm.LLVMGetFirstBasicBlock(fn.value);
    // llvm.LLVMPositionBuilderAtEnd(builder, fnEntry);

    final alloca =
        llvm.LLVMBuildAlloca(builder, type, 'alloca_$ident'.toChar());
    llvm.LLVMSetAlignment(alloca, 4);
    return alloca;
  }

  LLVMTempOpVariable math(Variable lhs, Variable rhs, OpKind op, bool isFloat,
      {bool signed = true}) {
    final l = lhs.load(this);
    final r = rhs.load(this);
    LLVMValueRef value;
    Ty? returnTy;
    if (!isFloat) {
      if (op == OpKind.Sub) {
        value = llvm.LLVMBuildSub(builder, l, r, unname);
      } else if (op == OpKind.Lt) {
        value = llvm.LLVMBuildICmp(
            builder, LLVMIntPredicate.LLVMIntULT, l, r, unname);
        returnTy = BuiltInTy.kBool;
      } else {
        value = llvm.LLVMBuildAdd(builder, l, r, unname);
      }
    } else {
      if (op == OpKind.Sub) {
        value = llvm.LLVMBuildFSub(builder, l, r, unname);
      } else if (op == OpKind.Lt) {
        value = llvm.LLVMBuildFCmp(
            builder, LLVMRealPredicate.LLVMRealOLT, r, r, unname);
        returnTy = BuiltInTy.kBool;
      } else {
        value = llvm.LLVMBuildFAdd(builder, l, r, unname);
      }
    }
    return LLVMTempOpVariable(returnTy ?? lhs.ty, isFloat, signed, value);
  }
}
