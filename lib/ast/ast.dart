// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../abi/abi_fn.dart';
import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
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

  static bool get enableIdentEq {
    return Zone.current[#data] == true;
  }

  static R run<R>(R Function() body, {ZoneSpecification? zoneSpecification}) {
    return runZoned(body,
        zoneValues: {#data: true}, zoneSpecification: zoneSpecification);
  }

  @override
  List<Object?> get props {
    if (identical(this, none)) {
      return [''];
    }
    if (builtInValue.isNotEmpty) {
      return [builtInValue];
    }

    if (enableIdentEq) {
      return [data.substring(start, end)];
    }
    return [name, start, end];
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
  ExprTempValue(this.variable, this.ty, this.currentIdent);
  final Ty ty;
  final Variable? variable;
  Identifier currentIdent;

  Offset get offset => currentIdent.offset;
}

abstract class Expr extends BuildMixin {
  bool _first = true;

  bool get hasUnknownExpr => false;

  void reset() {
    _first = true;
    _temp = null;
  }

  ExprTempValue? _temp;
  ExprTempValue? build(BuildContext context, {Ty? baseTy}) {
    if (!_first) return _temp;
    _first = false;
    return _temp ??= buildExpr(context, baseTy);
  }

  Expr clone();

  Ty? getTy(BuildContext context) => null;

  @override
  AnalysisVariable? analysis(AnalysisContext context);

  @protected
  ExprTempValue? buildExpr(BuildContext context, Ty? baseTy);
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
  ExprTempValue? buildExpr(BuildContext context, Ty? baseTy) {
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
  void build(BuildContext context);
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
  Block(this.stmts, this.ident, this.blockStart, this.blockEnd) {
    _init();
    final fnStmt = <FnExpr>[];
    final others = <Stmt>[];
    // 函数声明前置
    for (var stmt in stmts) {
      if (stmt is ExprStmt) {
        final expr = stmt.expr;
        if (expr is FnExpr) {
          fnStmt.add(expr);
          continue;
        }
      }
      others.add(stmt);
    }
    _fnExprs = fnStmt;
    _stmts = others;
  }

  void _init() {
    // {
    //   stmt
    // }
    for (var s in stmts) {
      s.incLevel();
    }
  }

  final Identifier? ident;
  final List<Stmt> stmts;

  late List<FnExpr> _fnExprs;
  late List<Stmt> _stmts;
  final Identifier blockStart;
  final Identifier blockEnd;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);

    for (var s in stmts) {
      s.incLevel(count);
    }
  }

  Block clone() {
    return Block(
        stmts.map((e) => e.clone()).toList(), ident, blockStart, blockEnd);
  }

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = stmts.map((e) => '$e\n').join();
    return '${ident ?? ''} {\n$s$p}';
  }

  void ret(BuildContext context) {
    if (stmts.isNotEmpty) {
      final stmt = stmts.last;
      if (stmt is ExprStmt) {
        final expr = stmt.expr;
        if (expr is! RetExpr) {
          // 获取缓存的value
          final valTemp = expr.build(context);
          final val = valTemp?.variable;
          context.ret(val, valTemp?.currentIdent);
        }
      }
    } else {
      context.ret(null, null);
    }
  }

  void build(BuildContext context, {bool free = true}) {
    for (var expr in _fnExprs) {
      expr.fn.pushFn(context);
    }

    // 先处理普通语句，在内部函数中可能会引用到变量等
    for (var stmt in _stmts) {
      stmt.build(context);
    }

    if (free) context.freeHeap();
  }

  @override
  List<Object?> get props => [stmts];

  @override
  void analysis(AnalysisContext context) {
    for (var expr in _fnExprs) {
      expr.fn.pushFn(context);
    }

    for (var i = 0; i < _stmts.length; i += 1) {
      final stmt = stmts[i];
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
  final List<FieldDef> generics;

  final PathTy returnTy;
  final bool isVar;

  bool eq(FnDecl other) {
    return const DeepCollectionEquality().equals(params, other.params) &&
        returnTy == other.returnTy;
  }

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
      final t = fn.getRty(context, p);
      context.pushVariable(
        p.ident,
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

abstract class Ty extends BuildMixin with EquatableMixin {
  static final PathTy unknown = UnknownTy(Identifier.none);

  LLVMType get llty;

  LLVMTypeRef typeOf(LLVMTypeMixin c) => llty.typeOf(c);

  Ty getRealTy(BuildContext c) => this;

  bool extern = false;
  BuildContext? _buildContext;
  // ignore: unnecessary_getters_setters
  BuildContext? get currentContext => _buildContext;

  set currentContext(BuildContext? context) {
    _buildContext = context;
  }

  void build() {}
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
  @override
  void analysis(AnalysisContext context) {}

  @override
  LLVMRefType get llty => LLVMRefType(this);

  @override
  List<Object?> get props => [parent];

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

  static BuiltInTy? from(String src) {
    final lit = LitKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy.get(lit);
  }

  @override
  String toString() {
    return _ty.lit;
  }

  @override
  List<Object?> get props => [_ty];

  @override
  LLVMTypeLit get llty => LLVMTypeLit(this);

  @override
  @override
  void analysis(AnalysisContext context) {}
}

/// [PathTy] 只用于声明
class PathTy with EquatableMixin {
  PathTy(this.ident, this.generics, [this.kind = const []]) : ty = null;
  PathTy.ty(Ty this.ty, [this.kind = const []])
      : ident = Identifier.none,
        generics = const [];
  final Identifier ident;
  final Ty? ty;
  final List<PointerKind> kind;

  final List<PathTy> generics;

  bool? _isRef;
  bool get isRef => _isRef ??= kind.isRef;

  @override
  String toString() {
    if (ty != null) return ty!.toString();
    var g = '';
    if (generics.isNotEmpty) {
      g = generics.join(',');
      g = '<$g>';
    }
    return '${kind.join('')}$ident$g';
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

  Ty? grtBase(Tys c) {
    var rty = ty;

    final tySrc = ident.src;
    rty ??= BuiltInTy.from(tySrc);

    rty ??= c.getTy(ident);
    if (rty == null) {
      // error
    }

    return rty;
  }

  Ty? grtOrT(Tys c, {GenTy? gen, GenTy? getTy}) {
    var rty = ty;

    final tySrc = ident.src;
    rty ??= BuiltInTy.from(tySrc);

    if (getTy != null) {
      rty ??= getTy(ident);
    } else {
      rty ??= c.getTy(ident);
    }
    rty ??= gen?.call(ident);

    if (rty is StructTy && generics.isNotEmpty) {
      final gMap = <Identifier, Ty>{};

      for (var i = 0; i < generics.length; i += 1) {
        final g = generics[i];
        final gg = rty.generics[i];
        final gty = g.grtOrT(c, gen: gen);
        if (gty != null) {
          gMap[gg.ident] = gty;
        }
      }
      rty = rty.newInst(gMap, c, gen: gen);
    } else if (rty is TypeAliasTy) {
      rty = rty.getTy(c, generics);
    }
    if (rty == null) {
      return null;
    }
    return kind.resolveTy(rty);
  }

  Ty grt(Tys c, {GenTy? gen}) {
    return grtOrT(c, gen: gen)!;
  }
}

class ArrayPathTy extends PathTy {
  ArrayPathTy(this.elementTy, this.size) : super(Identifier.none, []);
  final PathTy elementTy;
  final Expr size;

  @override
  Ty? grtOrT(Tys c, {GenTy? gen, GenTy? getTy}) {
    final e = elementTy.grtOrT(c, gen: gen, getTy: getTy);
    if (e == null) return null;
    Expr s = size;
    if (s is RefExpr) {
      s = s.current;
    }
    if (s is LiteralExpr) {
      final raw = LLVMRawValue(s.ident);
      return ArrayTy(e, raw.iValue);
    }

    return null;
  }

  @override
  String toString() {
    return '[$elementTy; $size]';
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
      cache.add(FieldDef(e.ident, PathTy.ty(e.ty, [PointerKind.ref])));
    }
    final decl = FnDecl(rawDecl.ident, cache, rawDecl.generics,
        rawDecl.returnTy, rawDecl.isVar);
    return FnTy(decl)..copy(this);
  }

  @override
  Fn cloneDefault() {
    // copy ???
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

  Ty getRetTy(Tys c) {
    return getRetTyOrT(c)!;
  }

  Ty? getRetTyOrT(Tys c) {
    return _getRtyOrT(c, fnSign.fnDecl.returnTy);
  }

  Ty getRty(Tys c, FieldDef p) {
    return p.grts(c, (ident) {
      final v = tys[ident] ?? grt(c, ident);
      return v;
    });
  }

  Ty? getRtyOrT(Tys c, FieldDef p) {
    return p.grtOrT(c, gen: (ident) {
      final v = tys[ident] ?? grt(c, ident);
      return v;
    });
  }

  Ty? _getRtyOrT(Tys c, PathTy ty) {
    return ty.grtOrT(c, gen: (ident) {
      final v = tys[ident] ?? grt(c, ident);
      return v;
    });
  }

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

  @mustCallSuper
  Ty? grt(Tys c, Identifier ident) {
    return tys[ident];
  }

  final _cache = <ListKey, LLVMConstVariable>{};

  void pushFn(Tys context) {
    context.pushFn(fnSign.fnDecl.ident, this);
  }

  @override
  LLVMConstVariable? build(
      [Set<AnalysisVariable>? variables,
      Map<Identifier, Set<AnalysisVariable>>? map]) {
    final context = currentContext;
    assert(context != null);
    if (context == null) return null;
    return customBuild(context, variables, map);
  }

  Fn cloneDefault() {
    return Fn(fnSign, block?.clone())..copy(this);
  }

  void copy(Fn from) {
    _parent = from.root;
    selfVariables = from.selfVariables;
    _get = from._get;
    currentContext = from.currentContext;
  }

  Fn get root => _parent ?? this;

  LLVMConstVariable? customBuild(BuildContext context,
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

    return root._cache.putIfAbsent(key, () {
      return context.buildFnBB(
          this, variables, map ?? const {}, pushTyGenerics);
    });
  }

  void pushTyGenerics(BuildContext context) {
    context.pushDyTys(tys);
  }

  void pushTyAnalysis(AnalysisContext context) {
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
    if (generics.isNotEmpty && tys.isEmpty) {
      return;
    }

    final child = context.childContext();
    pushTyAnalysis(child);

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
  List<FieldDef> get generics => fnSign.fnDecl.generics;

  @override
  Fn newTy(List<FieldDef> fields) {
    final s = FnSign(fnSign.extern, fnSign.fnDecl.copywith(fields));
    return Fn(s, block?.clone())..copy(this);
  }
}

mixin ImplFnMixin on Fn {
  Ty get ty;
  ImplTy get implty;

  ImplFnMixin get rootImpl => _parentImpl ?? this;
  final _cachesImpl = <Ty, ImplFnMixin>{};
  ImplFnMixin? _parentImpl;

  ImplFnMixin copyFrom(Ty other) {
    if (ty == other) return this;
    _parent ??= root;

    return rootImpl._cachesImpl
        .putIfAbsent(other, () => cloneImpl(other).._parentImpl = this);
  }

  @override
  BuildContext? get currentContext =>
      super.currentContext ?? implty.currentContext;

  @override
  ImplFnMixin newTy(List<FieldDef> fields);

  @override
  void pushTyGenerics(BuildContext context) {
    super.pushTyGenerics(context);
    final structTy = ty;
    if (structTy is! StructTy) return;
    context.pushDyTys(structTy.tys);
  }

  @override
  void pushTyAnalysis(AnalysisContext context) {
    super.pushTyAnalysis(context);
    final structTy = ty;
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
  Ty? grt(Tys c, Identifier ident) {
    final nTy = super.grt(c, ident);
    if (nTy != null) {
      return nTy;
    }

    final ty = this.ty;
    if (ident.src == 'Self') {
      return ty;
    }

    if (ty is! StructTy) return null;
    if (ty.generics.isEmpty) return null;
    final v = ty.generics.indexWhere((e) => e.ident == ident);
    if (v != -1) {
      final g = ty.generics[v];
      final vx = ty.tys[g.ident];
      return vx;
    }

    return null;
  }

  @override
  List<Object?> get props => [ty, implty];

  ImplFnMixin cloneImpl(Ty other);
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
    return ImplFn(s, block?.clone(), ty, implty)..copy(this);
  }

  @override
  ImplFn cloneImpl(Ty other) {
    return ImplFn(fnSign, block?.clone(), other, implty);
  }

  @override
  void analysisContext(AnalysisContext context) {
    final ident = Identifier.builtIn('self');
    final v = context.createVal(ty, ident);
    v.lifecycle.isOut = true;
    context.pushVariable(ident, v);
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

  @override
  ImplStaticFn cloneImpl(Ty other) {
    return ImplStaticFn(fnSign, block?.clone(), other, implty);
  }
}

class FieldDef with EquatableMixin {
  FieldDef(this.ident, this._ty) : _rty = null;
  FieldDef._internal(this.ident, this._ty, this._rty);
  final Identifier ident;
  final PathTy _ty;
  PathTy get rawTy => _ty;
  final Ty? _rty;
  Ty grt(Tys c) {
    if (_rty != null) return _rty!;
    return _ty.grt(c);
  }

  Ty grts(Tys c, GenTy gen) {
    if (_rty != null) return _rty!;
    return _ty.grt(c, gen: gen);
  }

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    if (_rty != null) return _rty!;
    return _ty.grtOrT(c, gen: gen);
  }

  FieldDef clone() {
    return FieldDef(ident, _ty);
  }

  FieldDef copyWithTy(Ty? ty) {
    return FieldDef._internal(ident, _ty, ty);
  }

  List<PointerKind> get kinds => _ty.kind;
  @override
  String toString() {
    return '$ident: $_ty';
  }

  bool? _isRef;
  bool get isRef => _isRef ??= kinds.isRef;

  @override
  List<Object?> get props => [_rty, _ty, ident];
}

typedef GenTy = Ty? Function(Identifier ident);

mixin NewInst<T extends Ty> {
  List<FieldDef> get fields;
  List<FieldDef> get generics;

  Map<Identifier, Ty>? _tys;

  Map<Identifier, Ty> get tys => _tys ?? const {};
  final _tyLists = <ListKey, T>{};

  T? _parent;
  T get parentOrCurrent => _parent ?? this as T;
  T newInst(Map<Identifier, Ty> tys, Tys c, {GenTy? gen}) {
    _parent ??= this as T;
    if (tys.isEmpty) return _parent!;
    final key = ListKey(tys);

    final newInst = (_parent as NewInst)._tyLists.putIfAbsent(key, () {
      final newFields = <FieldDef>[];
      for (var f in fields) {
        final g = f.grtOrT(c, gen: (ident) {
          final data = tys[ident];
          if (data != null) {
            var d = data;
            for (var k in f.kinds) {
              if ((k == PointerKind.ref || k == PointerKind.deref) &&
                  d is RefTy) {
                d = d.parent;
              }
            }
            return d;
          }
          return gen?.call(ident);
        });
        final nf = f.copyWithTy(g);
        newFields.add(nf);
      }

      final ty = newTy(newFields);
      (ty as NewInst)
        .._parent = _parent
        .._tys = tys;
      return ty;
    });

    newInst.currentContext = parentOrCurrent.currentContext;

    return newInst as T;
  }

  T newInstWithGenerics(Tys c, List<PathTy> realTypes, List<FieldDef> current,
      {Map<Identifier, Ty> extra = const {}, GenTy? gen}) {
    final types = <Identifier, Ty>{}..addAll(extra);
    for (var i = 0; i < realTypes.length; i += 1) {
      final g = realTypes[i];
      final name = current[i];
      types[name.ident] = g.grt(c);
    }

    return newInst(types, c, gen: gen);
  }

  T newTy(List<FieldDef> fields);
}

class StructTy extends Ty
    with EquatableMixin, NewInst<StructTy>
    implements PathInterFace {
  StructTy(this.ident, this.fields, this.generics);
  final Identifier ident;
  @override
  final List<FieldDef> fields;

  @override
  final List<FieldDef> generics;

  @override
  StructTy newTy(List<FieldDef> fields) {
    return StructTy(ident, fields, generics);
  }

  @override
  String toString() {
    var g = '';
    if (generics.isNotEmpty) {
      g = generics.join(',');
      g = '<$g>';
    }

    if (extern) {
      return '${pad}extern struct $ident$g {${fields.join(',')}}';
    }

    return '${pad}struct $ident$g {${fields.join(',')}}';
  }

  @override
  List<Object?> get props => [ident, fields, _tys];

  @override
  void build() {
    throw UnimplementedError('use buildItem instead.');
  }

  void buildItem(BuildContext context) {
    final context = currentContext;
    if (context == null) return;
    context.pushStruct(ident, this);
  }

  void push(Tys context) {
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
  void push(Tys context) {
    for (var v in variants) {
      v.push(context);
    }
  }

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.buildItem(context);
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
}

/// 与 `struct` 类似
class EnumItem extends StructTy {
  EnumItem(super.ident, super.fields, super.generics);
  late EnumTy parent;
  @override
  String toString() {
    final fy = fields.isEmpty ? '' : '(${fields.join(', ')})';
    return '$ident$fy';
  }

  @override
  // ignore: overridden_fields
  late final LLVMEnumItemType llty = LLVMEnumItemType(this);
}

class ComponentTy extends Ty {
  ComponentTy(this.ident, this.fns);

  final Identifier ident;
  List<FnSign> fns;

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
  String toString() {
    final pddd = getWhiteSpace(level + 1, BuildMixin.padSize);
    return 'com $ident {\n$pddd${fns.join('\n$pddd')}\n$pad}';
  }

  @override
  List<Object?> get props => [ident, fns];

  @override
  LLVMType get llty => throw UnimplementedError();
}

class ImplTy extends Ty {
  ImplTy(this.com, this.struct, this.label, this.fns, this.staticFns) {
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

  void initStructFns(Tys context) {
    final ty = struct.grtOrT(context, getTy: context.getTyIgnoreImpl);
    if (ty == null) return;
    context.pushImplForStruct(ty, this);

    _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty, this)).toList();
    _staticFns ??= staticFns
        .map((e) => ImplStaticFn(e.fnSign, e.block, ty, this))
        .toList();
  }

  @override
  void build() {
    final context = currentContext;
    if (context == null) return;
    context.pushImpl(struct.ident, this);
    initStructFns(context);
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
    return 'impl $cc$struct {\n$pad$sfnn$fnnStr$pad}';
  }

  @override
  List<Object?> get props => [struct, staticFns, fns, label];

  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  void analysis(AnalysisContext context) {
    final ident = struct.ident;
    context.pushImpl(ident, this);
    initStructFns(context);
  }
}

class ArrayTy extends Ty {
  ArrayTy(this.elementTy, this.size);
  final Ty elementTy;
  final int size;

  @override
  void analysis(AnalysisContext context) {}

  @override
  @override
  late final ArrayLLVMType llty = ArrayLLVMType(this);

  @override
  List<Object?> get props => [elementTy];
}

class ArrayLLVMType extends LLVMType {
  ArrayLLVMType(this.ty);

  @override
  final ArrayTy ty;
  @override
  LLVMTypeRef typeOf(BuildContext c) {
    return c.arrayType(ty.elementTy.typeOf(c), ty.size);
  }

  @override
  int getBytes(BuildContext c) {
    return c.typeSize(typeOf(c));
  }

  @override
  LLVMAllocaDelayVariable createAlloca(
      BuildContext c, Identifier ident, LLVMValueRef? base) {
    final val = LLVMAllocaDelayVariable(ty, base, ([alloca, nIdent]) {
      nIdent ??= ident;
      final count = c.constI64(ty.size);
      return c.createArray(ty.elementTy.typeOf(c), count, name: nIdent.src);
    }, typeOf(c));
    if (ident.isValid) {
      val.ident = ident;
    }
    return val;
  }

  LLVMConstVariable createArray(BuildContext c, List<LLVMValueRef> values) {
    final value = c.constArray(ty.elementTy.typeOf(c), values);
    return LLVMConstVariable(value, ty);
  }

  Variable getElement(BuildContext c, Variable value, LLVMValueRef index,
      {Offset offset = Offset.zero}) {
    final indics = <LLVMValueRef>[index];

    final p = value.getBaseValue(c);

    final elementTy = ty.elementTy.typeOf(c);

    c.diSetCurrentLoc(offset);
    final v = llvm.LLVMBuildInBoundsGEP2(
        c.builder, elementTy, p, indics.toNative(), indics.length, unname);

    final vv = LLVMAllocaVariable(ty.elementTy, v, elementTy);
    vv.isTemp = false;
    return vv;
  }

  Variable toStr(BuildContext c, Variable value) {
    return LLVMConstVariable(value.getBaseValue(c), LitKind.kStr.ty);
  }

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    return llvm.LLVMDIBuilderCreateArrayType(
        c.dBuilder!,
        ty.size,
        ty.elementTy.llty.getBytes(c),
        ty.elementTy.llty.createDIType(c),
        nullptr,
        0);
  }
}

abstract class PathInterFace {
  Map<Identifier, Ty> get tys;
}

class TypeAliasTy extends Ty {
  TypeAliasTy(this.ident, this.generics, this.baseTy);
  final Identifier ident;

  final List<FieldDef> generics;
  final PathTy? baseTy;

  Ty? grt(Tys c, {GenTy? gen}) {
    if (baseTy == null) return this;
    return baseTy!.grtOrT(c, gen: gen);
  }

  T? getTy<T extends Ty>(Tys c, List<PathTy> gs, {GenTy? gen}) {
    final gMap = <Identifier, Ty>{};
    for (var i = 0; i < gs.length; i += 1) {
      final gg = gs[i];
      final g = generics[i];
      gMap[g.ident] = gg.grt(c);
    }
    final t = grt(c, gen: (ident) {
      return gMap[ident];
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
  List<Object?> get props => [ident, generics, baseTy];

  @override
  String toString() {
    var g = '';
    if (generics.isNotEmpty) {
      g = generics.join(',');
      g = '<$g>';
    }
    if (baseTy != null) {
      return 'type $ident$g = $baseTy';
    }
    return 'type $ident$g';
  }
}

class LLVMAliasType extends LLVMType {
  LLVMAliasType(this.ty);

  @override
  final TypeAliasTy ty;

  @override
  LLVMTypeRef typeOf(BuildContext c) {
    final base = ty.baseTy;
    if (base == null) return c.pointer();
    final bty = base.grt(c);
    return bty.typeOf(c);
  }

  @override
  int getBytes(BuildContext c) {
    final base = ty.baseTy;
    if (base == null) return c.pointerSize();
    final bty = base.grt(c);
    return bty.llty.getBytes(c);
  }

  @override
  LLVMMetadataRef createDIType(covariant BuildContext c) {
    final base = ty.baseTy;
    if (base == null) {
      return llvm.LLVMDIBuilderCreateBasicType(
          c.dBuilder!, 'ptr'.toChar(), 3, c.pointerSize() * 8, 1, 0);
    }
    return base.grt(c).llty.createDIType(c);
  }
}

/// 弃用
class HeapTy extends RefTy {
  HeapTy(this.parent) : super(parent);

  @override
  // ignore: overridden_fields
  final StructTy parent;

  @override
  String toString() {
    return 'HeapTy($parent)';
  }

  @override
  late LLVMHeapType llty = LLVMHeapType(this);
}

class LLVMHeapType extends LLVMRefType {
  LLVMHeapType(HeapTy super.ty);

  @override
  HeapTy get ty => super.ty as HeapTy;
  StructTy get heapStructTy => ty.parent;

  StoreVariable getData(BuildContext context, Variable variable) {
    final data = heapStructTy.llty
        .getField(variable, context, Identifier.builtIn('data'));
    return data!;
  }

  StoreVariable getCount(
    BuildContext context,
    Variable variable,
  ) {
    final count = heapStructTy.llty
        .getField(variable, context, Identifier.builtIn('count'));
    return count!;
  }

  void initData(BuildContext context, Variable variable) {
    final llType = heapStructTy.llty;
    final count =
        llType.getField(variable, context, Identifier.builtIn('count'))!;
    count.store(context, context.usizeValue(1), Offset.zero);
    // final start =
    //     llType.getField(variable, context, Identifier.builtIn('start'))!;
    // final pointerStart = variable.getBaseValue(context);
    // start.store(context, pointerStart, Offset.zero);

    final data =
        llType.getField(variable, context, Identifier.builtIn('data'))!;

    if (variable is LLVMAllocaDelayVariable && !variable.created) {
      variable.create(context, data);
    } else {
      final size = llType.getBytes(context);
      context.memcopy(data, variable, context.usizeValue(size));
    }
  }

  void memRef(BuildContext context, Variable variable, Variable src) {
    final llType = heapStructTy.llty;
    final count =
        llType.getField(variable, context, Identifier.builtIn('count'))!;
    count.store(context, context.usizeValue(1), Offset.zero);
    // final start =
    //     llType.getField(variable, context, Identifier.builtIn('start'))!;
    // final pointerStart = variable.load(context, Offset.zero);
    // start.store(context, pointerStart, Offset.zero);
  }

  void addStack(BuildContext context, Variable variable) {
    final ident = Identifier.builtIn('addStack');
    final impl = context.getImplForStruct(heapStructTy, ident);
    var implFn = impl?.getFn(ident);
    final addFn = implFn?.copyFrom(heapStructTy);
    if (addFn == null) {
      Log.e('error addFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      addFn,
      [],
      LLVMConstVariable(variable.load(context, Offset.zero), ty),
      null,
      null,
      Identifier.none,
    );
  }

  void removeStack(BuildContext context, Variable variable) {
    final ident = Identifier.builtIn('removeStack');
    final impl = context.getImplForStruct(heapStructTy, ident);

    var implFn = impl?.getFn(ident);
    final removeFn = implFn?.copyFrom(heapStructTy);
    if (removeFn == null) {
      Log.e('error removeFn == null.', onlyDebug: false);
      return;
    }
    AbiFn.fnCallInternal(
      context,
      removeFn,
      [],
      LLVMConstVariable(variable.load(context, Offset.zero), ty),
      null,
      null,
      Identifier.none,
    );
  }
}
