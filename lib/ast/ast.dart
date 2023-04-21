// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/ast/stmt.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:llvm_dart/ast/variables.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'llvm_types.dart';

String getWhiteSpace(int level, int pad) {
  return ' ' * level * pad;
}

class RawIdent with EquatableMixin {
  RawIdent(this.start, this.end);
  final int start;
  final int end;

  @override
  List<Object?> get props => [start, end];
}

class Identifier with EquatableMixin {
  Identifier(this.name, this.start, int? end)
      : end = (end ?? start) + 1,
        builtInName = '';

  Identifier.fromToken(Token token)
      : start = token.start,
        end = token.end,
        builtInName = '',
        name = '';

  Identifier.builtIn(this.builtInName)
      : name = '',
        start = 0,
        end = 0;

  final String name;
  final int start;
  final int end;
  final String builtInName;

  RawIdent get toRawIdent {
    return RawIdent(start, end);
  }

  static final Identifier none = Identifier('', 0, 0);

  String ext([int count = 1]) {
    if (start <= 0) return src;
    final s = (start - count).clamp(0, start);
    if (identical(this, none)) {
      return '';
    }
    if (builtInName.isNotEmpty) {
      return builtInName;
    }
    final raw = Zone.current['astSrc'];
    if (raw is String) {
      return raw.substring(s, end);
    }
    return '';
  }

  @override
  List<Object?> get props {
    if (identical(this, none)) {
      return [''];
    }
    if (builtInName.isNotEmpty) {
      return [builtInName];
    }
    final src = Zone.current['astSrc'];
    if (src is String) {
      return [src.substring(start, end)];
    }
    return [name, start, end];
  }

  String get src {
    if (identical(this, none)) {
      return '';
    }
    if (builtInName.isNotEmpty) {
      return builtInName;
    }
    final src = Zone.current['astSrc'];
    if (src is String) {
      return src.substring(start, end);
    }
    return '';
  }

  /// 指示当前的位置
  String get light {
    final src = Zone.current['astSrc'];
    if (src is String) {
      return lightSrc(src, start, end);
    }
    return '';
  }

  static String lightSrc(String src, int start, int end) {
    var lineStart = start;
    if (start > 0) {
      lineStart = src.substring(0, start).lastIndexOf('\n');
      if (lineStart != -1) {
        lineStart += 1;
      }
    }
    var lineEnd = src.substring(start).indexOf('\n');
    if (lineEnd == -1) {
      lineEnd = end;
    } else {
      lineEnd += start;
    }
    if (lineStart != -1) {
      final vs = src.substring(lineStart, lineEnd);
      final s = ' ' * (start - lineStart);
      final v = '^' * (end - start);
      return '$vs\n$s$v';
    }
    return src.substring(start, end);
  }

  @override
  String toString() {
    if (identical(this, none)) {
      return '';
    }
    if (builtInName.isNotEmpty) {
      return '[$builtInName]';
    }
    final src = Zone.current['astSrc'];
    var rang = '[$start - $end]';
    if (src is String) {
      rang = src.substring(start, end);
    }
    return '$name$rang';
  }
}

// foo( ... ), Gen{ ... }
class GenericParam with EquatableMixin {
  GenericParam(this.ident, this.ty);
  final Identifier ident;
  final PathTy ty;

  bool get isRef => ty.isRef;

  @override
  String toString() {
    return '$ident: $ty';
  }

  @override
  List<Object?> get props => [ident, ty];

  void analysis(AnalysisContext context) {
    context.pushVariable(
      ident,
      context.createVal(ty.grt(context), ident, ty.kind)
        ..lifeCycle.isOut = true,
    );
  }
}

class ExprTempValue {
  ExprTempValue(this.variable, this.ty);
  final Ty ty;
  final Variable? variable;
}

abstract class Expr extends BuildMixin {
  bool _first = true;
  @override
  ExprTempValue? build(BuildContext context) {
    if (!_first) return _ty;
    _first = false;
    return _ty ??= buildExpr(context);
  }

  Expr clone();

  @override
  AnalysisVariable? analysis(AnalysisContext context);

