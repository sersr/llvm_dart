import '../llvm_dart.dart';
import 'analysis_context.dart';
import 'ast.dart';
import 'expr.dart';
import 'llvm/llvm_context.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
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
  BuiltinFn(this.name, this.runFn, this.retType) {
    _fns.add(this);
  }

  static final _fns = <BuiltinFn>[];

  final Identifier name;

  @override
  Identifier get ident => name;

  @override
  void analysis(AnalysisContext context) {}
  final Ty? retType;

  final BuiltinFnRun runFn;
  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  List<Object?> get props => [name];

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
      final p = PathTy(e.ident, e.generics);
      ty = p.grt(context);
    }
  }

  if (ty is EnumItem) {
    ty = ty.parent;
  }
  final tyy = ty!.typeOf(context);
  final size = context.typeSize(tyy);

  final v = context.usizeValue(size);
  final vv = LLVMConstVariable(v, BuiltInTy.usize, Identifier.none);
  return ExprTempValue(vv);
}

final sizeOfFn =
    BuiltinFn(Identifier.builtIn('sizeOf'), sizeOf, BuiltInTy.usize);

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

  final v = LLVMConstVariable(value, BuiltInTy.usize, Identifier.none);
  return ExprTempValue(v);
}

final memSetFn =
    BuiltinFn(Identifier.builtIn('memSet'), memSet, BuiltInTy.usize);
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

  final v =
      LLVMConstVariable(value, RefTy.pointer(BuiltInTy.kVoid), Identifier.none);
  return ExprTempValue(v);
}

final memCopyFn = BuiltinFn(
    Identifier.builtIn('memCopy'), memCopy, RefTy.pointer(BuiltInTy.kVoid));

ExprTempValue? addFree(
    FnBuildMixin context, Identifier ident, List<FieldExpr> params) {
  final val = params[0].build(context)!.variable!;
  context.addFree(val);
  return null;
}

final addFreeFn =
    BuiltinFn(Identifier.builtIn('addFree'), addFree, BuiltInTy.kVoid);
