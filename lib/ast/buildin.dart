import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'expr.dart';
import 'llvm/coms.dart';
import 'llvm/llvm_context.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
import 'memory.dart';
import 'tys.dart';

void initBuiltinFns(Tys context) {
  _init();
  for (var fn in BuiltinFn._fns) {
    context.pushBuiltinFn(fn.name, fn);
  }
}

bool _inited = false;
void _init() {
  if (_inited) return;
  sizeOfFn;
  memSetFn;
  memCopyFn;
  addFreeFn;
  ptrSetValueFn;
}

ExprTempValue? doBuiltFns(
    FnBuildMixin context, Ty? fn, Identifier ident, List<FieldExpr> params) {
  if (fn is BuiltinFn) {
    return fn.runFn(context, ident, params);
  }
  return null;
}

AnalysisVariable? doAnalysisFns(AnalysisContext context, Ty? fn) {
  if (fn is BuiltinFn) {
    final ty = fn.retType;

    if (ty != null) {
      return context.createVal(ty, Identifier.none);
    }
  }

  return null;
}

BuiltinFn? isBuiltinFn(Identifier ident) {
  for (var fn in BuiltinFn._fns) {
    if (fn.name == ident) {
      return fn;
    }
  }
  return null;
}

typedef BuiltinFnRun = ExprTempValue? Function(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params);

final class BuiltinFn extends Ty {
  BuiltinFn(String name, this.runFn, {this.retType}) : name = name.ident {
    _fns.add(this);
  }

  static final _fns = <BuiltinFn>[];

  final Identifier name;

  @override
  Identifier get ident => name;

  final Ty? retType;

  final BuiltinFnRun runFn;
  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  late final props = [name, retType, runFn];

  @override
  BuiltinFn clone() {
    return this;
  }
}

ExprTempValue? sizeOf(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  assert(params.isNotEmpty);

  final first = params.first;
  final e = first.expr.build(context);
  Ty? ty = e?.ty;
  if (ty == null) {
    var e = first.expr;

    if (e is VariableIdentExpr) {
      final p = e.pathTy;
      ty = p.grt(context);
    }
  }

  if (ty is EnumItem) {
    ty = ty.parent;
  }
  final tyy = ty!.typeOf(context);
  final size = context.typeSize(tyy);

  final v = context.usizeValue(size);
  final vv = LLVMConstVariable(v, LiteralKind.usize.ty, Identifier.none);
  return ExprTempValue(vv);
}

final sizeOfFn = BuiltinFn('sizeOf', sizeOf, retType: LiteralKind.usize.ty);

ExprTempValue memSet(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  Variable lhs = params[0].build(context)!.variable!;

  Variable rhs = params[1].build(context)!.variable!;
  Variable len = params[2].build(context)!.variable!;

  final lv = lhs.load(context);
  final rv = rhs.load(context);
  final lenv = len.load(context);
  final align = context.getBaseAlignSize(rhs.ty);
  final value = llvm.LLVMBuildMemSet(context.builder, lv, rv, lenv, align);

  final v = LLVMConstVariable(value, LiteralKind.usize.ty, Identifier.none);
  return ExprTempValue(v);
}

final memSetFn = BuiltinFn('memSet', memSet, retType: LiteralKind.usize.ty);
ExprTempValue memCopy(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  Variable lhs = params[0].build(context)!.variable!;

  Variable rhs = params[1].build(context)!.variable!;
  Variable len = params[2].build(context)!.variable!;

  final lv = lhs.load(context);
  final rv = rhs.load(context);
  final lenv = len.load(context);
  final lalign = context.getBaseAlignSize(lhs.ty);
  final align = context.getBaseAlignSize(rhs.ty);
  final value =
      llvm.LLVMBuildMemCpy(context.builder, lv, lalign, rv, align, lenv);

  final v = LLVMConstVariable(
      value, RefTy.pointer(LiteralKind.kVoid.ty), Identifier.none);
  return ExprTempValue(v);
}

final memCopyFn =
    BuiltinFn('memCopy', memCopy, retType: RefTy.pointer(LiteralKind.kVoid.ty));

ExprTempValue? addFree(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  final val = params[0].build(context)!.variable!;
  context.addFree(val);
  return null;
}

final addFreeFn = BuiltinFn('addFree', addFree);

ExprTempValue? removeFn(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  final val = params[0].build(context)!.variable!;
  context.removeVal(val);
  return null;
}

final removeFreeFn = BuiltinFn('removeFreeFn', removeFn);

ExprTempValue? ptrSetValue(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  final ptr = params[0].build(context)!.variable!;
  final offset = params[1].build(context)!.variable!;
  final value = params[2].build(context)!.variable!;

  final elementTy = ptr.ty.typeOf(context);

  final index = offset.load(context);
  final indics = <LLVMValueRef>[index];
  final p = ptr.load(context);

  context.diSetCurrentLoc(ident.offset);
  final addr = llvm.LLVMBuildInBoundsGEP2(
      context.builder, elementTy, p, indics.toNative(), indics.length, unname);
  final alloca = LLVMAllocaVariable(addr, ptr.ty, elementTy, ident);

  ImplStackTy.addStack(context, value);

  alloca.store(context, value.load(context));
  return null;
}

final ptrSetValueFn = BuiltinFn('ptrSetValue', ptrSetValue);
