// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'builders/builders.dart';
import 'context.dart';
import 'expr.dart';
import 'llvm/build_methods.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
import 'memory.dart';
import 'stmt.dart';
import 'tys.dart';

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

class Offset {
  const Offset(this.row, this.column);

  static const zero = Offset(0, 0);

  bool get isValid => column > 0 && row > 0;
  final int column;
  final int row;

  String get pathStyle {
    return '$row:$column';
  }

  @override
  String toString() {
    return '{row: $row, column: $column}';
  }
}

class Identifier with EquatableMixin {
  Identifier.fromToken(Token token, this.data)
      : start = token.start,
        end = token.end,
        lineStart = token.lineStart,
        lineEnd = token.lineEnd,
        lineNumber = token.lineNumber,
        builtInValue = '',
        isStr = false,
        name = '';

  Identifier.builtIn(this.builtInValue)
      : name = '',
        start = 0,
        lineStart = -1,
        lineEnd = -1,
        isStr = false,
        lineNumber = 0,
        end = 0,
        data = '';
  Identifier.str(Token tokenStart, Token tokenEnd, this.builtInValue)
      : start = tokenStart.start,
        end = tokenEnd.end,
        lineStart = tokenStart.lineStart,
        lineEnd = tokenEnd.lineEnd,
        isStr = true,
        lineNumber = tokenStart.lineNumber,
        data = '',
        name = '';

  final String name;
  final int start;
  final int lineStart;
  final int lineEnd;
  final int lineNumber;
  final int end;
  final String builtInValue;
  final bool isStr;

  @protected
  final String data;

  bool get isValid => end != 0;

  RawIdent get toRawIdent {
    return RawIdent(start, end);
  }

  Offset? _offset;

  Offset get offset {
    if (_offset != null) return _offset!;
    if (!isValid) return Offset.zero;

    return _offset = Offset(lineNumber, start - lineStart + 1);
  }

  static final Identifier none = Identifier.builtIn('');
  static final Identifier self = Identifier.builtIn('self');

