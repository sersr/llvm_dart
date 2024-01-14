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
}

ExprTempValue? doBuiltFns(
    FnBuildMixin context, Ty? fn, List<FieldExpr> params) {
  if (fn is BuiltinFn) {
    return fn.runFn(context, params);
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
    FnBuildMixin context, List<FieldExpr> params);

final class BuiltinFn extends Ty {
  BuiltinFn(this.name, this.runFn) {
    _fns.add(this);
  }

  static final _fns = <BuiltinFn>[];

  final Identifier name;

  @override
  Identifier get ident => name;

  @override
  void analysis(AnalysisContext context) {}

  final BuiltinFnRun runFn;
  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  List<Object?> get props => [name];
}

ExprTempValue? sizeOf(FnBuildMixin context, List<FieldExpr> params) {
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

final sizeOfFn = BuiltinFn(Identifier.builtIn('sizeOf'), sizeOf);

// LLVMAllocaVariable elmentAt(
//     BuildContext c, Ty elementTy, Variable v, Variable index) {
//   if (elementTy is RefTy) {
//     elementTy = elementTy.parent;
//   }
//   final tyy = elementTy.llvmType.createType(c);

//   final ptr = v.getBaseValue(c);
//   final indics = <LLVMValueRef>[index.load(c, Offset.zero)];

//   final llValue = llvm.LLVMBuildInBoundsGEP2(
//       c.builder, tyy, ptr, indics.toNative(), indics.length, unname);

//   return LLVMAllocaVariable(elementTy, llValue, tyy);
// }

// final elementAt = BuiltinFn(Identifier.builtIn('getElement'));

ExprTempValue memSet(FnBuildMixin context, List<FieldExpr> params) {
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

final memSetFn = BuiltinFn(Identifier.builtIn('memSet'), memSet);
ExprTempValue memCopy(FnBuildMixin context, List<FieldExpr> params) {
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

final memCopyFn = BuiltinFn(Identifier.builtIn('memCopy'), memCopy);
