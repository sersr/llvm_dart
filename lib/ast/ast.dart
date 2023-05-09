// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../llvm_core.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'context.dart';
import 'expr.dart';
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

class Identifier with EquatableMixin {
  // Identifier(this.name, this.start, int? end)
  //     : end = (end ?? start) + 1,
  //       data = '',
  //       builtInName = '';

  Identifier.fromToken(Token token, this.data)
      : start = token.start,
        end = token.end,
        builtInName = '',
        name = '';

  Identifier.builtIn(this.builtInName)
      : name = '',
        start = 0,
        end = 0,
        data = '';

  final String name;
  final int start;
  final int end;
  final String builtInName;

  @protected
  final String data;

  bool get isValid => end != 0;

  RawIdent get toRawIdent {
    return RawIdent(start, end);
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
    if (builtInName.isNotEmpty) {
      return [builtInName];
    }

    if (enableIdentEq) {
      return [data.substring(start, end)];
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
    return data.substring(start, end);
  }

  /// 指示当前的位置
  String get light {
    return lightSrc(data, start, end);
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

    return data.substring(start, end);
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

  void analysis(AnalysisContext context, Fn fn) {
    context.pushVariable(
      ident,
      context.createVal(fn.getRty(context, ty), ident, ty.kind)
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

  final extensions = <Object, dynamic>{};

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
  kString('string'),

  i8('i8'),
  i16('i16'),
  kInt('int'),
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
  @protected
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

  void analysis(AnalysisContext context, Fn fn) {
    for (var p in params) {
      p.analysis(context, fn);
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
  // @override
  // void build(BuildContext context) {
  //   throw UnimplementedError('ty');
  // }

  static final PathTy unknown = UnknownTy(Identifier.none);

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

  @override
  String toString() {
    return 'RefTy($parent)';
  }
}

class BuiltInTy extends Ty {
  BuiltInTy._(this._ty);
  static final int = BuiltInTy._(LitKind.i32);
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

  // Ty getRty(Tys c) {
  //   return kind.resolveTy(grt(c));
  // }

  Ty? grtBase(Tys c) {
    var rty = ty;
    // if (ty != null) return ty!;

    final tySrc = ident.src;
    rty ??= BuiltInTy.from(tySrc);

    rty ??= c.getTy(ident);
    if (rty == null) {
      // error
    }

    return rty;
  }

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    var rty = ty;
    // if (ty != null) return ty!;

    final tySrc = ident.src;
    rty ??= BuiltInTy.from(tySrc);

    rty ??= c.getTy(ident);
    rty ??= gen?.call(ident);
    if (rty == null) {
      // error
    }
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
    } else if (rty is CTypeTy && generics.isNotEmpty) {
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
    }
    if (rty == null) return null;
    return kind.resolveTy(rty);
  }

  Ty grt(Tys c, {GenTy? gen}) {
    return grtOrT(c, gen: gen)!;
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
    return FnTy(decl)..copy(this);
  }

  @override
  Fn cloneDefault() {
    // copy ???
    return FnTy(fnSign.fnDecl)..copy(this);
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

  Ty getRetTy(Tys c) {
    return getRty(c, fnSign.fnDecl.returnTy);
  }

  Ty? getRetTyOrT(Tys c) {
    return getRtyOrT(c, fnSign.fnDecl.returnTy);
  }

  Ty getRty(Tys c, PathTy ty) {
    return ty.grt(c, gen: (ident) {
      final v = grt(c, ident);
      return v;
    });
  }

  Ty? getRtyOrT(Tys c, PathTy ty) {
    return ty.grtOrT(c, gen: (ident) {
      final v = grt(c, ident);
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

  Ty? grt(Tys c, Identifier ident) {
    return null;
  }

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

  Fn cloneDefault() {
    return Fn(fnSign, block?.clone())..copy(this);
  }

  void copy(Fn from) {
    _parent = from.root;
    selfVariables = from.selfVariables;
    _get = from._get;
    sretVariables = from.sretVariables;
  }

  Fn? _parent;
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
      return context.buildFnBB(this, variables, map ?? const {});
    });
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

  List<RawIdent> sretVariables = [];

  bool _anaysised = false;

  void analysisContext(AnalysisContext context) {}
  @override
  void analysis(AnalysisContext context) {
    if (_anaysised) return;
    _anaysised = true;

    context.pushFn(fnSign.fnDecl.ident, this);
    final child = context.childContext();
    child.setFnContext(this);
    fnSign.fnDecl.analysis(child, this);
    analysisContext(child);
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
  ImplFn(super.fnSign, super.block, this.ty, this.implty);
  final StructTy ty;
  final ImplTy implty;

  @override
  ImplFn get root => super.root as ImplFn;
  final _caches = <StructTy, ImplFn>{};
  ImplFn copyFrom(StructTy other) {
    if (ty == other) return this;
    _parent ??= root;

    return root._caches.putIfAbsent(
      other,
      () {
        return ImplFn(fnSign, block?.clone(), other, implty).._parent = root;
      },
    );
  }

  @override
  Object? getKey() {
    return ty.tys;
  }

  @override
  void analysisContext(AnalysisContext context) {
    final ident = Identifier.builtIn('self');
    final v = context.createVal(ty, ident);
    context.pushVariable(ident, v);
  }

  @override
  Ty? grt(Tys c, Identifier ident) {
    if (ty.generics.isEmpty) return null;
    final impltyStruct = implty.struct.grtOrT(c);
    if (impltyStruct is StructTy) {
      final v = impltyStruct.generics.indexWhere((e) => e.ident == ident);
      if (v != -1) {
        final g = ty.generics[v];
        final vx = ty.tys[g.ident];
        return vx;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [ty.tys, implty];
}

class FieldDef {
  FieldDef(this.ident, this._ty);
  final Identifier ident;
  final PathTy _ty;
  PathTy get rawTy => _ty;
  Ty? _rty;
  Ty grt(Tys c) {
    if (_rty != null) return _rty!;
    return _ty.grt(c);
  }

  Ty? grts(Tys c, GenTy gen) {
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

  List<PointerKind> get kinds => _ty.kind;
  @override
  String toString() {
    return '$ident: ${kinds.join('')}$_ty';
  }

  bool? _isRef;
  bool get isRef => _isRef ??= kinds.isRef;
}

typedef GenTy = Ty? Function(Identifier ident);

class StructTy extends Ty with EquatableMixin implements PathInterFace {
  StructTy(this.ident, this.fields, this.generics);
  final Identifier ident;
  final List<FieldDef> fields;

  final List<FieldDef> generics;

  final _tyLists = <ListKey, StructTy>{};

  Map<Identifier, Ty>? _tys;
  @override
  Map<Identifier, Ty> get tys => _tys ?? const {};

  StructTy? _parent;
  StructTy get parentOrCurrent => _parent ?? this;
  StructTy newInst(Map<Identifier, Ty> tys, Tys c, {GenTy? gen}) {
    _parent ??= this;
    if (tys.isEmpty) return _parent!;
    final key = ListKey(tys);
    return _parent!._tyLists.putIfAbsent(key, () {
      final newFields = <FieldDef>[];
      for (var f in fields) {
        final nf = f.clone();
        final g = f.grts(c, (ident) {
          final data = tys[ident];
          if (data != null) {
            // Log.w(data);
            return data;
          }
          return gen?.call(ident);
        });
        nf._rty = g;
        newFields.add(nf);
      }

      return StructTy(ident, newFields, generics)
        .._parent = _parent
        .._tys = tys;
    });
  }

  @override
  String toString() {
    var g = '';
    if (generics.isNotEmpty) {
      g = generics.join(',');
      g = '<$g>';
    }
    return '${pad}struct $ident$g {${fields.join(',')}}';
  }

  @override
  List<Object?> get props => [ident, fields];

  @override
  void build(BuildContext context) {
    context.pushStruct(ident, this);
    context.pushVariable(ident, TyVariable(this));
  }

  void push(Tys context) {
    context.pushStruct(ident, this);
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushStruct(ident, this);
  }

  @override
  late final LLVMStructType llvmType = LLVMStructType(this);
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
  EnumItem(super.ident, super.fields, super.generics);
  late EnumTy parent;
  @override
  String toString() {
    final f = fields.map((e) => e._ty).join(',');
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

  ImplFn? getFn(Identifier ident) {
    return _fns?.firstWhereOrNull((e) => e.fnSign.fnDecl.ident == ident);
  }

  List<ImplFn>? _fns;

  void initStructFns(Tys context) {
    // final ty = struct.grt(context);
    final ident = struct.ident;
    final ty = context.getStruct(ident);
    if (ty is! StructTy) return;
    context.pushImplForStruct(ty, this);
    // final ty = context.getStruct(ident);
    // if (ty == null) {
    //   //error
    //   return;
    // }
    _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty, this)).toList();
    for (var fn in staticFns) {
      fn.pushFn(context);
    }
  }

  @override
  void build(BuildContext context) {
    context.pushImpl(struct.ident, this);
    initStructFns(context);
    // // check ty
    // final structTy = context.getStruct(ident);
    // if (structTy == null) return;
    // context.pushImplForStruct(structTy, this);
    // final ty = context.getStruct(ident);
    // if (ty == null) {
    //   //error
    //   return;
    // }

    // for (var fn in staticFns) {
    //   fn.customBuild(context);
    // }
    // final ifns =
    //     _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty)).toList();
    // for (var fn in ifns) {
    //   fn.customBuild(context);
    // }
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
  List<Object?> get props => [struct, struct, fns, label];

  @override
  LLVMType get llvmType => throw UnimplementedError();

  @override
  void analysis(AnalysisContext context) {
    final ident = struct.ident;
    context.pushImpl(ident, this);
    initStructFns(context);
    // final structTy = context.getStruct(ident);

    // if (structTy is! StructTy) return;
    // context.pushImplForStruct(structTy, this);
    // final ty = context.getStruct(ident);
    // if (ty == null) {
    //   //error
    //   return;
    // }
  }
}

class ArrayTy extends Ty {
  ArrayTy(this.elementType);
  final Ty elementType;

  @override
  void analysis(AnalysisContext context) {}

  @override
  void build(BuildContext context) {}

  @override
  late final ArrayLLVMType llvmType = ArrayLLVMType(this);

  @override
  List<Object?> get props => [elementType];
}

class ArrayLLVMType extends LLVMType {
  ArrayLLVMType(this.ty);

  @override
  final ArrayTy ty;
  @override
  LLVMTypeRef createType(BuildContext c) {
    return c.typePointer(ty.elementType.llvmType.createType(c));
  }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }

  StoreVariable createArray(BuildContext c, int count) {
    return LLVMAllocaDelayVariable(ty, ([alloca]) {
      return c.createArray(ty.elementType.llvmType.createType(c), count);
    }, createType(c));
  }

  Variable getElement(BuildContext c, Variable val, LLVMValueRef index) {
    final indics = <LLVMValueRef>[index];

    final p = val.load(c);

    final v = llvm.LLVMBuildInBoundsGEP2(
        c.builder, createType(c), p, indics.toNative(), indics.length, unname);
    final vv = LLVMRefAllocaVariable.from(v, ty.elementType, c);
    vv.isTemp = false;
    return vv;
  }
}

abstract class PathInterFace {
  Map<Identifier, Ty> get tys;
}

class CTypeTy extends Ty implements PathInterFace {
  CTypeTy(this.pathTy);
  final PathTy pathTy;
  Identifier get ident => pathTy.ident;

  List<PathTy> get generics => pathTy.generics;

  CTypeTy? _parent;
  CTypeTy get root => _parent ?? this;
  Map<Identifier, Ty>? _tys;
  @override
  Map<Identifier, Ty> get tys => _tys ?? const {};
  final _tyLists = <ListKey, CTypeTy>{};

  CTypeTy newInst(Map<Identifier, Ty> tys, Tys c, {GenTy? gen}) {
    _parent ??= this;
    return root._tyLists.putIfAbsent(ListKey(tys), () {
      return CTypeTy(pathTy).._tys = tys;
    });
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushCty(pathTy.ident, this);
  }

  @override
  void build(BuildContext context) {
    context.pushCty(pathTy.ident, this);
  }

  @override
  late final CTypeLLVMType llvmType = CTypeLLVMType(this);

  @override
  List<Object?> get props => [pathTy];

  @override
  String toString() {
    var g = '';
    if (generics.isNotEmpty) {
      g = generics.join(',');
      g = '<$g>';
    }
    return 'type $ident$g';
  }
}

class CTypeLLVMType extends LLVMType {
  CTypeLLVMType(this.ty);

  @override
  final CTypeTy ty;

  @override
  LLVMTypeRef createType(BuildContext c) {
    return c.pointer();
  }

  @override
  int getBytes(BuildContext c) {
    return c.pointerSize();
  }
}