  /// 在parser下要求更多字段相等
  static bool get identicalEq {
    return Zone.current[#data] == true;
  }

  static R run<R>(R Function() body, {ZoneSpecification? zoneSpecification}) {
    return runZoned(body,
        zoneValues: {#data: true}, zoneSpecification: zoneSpecification);
  }

  @override
  List<Object?> get props {
    if (identicalEq) {
      return [data, start, end, name];
    }
    return [src];
  }

  String? _src;
  String get src {
    if (_src != null) return _src!;
    if (identical(this, none)) {
      return '';
    }
    if (builtInValue.isNotEmpty || isStr) {
      return builtInValue;
    }

    if (lineStart == -1) {
      return '';
    }
    return _src = data.substring(start, end);
  }

  /// 指示当前的位置
  String get light {
    if (lineStart == -1) {
      return '';
    }

    final line = data.substring(lineStart, lineEnd);
    final space = ' ' * (start - lineStart);
    // lineEnd 没有包括换行符
    final arrow = '^' * (math.min(end, lineEnd + 1) - start);
    return '$line\n$space\x1B[31m$arrow\x1B[0m';
  }

  static String lightSrc(String src, int start, int end) {
    var lineStart = start;
    if (start > 0) {
      lineStart = src.substring(0, start).lastIndexOf('\n');
      if (lineStart != -1) {
        lineStart += 1;
      } else {
        lineStart = 0;
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
    if (builtInValue.isNotEmpty) {
      return '[$builtInValue]';
    }
    if (identical(this, none) || lineStart == -1) {
      return '';
    }

    return data.substring(start, end);
  }
}

class ExprTempValue {
  ExprTempValue(Variable this.variable)
      : _ty = null,
        _ident = null;

  ExprTempValue.ty(Ty this._ty, this._ident) : variable = null;
  final Ty? _ty;
  final Variable? variable;
  final Identifier? _ident;
  Identifier? get ident => _ident ?? variable?.ident;
  Ty get ty => variable?.ty ?? _ty!;
}

abstract class Expr extends BuildMixin {
  bool _first = true;

  bool get hasUnknownExpr => false;

  void reset() {
    _first = true;
    _temp = null;
  }

  ExprTempValue? _temp;
  ExprTempValue? build(FnBuildMixin context, {Ty? baseTy}) {
    if (!_first) return _temp;
    _first = false;
    return _temp ??= buildExpr(context, baseTy);
  }

  ExprTempValue? get temp => _temp;

  Expr clone();

  Ty? getTy(StoreLoadMixin context) => null;

  @override
  AnalysisVariable? analysis(AnalysisContext context);

  @protected
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy);
}

mixin RetExprMixin on Expr {
  @override
  ExprTempValue? build(FnBuildMixin context, {Ty? baseTy, bool isRet = false}) {
    if (!_first) return _temp;
    _first = false;
    return _temp ??= buildRetExpr(context, baseTy, isRet);
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    throw 'use buildRetExpr';
  }

  ExprTempValue? buildRetExpr(FnBuildMixin context, Ty? baseTy, bool isRet);
}

class UnknownExpr extends Expr {
  UnknownExpr(this.ident, this.message);
  final Identifier ident;
  final String message;

  @override
  bool get hasUnknownExpr => true;

  @override
  Expr clone() {
    return this;
  }

  @override
  String toString() {
    return 'UnknownExpr: $ident';
  }

  @override
  ExprTempValue? buildExpr(FnBuildMixin context, Ty? baseTy) {
    context.errorExpr(this);
    return null;
  }

  @override
  AnalysisVariable? analysis(AnalysisContext context) {
    return null;
  }
}

abstract class Clone<T> {
  T clone();
}

abstract class BuildMixin {
  int level = 0;
  @mustCallSuper
  void incLevel([int count = 1]) {
    level += count;
  }

  final extensions = <Object, dynamic>{};

  void analysis(AnalysisContext context);

  static int padSize = 2;

  String get pad => getWhiteSpace(level, padSize);
  @override
  String toString() {
    return pad;
  }
}

abstract class Stmt extends BuildMixin with EquatableMixin {
  void build(FnBuildMixin context, bool isRet);
  Stmt clone();
}

enum LitKind {
  kFloat('float'),
  kDouble('double'),
  f32('f32'),
  f64('f64'),
  kInt('int'),
  kStr('str'),

  i8('i8'),
  i16('i16'),
  i32('i32'),
  i64('i64'),
  i128('i128'),
  isize('isize'),

  u8('u8'),
  u16('u16'),
  u32('u32'),
  u64('u64'),
  u128('u128'),
  usize('usize'),

  kBool('bool'),
  kVoid('void'),
  ;

  bool get isSize => this == isize || this == usize;

  bool get isFp {
    if (index <= f64.index) {
      return true;
    }
    return false;
  }

  bool get isInt {
    if (index >= i8.index && index < kBool.index) {
      return true;
    }
    return false;
  }

  bool get isNum => isInt || isFp;

  LitKind get convert {
    if (index >= u8.index && index <= usize.index) {
      final diff = index - u8.index;
      return values[i8.index + diff];
    }
    if (this == kFloat) {
      return f32;
    } else if (this == kDouble) {
      return f64;
    }
    return this;
  }

  bool get signed {
    if (index >= i8.index && index <= isize.index || this == kInt) {
      return true;
    }
    return false;
  }

  final String lit;
  const LitKind(this.lit);

  static LitKind? from(LiteralKind kind) {
    return values.firstWhereOrNull((element) => element.lit == kind.lit);
  }

  BuiltInTy get ty => BuiltInTy.get(this);
}

class Block extends BuildMixin with EquatableMixin {
  Block(this._innerStmts, this.ident, this.blockStart, this.blockEnd) {
    _init();
    final fnStmt = <Fn>[];
    final others = <Stmt>[];
    final tyStmts = <Stmt>[];
    final implStmts = <Stmt>[];
    final aliasStmts = <Stmt>[];
    final importStmts = <Stmt>[];
    // 函数声明前置
    for (var stmt in _innerStmts) {
      if (stmt is TyStmt) {
        final ty = stmt.ty;
        switch (ty) {
          case Fn ty:
            fnStmt.add(ty);
          case ImplTy _:
            implStmts.add(stmt);
          case TypeAliasTy _:
            aliasStmts.add(stmt);
          case _:
            tyStmts.add(stmt);
        }

        continue;
      } else if (stmt case ExprStmt(expr: ImportExpr())) {
        importStmts.add(stmt);
        continue;
      }
      others.add(stmt);
    }
    _fnExprs = fnStmt;
    _stmts = others;
    _tyStmts = tyStmts;
    _implTyStmts = implStmts;
    _aliasStmts = aliasStmts;
    _importStmts = importStmts;
  }

  Block._(this._innerStmts, this.ident, this.blockStart, this.blockEnd);

  void _init() {
    // {
    //   stmt
    // }
    for (var s in _innerStmts) {
      s.incLevel();
    }
  }

  final Identifier? ident;
  final List<Stmt> _innerStmts;

  late List<Fn> _fnExprs;
  late List<Stmt> _stmts;
  late List<Stmt> _tyStmts;
  late List<Stmt> _implTyStmts;
  late List<Stmt> _aliasStmts;
  late List<Stmt> _importStmts;
  final Identifier blockStart;
  final Identifier blockEnd;

  bool get isNotEmpty => _stmts.isNotEmpty;

  Stmt? get lastOrNull => _stmts.lastOrNull;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);

    for (var s in _innerStmts) {
      s.incLevel(count);
    }
  }

  Block clone() {
    return Block._(_innerStmts, ident, blockStart, blockEnd)
      .._fnExprs = _fnExprs.map((e) => e.clone()).toList()
      .._stmts = _stmts.map((e) => e.clone()).toList()
      .._implTyStmts = _implTyStmts.map((e) => e.clone()).toList()
      .._aliasStmts = _aliasStmts.map((e) => e.clone()).toList()
      .._importStmts = _importStmts.map((e) => e.clone()).toList()
      .._tyStmts = _tyStmts.map((e) => e.clone()).toList();
  }

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = _innerStmts.map((e) => '$e\n').join();
    return '${ident ?? ''} {\n$s$p}';
  }

  void build(FnBuildMixin context, {bool hasRet = false}) {
    for (var stmt in _importStmts) {
      stmt.build(context, false);
    }

    for (var fn in _fnExprs) {
      fn.currentContext = context;
      fn.build();
    }

    for (var ty in _tyStmts) {
      ty.build(context, false);
    }

    for (var alias in _aliasStmts) {
      alias.build(context, false);
    }

    for (var implTy in _implTyStmts) {
      implTy.build(context, false);
    }

    if (!hasRet) {
      for (var stmt in _stmts) {
        stmt.build(context, false);
      }
    } else {
      final length = _stmts.length;
      final max = length - 1;

      // 先处理普通语句，在内部函数中可能会引用到变量等
      for (var i = 0; i < length; i++) {
        final stmt = _stmts[i];
        stmt.build(context, i == max);
      }
    }
  }

  @override
  List<Object?> get props => [_innerStmts];

  @override
  void analysis(AnalysisContext context) {
    for (var stmt in _importStmts) {
      stmt.analysis(context);
    }

    for (var fn in _fnExprs) {
      context.pushFn(fn.fnName, fn);
    }

    for (var ty in _tyStmts) {
      ty.analysis(context);
    }

    for (var alais in _aliasStmts) {
      alais.analysis(context);
    }

    for (var implTy in _implTyStmts) {
      implTy.analysis(context);
    }

    for (var stmt in _stmts) {
      stmt.analysis(context);
    }

    for (var fn in _fnExprs) {
      fn.analysis(context);
    }
  }
}

// 函数声明
class FnDecl with EquatableMixin {
  FnDecl(this.ident, this.params, this.generics, this.returnTy, this.isVar);
  final Identifier ident;