  ExprTempValue? _ty;
  ExprTempValue? get currentTy => _ty;

  @protected
  ExprTempValue? buildExpr(BuildContext context);
}

class UnknownExpr extends Expr {
  UnknownExpr(this.ident, this.message);
  final Identifier ident;
  final String message;

  @override
  Expr clone() {
    return this;
  }

  @override
  String toString() {
    return 'UnknownExpr $ident($message)';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.errorExpr(this);
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }
}

abstract class BuildMixin {
  int level = 0;
  @mustCallSuper
  void incLevel([int count = 1]) {
    level += count;
  }

  void build(BuildContext context);

  void analysis(AnalysisContext context);

  static int padSize = 2;

  String get pad => getWhiteSpace(level, padSize);
  @override
  String toString() {
    return pad;
  }
}

abstract class Stmt extends BuildMixin with EquatableMixin {
  Stmt clone();
}

enum LitKind {
  kFloat('float'),
  kDouble('double'),
  f32('f32'),
  f64('f64'),
  kInt('int'),
  kString('string'),

  i8('i8'),
  i16('i16'),
  i32('i32'),
  i64('i64'),
  i128('i128'),

  u8('u8'),
  u16('u16'),
  u32('u32'),
  u64('u64'),
  u128('u128'),
  usize('usize'),

  kBool('bool'),
  kVoid('void'),
  ;

  bool get isFp {
    if (index <= f64.index) {
      return true;
    }
    return false;
  }

  bool get isInt {
    if (index > f64.index && index < kBool.index) {
      return true;
    }
    return false;
  }

  LitKind get convert {
    if (index >= u8.index && index <= u128.index) {
      return values[index - 5];
    }
    return this;
  }

  bool get signed {
    assert(isInt);
    if (index >= i8.index && index <= i128.index) {
      return true;
    }
    return false;
  }

  final String lit;
  const LitKind(this.lit);

  static LitKind? from(LiteralKind kind) {
    return values.firstWhereOrNull((element) => element.lit == kind.lit);
  }
}

class Block extends BuildMixin with EquatableMixin {
  Block(this.stmts, this.ident) {
    // {
    //   stmt
    // }
    for (var s in stmts) {
      s.incLevel();
    }
  }
  final Identifier? ident;
  final List<Stmt> stmts;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);

    for (var s in stmts) {
      s.incLevel(count);
    }
  }

  Block clone() {
    return Block(stmts.map((e) => e.clone()).toList(), ident);
  }

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = stmts.map((e) => '$e\n').join();
    return '${ident ?? ''} {\n$s$p}';
  }

  @override
  void build(BuildContext context) {
    final fnStmt = <Stmt>[];

    // 函数声明前置
    for (var stmt in stmts) {
      if (stmt is ExprStmt) {
        final expr = stmt.expr;
        if (expr is FnExpr) {
          expr.fn.pushFn(context);
          fnStmt.add(stmt);
          continue;
        }
      }
    }

    // 先处理普通语句，在内部函数中可能会引用到变量等
    for (var stmt in stmts) {
      if (fnStmt.contains(stmt)) continue;
      stmt.build(context);
    }

    for (var fn in fnStmt) {
      fn.build(context);
    }
  }

  @override
  List<Object?> get props => [stmts];

  @override
  void analysis(AnalysisContext context) {
    final fnStmt = <Stmt>[];
    for (var stmt in stmts) {
      if (stmt is ExprStmt) {
        final expr = stmt.expr;
        if (expr is FnExpr) {
          expr.fn.pushFn(context);
          fnStmt.add(stmt);
          continue;
        }
      }
    }

    for (var stmt in stmts) {
      if (fnStmt.contains(stmt)) continue;
      stmt.analysis(context);
    }
    for (var fn in fnStmt) {
      fn.analysis(context);
    }
  }
}

// 函数声明
class FnDecl with EquatableMixin {
  FnDecl(this.ident, this.params, this.returnTy, this.isVar);
  final Identifier ident;
  final List<GenericParam> params;
  final PathTy returnTy;
  final bool isVar;