  FnDecl copywith(List<FieldDef> params) {
    return FnDecl(ident, params, generics, returnTy, isVar);
  }

  final List<FieldDef> params;
  final List<GenericDef> generics;

  final PathTy returnTy;
  final bool isVar;

  @override
  String toString() {
    final isVals = isVar ? ', ...' : '';
    final g = generics.isNotEmpty ? '<${generics.join(',')}>' : '';
    return '$ident$g(${params.join(',')}$isVals) -> $returnTy';
  }

  @override
  List<Object?> get props => [ident, params, returnTy];

  void analysis(AnalysisContext context, Fn fn) {
    for (var p in params) {
      final t = fn.getFieldTy(context, p);
      context.pushVariable(
        context.createVal(t, p.ident, p.rawTy.kind)..lifecycle.isOut = true,
      );
    }
  }
}

// 函数签名
class FnSign with EquatableMixin {
  FnSign(this.extern, this.fnDecl);
  final FnDecl fnDecl;
  // header
  final bool extern;

  Identifier get ident => fnDecl.ident;

  @override
  String toString() {
    return fnDecl.toString();
  }

  void analysis(AnalysisContext context, Fn fn) {
    fnDecl.analysis(context, fn);
  }

  @override
  List<Object?> get props => [fnDecl, extern];
}

/// ----- Ty -----

abstract class Ty extends BuildMixin with EquatableMixin implements Clone<Ty> {
  static final PathTy unknown = UnknownTy(Identifier.none);

  bool isTy(Ty? other) {
    return this == other;
  }

  LLVMType get llty;

  Identifier get ident;

  List<ComponentTy> _constraints = const [];
  List<ComponentTy> get constraints => _constraints;

  Ty newConstraints(Tys c, List<ComponentTy> newConstraints) {
    return clone()
      .._constraints = newConstraints
      .._buildContext = _buildContext;
  }

  LLVMTypeRef typeOf(StoreLoadMixin c) => llty.typeOf(c);

  bool extern = false;
  FnBuildMixin? _buildContext;
  // ignore: unnecessary_getters_setters
  FnBuildMixin? get currentContext => _buildContext;

  set currentContext(FnBuildMixin? context) {
    _buildContext = context;
  }

  void build() {}
}

class RefTy extends Ty {
  RefTy(this.parent)
      : isPointer = false,
        ident = Identifier.builtIn('&');
  RefTy.pointer(this.parent)
      : isPointer = true,
        ident = Identifier.builtIn('*');
  RefTy.from(this.parent, this.isPointer)
      : ident = Identifier.builtIn(isPointer ? '*' : '&');

  final bool isPointer;
  final Ty parent;

  @override
  final Identifier ident;

  Ty get baseTy {
    return switch (parent) {
      RefTy p => p.baseTy,
      _ => parent,
    };
  }

  @override
  RefTy clone() {
    return RefTy.from(parent.clone(), isPointer);
  }

  @override
  void analysis(AnalysisContext context) {}

  @override
  LLVMRefType get llty => LLVMRefType(this);

  @override
  List<Object?> get props => [parent, _constraints];

  @override
  String toString() {
    return 'RefTy($parent)';
  }
}

class BuiltInTy extends Ty {
  static final i8 = LitKind.i8.ty;
  static final u8 = LitKind.u8.ty;
  static final i32 = LitKind.i32.ty;
  static final i64 = LitKind.i64.ty;
  static final f32 = LitKind.f32.ty;
  static final f64 = LitKind.f64.ty;
  static final kVoid = LitKind.kVoid.ty;
  static final kBool = LitKind.kBool.ty;
  static final usize = LitKind.usize.ty;

  static final _instances = <LitKind, BuiltInTy>{};

  factory BuiltInTy.get(LitKind lit) {
    if (lit == LitKind.kFloat) {
      lit = LitKind.f32;
    } else if (lit == LitKind.kDouble) {
      lit = LitKind.f64;
    }
    return _instances.putIfAbsent(lit, () {
      return BuiltInTy._lit(lit);
    });
  }

  BuiltInTy._lit(this._ty);

  final LitKind _ty;
  LitKind get ty => _ty;

  Identifier? _ident;
  @override
  Identifier get ident => _ident ??= Identifier.builtIn(_ty.name);

  @override
  bool isTy(Ty? other) {
    if (other is BuiltInTy) {
      return other._ty == _ty;
    }
    return super.isTy(other);
  }

  static BuiltInTy? from(String src) {
    final lit = LitKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy.get(lit);
  }

  @override
  BuiltInTy clone() {
    return BuiltInTy._lit(_ty);
  }

  @override
  String toString() {
    return '${_ty.lit}${constraints.constraints}';
  }

  @override
  List<Object?> get props => [_ty, _constraints];

  @override
  LLVMTypeLit get llty => LLVMTypeLit(this);

  @override
  @override
  void analysis(AnalysisContext context) {}
}

/// [PathTy] 只用于声明
class PathTy with EquatableMixin {
  PathTy(this.ident, this.genericInsts, [this.kind = const []]) : ty = null;
  PathTy.ty(Ty this.ty, [this.kind = const []])
      : ident = Identifier.none,
        genericInsts = const [];
  final Identifier ident;
  final Ty? ty;
  final List<PointerKind> kind;

  final List<PathTy> genericInsts;

  bool get isRef => kind.isRef;

  @override
  String toString() {
    if (ty != null) return ty!.toString();
    return '${kind.join('')}$ident${genericInsts.str}';
  }

  @override
  List<Object?> get props => [ident];

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    var tempTy =
        ty ?? BuiltInTy.from(ident.src) ?? c.getTy(ident) ?? gen?.call(ident);

    if (tempTy is NewInst && !tempTy.done) {
      final types = NewInst.getTysFromGenericInsts(
          c, genericInsts, tempTy.generics,
          gen: gen);

      tempTy = tempTy.newInst(types, c);
    } else if (tempTy is TypeAliasTy) {
      tempTy = tempTy.getTy(c, genericInsts, gen: gen);
    }

    if (tempTy == null) return null;