  bool eq(FnDecl other) {
    return const DeepCollectionEquality().equals(params, other.params) &&
        returnTy == other.returnTy;
  }

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    return '$ident(${params.join(',')}$isVals) -> $returnTy';
  }

  @override
  List<Object?> get props => [ident, params, returnTy];

  void analysis(AnalysisContext context) {
    for (var p in params) {
      p.analysis(context);
    }
  }
}

// 函数签名
class FnSign with EquatableMixin {
  FnSign(this.extern, this.fnDecl);
  final FnDecl fnDecl;
  // header
  final bool extern;

  @override
  String toString() {
    return fnDecl.toString();
  }

  void analysis(AnalysisContext context) {
    fnDecl.analysis(context);
  }

  @override
  List<Object?> get props => [fnDecl, extern];
}

/// ----- Ty -----

abstract class Ty extends BuildMixin with EquatableMixin {
  // @override
  // void build(BuildContext context) {
  //   throw UnimplementedError('ty');
  // }

  static final PathTy unknown = UnknownTy(Identifier('', 0, 0));

  LLVMType get llvmType;

  Ty getRealTy(BuildContext c) => this;

  bool extern = false;
  @override
  void build(BuildContext context);
}

class RefTy extends Ty {
  RefTy(this.parent);
  final Ty parent;

  Ty get baseTy {
    if (parent is RefTy) {
      return (parent as RefTy).baseTy;
    }
    return parent;
  }

  @override
  void build(BuildContext context) {}
  @override
  void analysis(AnalysisContext context) {}

  @override
  LLVMRefType get llvmType => LLVMRefType(this);

  @override
  List<Object?> get props => [parent];
}

class BuiltInTy extends Ty {
  BuiltInTy._(this._ty);
  static final int = BuiltInTy._(LitKind.kInt);
  static final float = BuiltInTy._(LitKind.kFloat);
  static final double = BuiltInTy._(LitKind.kDouble);
  static final string = BuiltInTy._(LitKind.kString);
  static final kVoid = BuiltInTy._(LitKind.kVoid);
  static final kBool = BuiltInTy._(LitKind.kBool);
  BuiltInTy.lit(this._ty);

  final LitKind _ty;
  LitKind get ty => _ty.convert;

  static BuiltInTy? from(String src) {
    final lit = LitKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy._(lit);
  }

  @override
  String toString() {
    return _ty.lit;
  }

  @override
  List<Object?> get props => [ty];

  @override
  LLVMTypeLit get llvmType => LLVMTypeLit(this);

  @override
  void build(BuildContext context) {}
  @override
  void analysis(AnalysisContext context) {}
}

/// [PathTy] 只用于声明
class PathTy with EquatableMixin {
  PathTy(this.ident, [this.kind = const []]) : ty = null;
  PathTy.ty(Ty this.ty, [this.kind = const []]) : ident = Identifier.none;
  final Identifier ident;
  final Ty? ty;
  final List<PointerKind> kind;

  bool? _isRef;
  bool get isRef => _isRef ??= kind.isRef;

  @override
  String toString() {
    if (ty != null) return ty!.toString();
    return '${kind.join('')}$ident';
  }

  @override
  List<Object?> get props => [ident];

  void build(BuildContext context) {
    if (ty != null) return;

    final tySrc = ident.src;
    var rty = BuiltInTy.from(tySrc);
    if (rty != null) {
      final hasTy = context.contains(rty);
      assert(hasTy);
    }
  }

  Ty getRty(Tys c) {
    return kind.resolveTy(grt(c));
  }

  Ty grt(Tys c) {
    var rty = ty;
    // if (ty != null) return ty!;

    final tySrc = ident.src;
    rty ??= BuiltInTy.from(tySrc);

    rty ??= c.getTy(ident);
    if (rty == null) {
      // error
    }

    return rty!;
  }
}

class UnknownTy extends PathTy {
  UnknownTy(Identifier ident) : super(ident, []);
  @override
  String toString() {
    return '{Unknown}';
  }
}

class FnTy extends Fn {
  FnTy(FnDecl fnDecl) : super(FnSign(false, fnDecl), null);