    return kind.wrapRefTy(tempTy);
  }

  Ty grt(Tys c, {GenTy? gen}) {
    return grtOrT(c, gen: gen)!;
  }

  Ty? getBaseTy(Tys c) {
    return ty ?? BuiltInTy.from(ident.src) ?? c.getTy(ident);
  }
}

class ArrayPathTy extends PathTy {
  ArrayPathTy(this.elementTy, Identifier ident, List<PointerKind> kinds)
      : super(ident, const [], kinds);
  final PathTy elementTy;

  @override
  Ty? grtOrT(Tys c, {GenTy? gen}) {
    final e = elementTy.grtOrT(c, gen: gen);
    if (e == null) return null;

    final array = ArrayTy(e, LLVMRawValue(ident).iValue);
    return kind.wrapRefTy(array);
  }

  @override
  String toString() {
    return '[$elementTy; $ident]';
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

  FnTy copyWith(Set<AnalysisVariable> extra) {
    final rawDecl = fnSign.fnDecl;
    final cache = rawDecl.params.toList();
    for (var e in extra) {
      cache.add(FieldDef(e.ident, PathTy.ty(e.ty, [PointerKind.ref])));
    }
    final decl = FnDecl(rawDecl.ident, cache, rawDecl.generics,
        rawDecl.returnTy, rawDecl.isVar);
    return FnTy(decl)
      ..copy(this)
      .._constraints = _constraints;
  }

  @override
  Fn clone() {
    return FnTy(fnSign.fnDecl)..copy(this);
  }

  @override
  LLVMConstVariable? build(
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    return null;
  }
}

class Fn extends Ty with NewInst<Fn> {
  Fn(this.fnSign, this.block);

  Identifier get fnName => fnSign.fnDecl.ident;

  @override
  Identifier get ident => fnName;

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

    var ext = '';
    if (extern) {
      ext = 'extern ';
    }

    return '$pad${ext}fn $fnSign$b${tys.str}';
  }

  @override
  List<Object?> get props => [fnSign, block, _tys, _constraints];

  Ty getRetTy(Tys c) {
    return getRetTyOrT(c)!;
  }

  Ty? getRetTyOrT(Tys c) {
    return fnSign.fnDecl.returnTy.grtOrT(c, gen: (ident) {
      return getTy(c, ident);
    });
  }

  @override
  Fn clone() {
    return Fn(fnSign, block)..copy(this);
  }

  final _cache = <ListKey, LLVMConstVariable>{};

  @override
  void build() {
    final context = currentContext;
    assert(context != null);
    if (context == null) return;
    context.pushFn(fnName, this);
  }

  void copy(Fn from) {
    _parent = from.parentOrCurrent;
    selfVariables = from.selfVariables;
    _get = from._get;
    currentContext = from.currentContext;
  }

  LLVMConstVariable? genFn([
    Set<AnalysisVariable>? variables,
    Map<Identifier, Set<AnalysisVariable>>? map,
  ]) {
    final context = currentContext;
    assert(context != null);
    if (context == null) return null;
    return _customBuild(context, variables, map);
  }

  LLVMConstVariable? _customBuild(FnBuildMixin context,
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    final vk = [];

    final k = getKey();
    if (k != null) {
      vk.add(k);
    }

    if (variables != null && variables.isNotEmpty) {
      vk.add(variables.toList());
    }
    for (var v in selfVariables) {
      final vt = v.ty;
      vk.add(vt);
      if (vt is StructTy) {
        vk.add(vt.tys);
      }
    }
    final key = ListKey(vk);

    return parentOrCurrent._cache.putIfAbsent(key, () {
      return context.buildFnBB(
          this, variables, map ?? const {}, pushTyGenerics);
    });
  }

  void pushTyGenerics(Tys context) {
    context.pushDyTys(tys);
  }

  Object? getKey() {
    return null;
  }

  Set<AnalysisVariable> selfVariables = {};
  Set<AnalysisVariable> get variables {
    final v = _get?.call();
    if (v == null) return selfVariables;
    return {...selfVariables, ...v};
  }

  Set<AnalysisVariable> Function()? _get;

  Set<RawIdent> returnVariables = {};

  bool _anaysised = false;

  void analysisContext(AnalysisContext context) {}
  @override
  void analysis(AnalysisContext context) {
    if (_anaysised) return;
    _anaysised = true;
    if (context.getFn(fnName) == null) context.pushFn(fnName, this);
    if (generics.isNotEmpty && tys.isEmpty) {
      return;
    }

    final child = context.childContext();
    pushTyGenerics(child);

    child.setFnContext(this);
    fnSign.fnDecl.analysis(child, this);
    analysisContext(child);
    block?.analysis(child);
    selfVariables = child.catchVariables;
    _get = () => child.childrenVariables;

    final lastStmt = block?._stmts.lastOrNull;

    if (lastStmt is ExprStmt) RetExpr.analysisAll(child, lastStmt.expr);
  }

  @override
  late final LLVMFnType llty = LLVMFnType(this);

  @override
  List<FieldDef> get fields => fnSign.fnDecl.params;
  @override
  List<GenericDef> get generics => fnSign.fnDecl.generics;

  @override
  Fn newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return Fn(s, block)..copy(this);
  }
}

mixin ImplFnMixin on Fn {
  Ty get ty;
  ImplTy get implty;

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ?? implty.currentContext;

  @override
  ImplFnMixin newTy(List<FieldDef> fields);

  @override
  void pushTyGenerics(Tys context) {
    super.pushTyGenerics(context);
    _pushSelf(context);
  }

  void _pushSelf(Tys context) {
    final structTy = ty;
    final ident = Identifier.builtIn('Self');
    context.pushDyTy(ident, structTy);

    if (structTy is! StructTy) return;
    context.pushDyTys(structTy.tys);
  }

  @override
  Object? getKey() {
    if (ty is StructTy) {
      return (ty as StructTy).tys;
    }
    return null;
  }

  @override
  Ty? getTy(Tys c, Identifier ident) {
    final tempTy = super.getTy(c, ident);
    if (tempTy != null) {
      return tempTy;
    }

    final ty = this.ty;
    if (ident.src == 'Self') {
      return ty;
    }

    if (ty is! StructTy) return null;

    return ty.tys[ident];
  }

  @override
  List<Object?> get props => [ty, implty, _constraints];
}