  FnTy clone(Set<AnalysisVariable> extra) {
    final rawDecl = fnSign.fnDecl;
    final cache = rawDecl.params.toList();
    for (var e in extra) {
      cache.add(GenericParam(e.ident, PathTy.ty(e.ty, [PointerKind.ref])));
    }
    final decl = FnDecl(rawDecl.ident, cache, rawDecl.returnTy, rawDecl.isVar);
    return FnTy(decl);
  }

  @override
  LLVMConstVariable? build(BuildContext context,
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    return null;
  }
}

class Fn extends Ty {
  Fn(this.fnSign, this.block);

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    block?.incLevel(count);
  }

  final FnSign fnSign;
  final Block? block;

  @override
  String toString() {
    var b = '';
    if (block != null) {
      b = '$block';
    }
    if (extern) {
      return '${pad}extern fn $fnSign$b';
    }
    return '${pad}fn $fnSign$b';
  }

  @override
  List<Object?> get props => [fnSign, block];

  final _cache = <ListKey, LLVMConstVariable>{};

  void pushFn(Tys context) {
    context.pushFn(fnSign.fnDecl.ident, this);
  }

  @override
  LLVMConstVariable? build(BuildContext context,
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    context.pushFn(fnSign.fnDecl.ident, this);
    return customBuild(context, variables, map);
  }

  LLVMConstVariable? customBuild(BuildContext context,
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    final key = ListKey(variables?.map((e) => e.ty).toList() ?? []);
    return _cache.putIfAbsent(key, () {
      return context.buildFnBB(this, variables, map ?? const {});
    });
  }

  Set<AnalysisVariable> selfVariables = {};
  Set<AnalysisVariable> get variables {
    final v = _get?.call();
    if (v == null) return selfVariables;
    return {...selfVariables, ...v};
  }

  Set<AnalysisVariable> Function()? _get;

  List<RawIdent> sretVariables = [];

  bool _anaysised = false;

  @override
  void analysis(AnalysisContext context) {
    if (_anaysised) return;
    _anaysised = true;
    context.pushFn(fnSign.fnDecl.ident, this);
    final child = context.childContext();
    child.setFnContext(this);
    fnSign.fnDecl.analysis(child);
    block?.analysis(child);
    selfVariables = child.catchVariables;
    _get = () => child.childrenVariables;
    if (block != null && block!.stmts.isNotEmpty) {
      final lastStmt = block!.stmts.last;
      if (lastStmt is ExprStmt) {
        var expr = lastStmt.expr;
        if (expr is! RetExpr) {
          final val = expr.analysis(child);
          if (val != null) {
            sretVariables.add(val.ident.toRawIdent);
          }
        }
      }
    }
  }

  @override
  late final LLVMFnType llvmType = LLVMFnType(this);
}

class ImplFn extends Fn {
  ImplFn(super.fnSign, super.block, this.ty);
  final StructTy ty;
}

class FieldDef {
  FieldDef(this.ident, this.ty);
  final Identifier ident;
  final PathTy ty;
  List<PointerKind> get kinds => ty.kind;
  @override
  String toString() {
    return '$ident: ${kinds.join('')}$ty';
  }

  bool? _isRef;
  bool get isRef => _isRef ??= kinds.isRef;
}

class StructTy extends Ty with EquatableMixin {
  StructTy(this.ident, this.fields);
  final Identifier ident;
  final List<FieldDef> fields;

  @override
  String toString() {
    return '${pad}struct $ident {${fields.join(',')}}';
  }

  @override
  List<Object?> get props => [ident, fields];

  @override
  void build(BuildContext context) {
    context.pushStruct(ident, this);
    context.pushVariable(ident, TyVariable(this));
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushStruct(ident, this);
  }

  @override
  late final LLVMStructType llvmType = LLVMStructType(this);
}

class UnionTy extends StructTy {
  UnionTy(super.ident, super.fields);
}

class EnumTy extends Ty {
  EnumTy(this.ident, this.variants) {
    for (var v in variants) {
      v.parent = this;
    }
  }
  final Identifier ident;
  final List<EnumItem> variants;