class ImplFn extends Fn with ImplFnMixin {
  ImplFn(super.fnSign, super.block, this.ty, this.implty);
  @override
  final Ty ty;
  @override
  final ImplTy implty;

  @override
  ImplFnMixin newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return ImplFn(s, block, ty, implty)..copy(this);
  }

  ImplFn cloneWith(Ty ty, ImplTy other) {
    return ImplFn(fnSign, block, ty, other)..copy(this);
  }

  @override
  void analysisContext(AnalysisContext context) {
    final ident = Identifier.self;
    final v = context.createVal(ty, ident);
    v.lifecycle.isOut = true;
    context.pushVariable(v);
  }
}

class ImplStaticFn extends Fn with ImplFnMixin {
  ImplStaticFn(super.fnSign, super.block, this.ty, this.implty);
  @override
  final Ty ty;
  @override
  final ImplTy implty;

  @override
  ImplFnMixin newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return ImplStaticFn(s, block, ty, implty)..copy(this);
  }

  ImplStaticFn cloneWith(Ty ty, ImplTy other) {
    return ImplStaticFn(fnSign, block, ty, other)..copy(this);
  }
}

class GenericDef with EquatableMixin {
  GenericDef(this.ident, this.constraints);
  final Identifier ident;
  final List<PathTy> constraints;

  List<Ty> getConstraints(Tys c, {GenTy? gen}) {
    final list = <Ty>[];
    for (var pathTy in constraints) {
      final ty = pathTy.grtOrT(c, gen: gen);
      if (ty != null) {
        list.add(ty);
      }
    }

    return list;
  }

  @override
  String toString() {
    if (constraints.isEmpty) {
      return ident.src;
    }

    return '$ident: ${constraints.join(' + ')}';
  }

  @override
  List<Object?> get props => [constraints, ident];
}

/// 字段定义
///
/// 函数，结构体的字段格式
class FieldDef with EquatableMixin implements Clone<FieldDef> {
  FieldDef(this.ident, this._ty) : _rty = null;
  FieldDef._internal(this.ident, this._ty, this._rty);
  final Identifier ident;
  final PathTy _ty;
  PathTy get rawTy => _ty;
  final Ty? _rty;
  Ty? _cache;

  Ty grt(Tys c) => grtOrT(c)!;

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    return _rty ?? (_cache ??= _ty.grtOrT(c, gen: gen));
  }

  @override
  FieldDef clone() {
    return FieldDef._internal(ident, _ty, _rty);
  }

  List<PointerKind> get kinds => _ty.kind;
  @override
  String toString() {
    if (!ident.isValid) {
      return '$_ty';
    }
    return '$ident: $_ty';
  }

  bool? _isRef;
  bool get isRef => _isRef ??= kinds.isRef;

  @override
  List<Object?> get props => [_rty, _ty, ident];
}

typedef GenTy = Ty? Function(Identifier ident);

mixin NewInst<T extends Ty> on Ty {
  List<FieldDef> get fields;
  List<GenericDef> get generics;

  Map<Identifier, Ty>? _tys;

  Map<Identifier, Ty> get tys => _tys ?? const {};

  bool get done => tys.length == generics.length;

  final _tyLists = <ListKey, T>{};

  T? _parent;
  T get parentOrCurrent => _parent ?? this as T;

  @override
  FnBuildMixin? get currentContext =>
      super.currentContext ??= _parent?.currentContext;

  @override
  bool isTy(Ty? other) {
    if (other is NewInst) {
      return other.parentOrCurrent == parentOrCurrent;
    }
    return super.isTy(other);
  }

  @override
  Ty newConstraints(Tys c, List<ComponentTy> newConstraints) {
    final ty = (clone() as NewInst)
      .._constraints = newConstraints
      .._buildContext = _buildContext;
    ty._initData(c, parentOrCurrent, tys);
    return ty;
  }

  int getScore(NewInst other) {
    if (parentOrCurrent != other.parentOrCurrent) return -1;

    for (var MapEntry(:key, :value) in tys.entries) {
      final pv = other.tys[key];
      if (pv != null && pv != value) {
        return -1;
      }
    }

    return tys.length - other.tys.length;
  }

  _initData(Tys c, T? parent, Map<Identifier, Ty> tys) {
    _parent = parent;
    _tys = tys;

    // init ty
    for (var fd in fields) {
      getFiledTyOrT(c, fd);
    }
  }

  /// todo: 使用 `context.pushDyty` 实现
  T newInst(Map<Identifier, Ty> tys, Tys c) {
    final parent = parentOrCurrent;
    if (tys.isEmpty) return parent;
    final key = ListKey(tys);

    final newInst = (parent as NewInst)._tyLists.putIfAbsent(key, () {
      final newFields = fields.map((e) => e.clone()).toList();

      final ty = newTy(newFields);
      ty._buildContext = currentContext;
      (ty as NewInst)._initData(c, parentOrCurrent, tys);
      return ty;
    });

    return newInst as T;
  }

  /// 从泛型实体获取map
  ///
  /// struct Box<S,T> {
  ///  ...
  /// }
  ///
  /// fn main() {
  ///   let box = Box<i32, i64>{ ... };
  /// }
  ///
  /// generics    : <S  , T  >
  ///
  /// genericInsts: <i32, i64>
  ///
  ///  => map: {S: i32, T: i64 }
  static Map<Identifier, Ty> getTysFromGenericInsts(
    Tys c,
    List<PathTy> genericInsts,
    List<GenericDef> generics, {
    Ty? Function(Identifier ident)? gen,
  }) {
    final types = <Identifier, Ty>{};

    if (genericInsts.length != genericInsts.length) return types;

    for (var i = 0; i < genericInsts.length; i += 1) {
      final pathTy = genericInsts[i];
      final generic = generics[i];
      final gty = pathTy.grtOrT(c, gen: gen);
      if (gty != null) {
        types[generic.ident] = gty;
      }
    }

    return types;
  }

  T newInstWithGenerics(
      Tys c, List<PathTy> genericInsts, List<GenericDef> generics,
      {GenTy? gen}) {
    final types = getTysFromGenericInsts(c, genericInsts, generics, gen: gen);

    return newInst(types, c);
  }

  static bool resolve(Tys c, Ty exactTy, PathTy pathTy,
      List<GenericDef> generics, Map<Identifier, Ty> genMapTy) {
    bool result = true;
    // x: Arc<Gen<T>> => first fdTy => Arc<Gen<T>>
    // child fdTy:  Gen<T> => T => real type
    //
    // fn hello<T>(y: T);
    //
    // hello(y: 1000);
    // ==> exactTy: i32; fieldTy: T
    //
    // fn foo<T>(x: Gen<T>);
    //
    // foo(x: Gen<i32> { foo: 1000 } );
    // ==> exactTy: Gen<i32>; fieldTy: Gen<T>
    void visitor(Ty exactTy, PathTy pathTy) {
      ComponentTy? checkTy(Ty exactTy, PathTy pathTy) {
        ComponentTy? tyConstraint;

        final tryTy = c.runIgnoreImport(() => pathTy.getBaseTy(c));
        var generics = const <GenericDef>[];
        var tys = const <Identifier, Ty>{};

        if (tryTy is TypeAliasTy) {
          final alias = tryTy.aliasTy;

          // 从[TypeAlaisTy] 中获取基本类型
          final newMap = <Identifier, Ty>{};
          result = resolve(c, exactTy, alias, tryTy.generics, newMap);
          if (!result) return null;
          assert(newMap.length == pathTy.genericInsts.length);
          generics = tryTy.generics;
          tys = newMap;
        } else if (exactTy is NewInst) {
          generics = exactTy.generics;
          tys = exactTy.tys;

          if (tryTy is! NewInst ||
              tryTy.parentOrCurrent != exactTy.parentOrCurrent) {
            result = false;
            return null;
          }
        } else if (tryTy is ComponentTy) {
          /// exactTy不支持泛型如: i32 , i64 ...
          final currentImplTy =
              c.runIgnoreImport(() => c.getImplWith(exactTy, comTy: tryTy));
          final com = currentImplTy?.comTy;

          if (com?.parentOrCurrent != tryTy.parentOrCurrent) {
            result = false;
            return null;
          }
          tyConstraint = com;

          generics = com!.generics;
          tys = com.tys;
        }

        /// 除了[TypeAliasTy]泛型个数必须一致
        if (pathTy.genericInsts.length != generics.length) {
          result = false;
          return null;
        }

        for (var i = 0; i < pathTy.genericInsts.length; i += 1) {
          final genericInst = pathTy.genericInsts[i];
          final ty = tys[generics[i].ident];
          if (ty != null) visitor(ty, genericInst);
        }

        return tyConstraint;
      }

      exactTy = pathTy.kind.unWrapRefTy(exactTy);

      final currentGenField =
          generics.firstWhereOrNull((e) => e.ident == pathTy.ident);
      if (currentGenField != null) {
        // fn bar<T, X: Bar<T>>(x: X);
        // 处理泛型内部依赖，X已知晓，处理T

        genMapTy.putIfAbsent(pathTy.ident, () {
          final list = <ComponentTy>[];
          for (var g in currentGenField.constraints) {
            final com = checkTy(exactTy, g);
            if (com != null) {
              list.add(com);
            }
          }

          return exactTy.newConstraints(c, list);
        });
      }

      if (genMapTy.length == generics.length) {
        return;
      }

      // Gen<i32> : Gen<T>
      // 泛型在下一级中
      checkTy(exactTy, pathTy);
    }

    visitor(exactTy, pathTy);

    return result;
  }

  T resolveGeneric(Tys context, List<FieldExpr> params,
      {List<GenericDef> others = const []}) {
    final generics = [...this.generics, ...others];

    if (tys.length >= generics.length) return this as T;

    final genMapTy = <Identifier, Ty>{};

    final sortFields =
        alignParam(params, (p) => fields.indexWhere((e) => e.ident == p.ident));

    bool isBuild = context is FnBuildMixin;

    Ty? gen(Identifier ident) {
      return genMapTy[ident] ?? tys[ident];
    }

    for (var i = 0; i < sortFields.length; i += 1) {
      final f = sortFields[i];
      final fd = fields[i];

      Ty? ty;
      if (isBuild) {
        ty = f.build(context, baseTy: fd.grtOrT(context, gen: gen))?.ty;
      } else {
        // fd.grtOrT(context, gen: gen)
        ty = f.analysis(context as AnalysisContext)?.ty;
      }
      if (ty != null) {
        resolve(context, ty, fd.rawTy, generics, genMapTy);
      }
    }

    return newInst(genMapTy, context);
  }

  @protected
  T newTy(List<FieldDef> fields);

  /// 从[ident] 获取[Ty]
  ///
  /// 不直接调用;
  ///
  /// 一般[fields]中的泛型都在[generics]中，
  /// 不过静态函数[ImplStaticFn]可能来源于[StructTy]结构体
  ///
  /// [ImplFnMixin.getTy]
  @mustCallSuper
  Ty? getTy(Tys c, Identifier ident) {
    return tys[ident];
  }

  Ty getFieldTy(Tys c, FieldDef fd) {
    return getFiledTyOrT(c, fd)!;
  }

  Ty? getFiledTyOrT(Tys c, FieldDef fd) {
    return fd.grtOrT(c, gen: (ident) {
      return getTy(c, ident);
    });
  }
}

class StructTy extends Ty with EquatableMixin, NewInst<StructTy> {
  StructTy(this.ident, this.fields, this.generics);
  @override
  final Identifier ident;
  @override
  final List<FieldDef> fields;