  @override
  String toString() {
    return 'enum $ident {${variants.join(',')}}';
  }

  @override
  List<Object?> get props => [ident, variants];

  @override
  void build(BuildContext context) {
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.build(context);
    }
  }

  @override
  late LLVMEnumType llvmType = LLVMEnumType(this);

  @override
  void analysis(AnalysisContext context) {
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.analysis(context);
    }
  }
}

/// 与 `struct` 类似
class EnumItem extends StructTy {
  EnumItem(super.ident, super.fields);
  late EnumTy parent;
  @override
  String toString() {
    final f = fields.map((e) => e.ty).join(',');
    final fy = f.isEmpty ? '' : '($f)';
    return '$ident$fy';
  }

  @override
  // ignore: overridden_fields
  late final LLVMEnumItemType llvmType = LLVMEnumItemType(this);
}

class ComponentTy extends Ty {
  ComponentTy(this.ident, this.fns);

  final Identifier ident;
  List<FnSign> fns;

  @override
  void build(BuildContext context) {
    context.pushComponent(ident, this);
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushComponent(ident, this);
  }

  @override
  String toString() {
    final pddd = getWhiteSpace(level + 1, BuildMixin.padSize);
    return 'com $ident {\n$pddd${fns.join('\n$pddd')}\n$pad}';
  }

  @override
  List<Object?> get props => [ident, fns];

  @override
  LLVMType get llvmType => throw UnimplementedError();
}

class ImplTy extends Ty {
  ImplTy(this.ident, this.com, this.ty, this.label, this.fns, this.staticFns) {
    for (var fn in fns) {
      fn.incLevel();
    }
    for (var fn in staticFns) {
      fn.incLevel();
    }
  }
  final PathTy ty;
  final Identifier ident;
  final Identifier? com;
  final Identifier? label;
  final List<Fn> fns;
  final List<Fn> staticFns;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var fn in fns) {
      fn.incLevel(count);
    }

    for (var fn in staticFns) {
      fn.incLevel(count);
    }
  }

  Fn? getFn(Identifier ident) {
    return _fns?.firstWhereOrNull((e) => e.fnSign.fnDecl.ident == ident);
  }

  List<ImplFn>? _fns;

  void initStructFns(Tys context) {
    final structTy = context.getStruct(ident);
    if (structTy == null) return;
    context.pushImplForStruct(structTy, this);
    final ty = context.getStruct(ident);
    if (ty == null) {
      //error
      return;
    }
    _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty)).toList();
  }

  @override
  void build(BuildContext context) {
    context.pushImpl(ident, this);
    // check ty
    final structTy = context.getStruct(ident);
    if (structTy == null) return;
    context.pushImplForStruct(structTy, this);
    final ty = context.getStruct(ident);
    if (ty == null) {
      //error
      return;
    }

    for (var fn in staticFns) {
      fn.customBuild(context);
    }
    final ifns =
        _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty)).toList();
    for (var fn in ifns) {
      fn.customBuild(context);
    }
  }

  @override
  String toString() {
    final l = label == null ? '' : ': $label';
    final cc = com == null ? '' : '$com$l for ';
    var sfnn = staticFns.map((e) {
      final pad = getWhiteSpace(level + 1, BuildMixin.padSize);
      var str = '$e'.toString().replaceFirst(pad, '${pad}static ');
      return '$str\n';
    }).join();
    var fnnStr = fns.map((e) => '$e\n').join();

    if (sfnn.isNotEmpty) {
      fnnStr = '$pad$fnnStr';
    }
    return 'impl $cc$ty {\n$pad$sfnn$fnnStr$pad}';
  }

  @override
  List<Object?> get props => [ident, ty, fns, label];

  @override
  LLVMType get llvmType => throw UnimplementedError();

  @override
  void analysis(AnalysisContext context) {
    context.pushImpl(ident, this);
    final structTy = context.getStruct(ident);
    if (structTy == null) return;
    context.pushImplForStruct(structTy, this);
    final ty = context.getStruct(ident);
    if (ty == null) {
      //error
      return;
    }
  }
}