  @override
  final List<GenericDef> generics;

  @override
  StructTy newTy(List<FieldDef> fields) {
    return StructTy(ident, fields, generics);
  }

  @override
  StructTy clone() {
    return StructTy(ident, fields.clone(), generics);
  }

  @override
  String toString() {
    var ext = '';
    if (extern) {
      ext = '$extern ';
    }

    return '$pad${ext}struct $ident${generics.str} {${fields.join(',')}}${tys.str} ${constraints.constraints}';
  }

  @override
  List<Object?> get props => [ident, fields, _tys, _constraints];

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushStruct(ident, this);
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushStruct(ident, this);
  }

  @override
  late final LLVMStructType llty = LLVMStructType(this);
}

class UnionTy extends StructTy {
  UnionTy(super.ident, super.fields, super.generics);
}

class EnumTy extends Ty with NewInst<EnumTy> {
  EnumTy(this.ident, this.variants, this.generics) {
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      v.parent = this;
      v._index = i;
    }
  }
  @override
  final Identifier ident;
  final List<EnumItem> variants;

  @override
  EnumTy clone() {
    return EnumTy(ident, variants.clone(), generics);
  }

  @override
  String toString() {
    return 'enum $ident${generics.str} {${variants.join(',')}}${tys.str}';
  }

  @override
  List<Object?> get props => [ident, variants, _constraints];

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.currentContext ??= context;
      v.build();
    }
  }

  @override
  late LLVMEnumType llty = LLVMEnumType(this);

  @override
  void analysis(AnalysisContext context) {
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.analysis(context);
    }
  }

  List<FieldDef>? _fields;
  @override
  List<FieldDef> get fields {
    if (_fields != null) return _fields!;
    final fields = <FieldDef>[];
    for (var item in variants) {
      fields.addAll(item.fields);
    }

    return _fields = fields;
  }

  @override
  final List<GenericDef> generics;

  @override
  EnumTy newTy(List<FieldDef> fields) {
    var index = 0;

    final newVarints = <EnumItem>[];
    for (var item in variants) {
      final end = index + item.fields.length;
      final itemFields = fields.sublist(index, end);
      newVarints.add(EnumItem(item.ident, itemFields, item.generics));
      index = end;
    }

    return EnumTy(ident, newVarints, generics);
  }
}

extension<S, T extends Clone<S>> on List<T> {
  List<T> clone() {
    return List.from(map((e) {
      return e.clone();
    }));
  }
}

/// 与 `struct` 类似
class EnumItem extends StructTy {
  EnumItem(super.ident, super.fields, super.generics);
  late EnumTy parent;
  late int _index;

  @override
  String toString() {
    final fy = fields.isEmpty ? '' : '(${fields.join(', ')})';

    return '$ident$fy${parent.tys.str}';
  }

  @override
  EnumItem clone() {
    return EnumItem(ident, fields.clone(), generics);
  }

  @override
  EnumItem newTy(List<FieldDef> fields) {
    throw "use EnumTy.newTy";
  }

  @override
  List<GenericDef> get generics => parent.generics;

  @override
  Map<Identifier, Ty> get tys => parent.tys;

  @override
  EnumItem newInst(Map<Identifier, Ty> tys, Tys<LifeCycleVariable> c) {
    final enumTy = parent.newInst(tys, c);
    return enumTy.variants.firstWhere((e) => e._index == _index);
  }

  @override
  Ty? getTy(Tys<LifeCycleVariable> c, Identifier ident) {
    final tempTy = super.getTy(c, ident);
    if (tempTy != null) return tempTy;
    return parent.getTy(c, ident);
  }

  @override
  // ignore: overridden_fields
  late final LLVMEnumItemType llty = LLVMEnumItemType(this);
}

class ComponentTy extends Ty with NewInst<ComponentTy> {
  ComponentTy(this.ident, this.fns, this.generics);

  @override
  final Identifier ident;
  @override
  final List<GenericDef> generics;
  final List<FnSign> fns;

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushComponent(ident, this);
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushComponent(ident, this);
  }

  @override
  ComponentTy clone() {
    return ComponentTy(ident, fns, generics);
  }

  @override
  String toString() {
    final pddd = getWhiteSpace(level + 1, BuildMixin.padSize);

    return 'com $ident${generics.str} {\n$pddd${fns.join('\n$pddd')}\n$pad}${tys.str}';
  }

  @override
  List<Object?> get props => [ident, fns, _tys, _constraints];

  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  List<FieldDef> get fields => const [];

  @override
  ComponentTy newTy(List<FieldDef> fields) {
    return ComponentTy(ident, fns, generics);
  }
}

class ImplTy extends Ty with NewInst<ImplTy> {
  ImplTy(this.generics, this.com, this.struct, this.label, this.fns,
      this.staticFns) {
    for (var fn in fns) {
      fn.incLevel();
    }
    for (var fn in staticFns) {
      fn.incLevel();
    }
  }
  final PathTy struct;
  final PathTy? com;
  final PathTy? label;
  final List<Fn> fns;
  final List<Fn> staticFns;

  @override
  final List<GenericDef> generics;

  @override
  List<FieldDef> get fields => const [];
  @override
  ImplTy newTy(List<FieldDef> fields) {
    return ImplTy(generics, com, struct, label, fns, staticFns);
  }

  @override
  ImplTy clone() {
    return this;
  }

  @override
  Identifier get ident => label?.ident ?? com?.ident ?? struct.ident;

  bool contains(Identifier ident) {
    return fns.any((e) => e.fnSign.fnDecl.ident == ident) ||
        staticFns.any((e) => e.fnSign.fnDecl.ident == ident);
  }

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

  ImplFnMixin? getFn(Identifier ident) {
    return _fns?.firstWhereOrNull((e) => e.fnSign.fnDecl.ident == ident) ??
        _staticFns?.firstWhereOrNull((e) => e.fnSign.fnDecl.ident == ident);
  }

  List<ImplFn>? _fns;

  List<ImplStaticFn>? _staticFns;

  Ty? _ty;
  Ty? get ty => _ty;

  ComponentTy? _componentTy;
  ComponentTy? get comTy => _componentTy;

  Map<Identifier, GenericDef>? _map;

  GenericDef? getGeneric(Identifier ident) {
    var map = _map;
    if (map == null) {
      map = {};
      for (var generic in generics) {
        map[generic.ident] = generic;
      }
      _map = map;
    }

    return map[ident];
  }

  final _implTyList = <Ty, ImplTy>{};

  ImplTy? compareStruct(Tys c, Ty exactTy, Ty? comTy) {
    if (generics.isEmpty) {
      if (comTy == null || comTy.isTy(this.comTy)) {
        return this;
      }
      return null;
    }

    var cache = parentOrCurrent._implTyList[exactTy];
    if (cache == null) {
      final genMap = <Identifier, Ty>{};
      final result = NewInst.resolve(c, exactTy, struct, generics, genMap);
      if (!result) return null;

      final impl = newInst(genMap, c).._initTys(c);
      parentOrCurrent._implTyList[exactTy] = impl;
      cache = impl;
    }

    if (comTy == null || comTy.isTy(cache.comTy)) {
      return cache;
    }

    return null;
  }

  bool _init = false;
  void _initTys(Tys c) {
    if (_init) return;
    _init = true;
    _initC(c);
  }

  void _initC(Tys context) {
    final comTy = com?.grtOrT(context, gen: (ident) => tys[ident]);

    assert(comTy == null ||
        comTy is ComponentTy ||
        Log.e('${com?.ident} is not Com\n$comTy\n$comTy'));

    if (comTy is ComponentTy) {
      _componentTy = comTy;
    }

    final ty = struct.grtOrT(context, gen: (ident) => tys[ident]);
    if (ty == null) {
      context.pushImplTy(this);
      return;
    }
    _ty = ty;

    context.pushImplForStruct(ty, this);
    final parent = parentOrCurrent;
    final pfns = parent._fns;
    final pstaticFns = parent._staticFns;

    if (pfns != null && pstaticFns != null) {
      _fns ??= pfns.map((e) => e.cloneWith(ty, this)).toList();
      _staticFns ??= pstaticFns.map((e) => e.cloneWith(ty, this)).toList();
      return;
    }

    _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty, this)).toList();
    _staticFns ??= staticFns
        .map((e) => ImplStaticFn(e.fnSign, e.block, ty, this))
        .toList();
  }

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    _initTys(context);
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

    return 'impl${generics.str} $cc$struct {\n$pad$sfnn$fnnStr$pad}${tys.str}';
  }

  @override
  List<Object?> get props => [struct, staticFns, fns, label, _constraints];

  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  void analysis(AnalysisContext context) {
    _initC(context);
  }
}

class ArrayTy extends Ty {
  ArrayTy(this.elementTy, this.size);
  final Ty elementTy;
  final int size;

  Identifier? _ident;
  @override
  Identifier get ident => _ident ??= Identifier.builtIn('[$size; $elementTy]');

  @override
  void analysis(AnalysisContext context) {}

  @override
  ArrayTy clone() {
    return ArrayTy(elementTy.clone(), size);
  }

  @override
  late final ArrayLLVMType llty = ArrayLLVMType(this);

  @override
  List<Object?> get props => [elementTy, _constraints];
}

class ArrayLLVMType extends LLVMType {
  ArrayLLVMType(this.ty);

  @override
  final ArrayTy ty;
  @override
  LLVMTypeRef typeOf(StoreLoadMixin c) {
    return c.arrayType(ty.elementTy.typeOf(c), ty.size);
  }

  @override
  int getBytes(StoreLoadMixin c) {
    return c.typeSize(typeOf(c));
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

  Variable getElement(
      StoreLoadMixin c, Variable value, LLVMValueRef index, Identifier id) {
    final indics = <LLVMValueRef>[index];

    final elementTy = ty.elementTy.typeOf(c);

    final vv = LLVMAllocaVariable.delay(() {
      c.diSetCurrentLoc(id.offset);
      final p = value.getBaseValue(c);
      return llvm.LLVMBuildInBoundsGEP2(
          c.builder, elementTy, p, indics.toNative(), indics.length, unname);
    }, ty.elementTy, elementTy, id);

    return vv;
  }

  Variable toStr(StoreLoadMixin c, Variable value) {
    return LLVMConstVariable(
        value.getBaseValue(c), LitKind.kStr.ty, Identifier.none);
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

class TypeAliasTy extends Ty {
  TypeAliasTy(this.ident, this.generics, this.aliasTy);
  @override
  final Identifier ident;

  final List<GenericDef> generics;
  final PathTy aliasTy;

  @override
  TypeAliasTy clone() {
    return TypeAliasTy(ident, generics, aliasTy);
  }

  Ty? grt(Tys c, {GenTy? gen}) {
    return aliasTy.grtOrT(c, gen: gen);
  }

  T? getTy<T extends Ty>(Tys c, List<PathTy> genericInsts, {GenTy? gen}) {
    final map =
        NewInst.getTysFromGenericInsts(c, genericInsts, generics, gen: gen);

    final t = grt(c, gen: (ident) {
      return map[ident];
    });

    if (t is! T) return null;

    return t;
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushAliasTy(ident, this);
  }

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushAliasTy(ident, this);
  }

  @override
  late final LLVMAliasType llty = LLVMAliasType(this);

  @override
  List<Object?> get props => [ident, generics, aliasTy, _constraints];

  @override
  String toString() {
    return 'type $ident${generics.str} = $aliasTy';
  }
}

extension ListStr<T> on List<T> {
  String get str {
    if (isEmpty) return '';
    return '<${join(',')}>';
  }

  String get constraints {
    if (isEmpty) return '';
    return '[[\n${join(',')}\n]]\n';
  }
}

extension on Map<Identifier, Ty> {
  String get str {
    if (isEmpty) return '';
    return ' : ${toString()}';
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
