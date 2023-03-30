// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/tys.dart';
import 'package:meta/meta.dart';

import '../parsers/lexers/token_kind.dart';

String getWhiteSpace(int level, int pad) {
  return ' ' * level * pad;
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

  static final Identifier none = Identifier('', 0, 0);

  @override
  List<Object?> get props {
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
    if (builtInName.isNotEmpty) {
      return builtInName;
    }
    final src = Zone.current['astSrc'];
    if (src is String) {
      return src.substring(start, end);
    }
    return '';
  }

  @override
  String toString() {
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
  GenericParam(this.ident, this.ty, this.isRef);
  final Identifier ident;
  final Ty ty;
  final bool isRef;

  @override
  String toString() {
    if (isRef) {
      return '$ident: &$ty';
    }
    return '$ident: $ty';
  }

  @override
  List<Object?> get props => [ident, ty];
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
  String toString() {
    return 'UnknownExpr $ident($message)';
  }

  @override
  ExprTempValue? buildExpr(BuildContext context) {
    context.errorExpr(this);
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

  static int padSize = 2;

  String get pad => getWhiteSpace(level, padSize);
  @override
  String toString() {
    return pad;
  }
}

abstract class Stmt with BuildMixin, EquatableMixin {}

enum LitKind {
  kInt('int'),
  kFloat('float'),
  kDouble('double'),
  kString('string'),
  i8('i8'),
  i16('i16'),
  i32('i32'),
  i64('i64'),
  i128('i128'),
  f32('f32'),
  f64('f64'),
  kBool('bool'),
  kVoid('void'),
  ;

  final String lit;
  const LitKind(this.lit);
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

  @override
  String toString() {
    final p = getWhiteSpace(level, BuildMixin.padSize);
    final s = stmts.map((e) => '$e\n').join();
    return '${ident ?? ''} {\n$s$p}';
  }

  @override
  void build(BuildContext context) {
    for (var stmt in stmts) {
      stmt.build(context);
    }
  }

  @override
  List<Object?> get props => [stmts];
}

// 函数声明
class FnDecl with EquatableMixin {
  FnDecl(this.ident, this.params, this.returnTy);
  final Identifier ident;
  final List<GenericParam> params;
  final Ty returnTy;

  @override
  String toString() {
    return '$ident(${params.join(',')}) -> $returnTy';
  }

  @override
  List<Object?> get props => [ident, params, returnTy];
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

  @override
  List<Object?> get props => [fnDecl, extern];
}

/// ----- Ty -----

abstract class Ty extends BuildMixin with EquatableMixin {
  // @override
  // void build(BuildContext context) {
  //   throw UnimplementedError('ty');
  // }

  static final Ty unknown = UnknownTy(Identifier('', 0, 0));

  LLVMType get llvmType;

  Ty getRealTy(BuildContext c) => this;

  bool extern = false;
  @override
  void build(BuildContext context);
}

class RefTy extends Ty {
  RefTy(this.parent);
  final Ty parent;

  @override
  void build(BuildContext context) {}

  @override
  LLVMRefType get llvmType => LLVMRefType(this);

  @override
  List<Object?> get props => [parent];
}

class BuiltInTy extends Ty {
  BuiltInTy._(this.ty);
  static final int = BuiltInTy._(LitKind.kInt);
  static final float = BuiltInTy._(LitKind.kFloat);
  static final double = BuiltInTy._(LitKind.kDouble);
  static final string = BuiltInTy._(LitKind.kString);
  static final kVoid = BuiltInTy._(LitKind.kVoid);
  static final kBool = BuiltInTy._(LitKind.kBool);

  final LitKind ty;

  static BuiltInTy? from(String src) {
    final lit = LitKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy._(lit);
  }

  @override
  String toString() {
    return ty.name;
  }

  @override
  List<Object?> get props => [ty];

  @override
  LLVMTypeLit get llvmType => LLVMTypeLit(this);

  @override
  void build(BuildContext context) {}
}

/// [PathTy] 只用于声明
class PathTy extends Ty {
  PathTy(this.ident);
  final Identifier ident;

  @override
  String toString() {
    return '$ident';
  }

  @override
  List<Object?> get props => [ident];

  @override
  void build(BuildContext context) {
    final tySrc = ident.src;
    var ty = BuiltInTy.from(tySrc);
    if (ty != null) {
      final hasTy = context.contains(ty);
      assert(hasTy);
    }
  }

  @override
  Ty getRealTy(BuildContext c) {
    final tySrc = ident.src;
    Ty? ty = BuiltInTy.from(tySrc);
    if (ty != null) {
      return ty;
    }

    ty = c.getTy(ident);
    if (ty != null) {
      // error
    }
    return ty!;
  }

  @override
  LLVMType get llvmType => LLVMPathType(this);
}

class UnknownTy extends PathTy {
  UnknownTy(super.ident);

  @override
  String toString() {
    return '{Unknown}';
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

  @override
  void build(BuildContext context) {
    context.pushFn(fnSign.fnDecl.ident, this);
    // final fn = context.buildFn(fnSign);
    // // final blockBB =
    // block.build(context);
    context.buildFnBB(this);
  }

  @override
  late final LLVMFnType llvmType = LLVMFnType(this);
}

class ImplFn extends Fn {
  ImplFn(super.fnSign, super.block, this.ty);
  final StructTy ty;
}

class FieldDef with EquatableMixin {
  FieldDef(this.ident, this.ty);
  final Identifier ident;
  final Ty ty;

  @override
  String toString() {
    return '$ident: $ty';
  }

  @override
  List<Object?> get props => [ident, ty];
}

class StructTy extends Ty with EquatableMixin {
  StructTy(this.ident, this.fields);
  final Identifier ident;
  final List<FieldDef> fields;

  @override
  String toString() {
    return 'struct $ident {${fields.join(',')}}';
  }

  @override
  List<Object?> get props => [ident, fields];

  @override
  void build(BuildContext context) {
    context.pushStruct(ident, this);
  }

  @override
  late final LLVMStructType llvmType = LLVMStructType(this);
}

class UnionTy extends StructTy {
  UnionTy(super.ident, super.fields);
}

class EnumTy extends Ty {
  EnumTy(this.ident, this.variants);
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
  }

  @override
  LLVMType get llvmType => throw UnimplementedError();
}

/// 与 `struct` 类似
class EnumItem with EquatableMixin {
  EnumItem(this.ident, this.fields);
  final Identifier ident;
  final List<FieldDef>? fields;

  @override
  String toString() {
    final f = fields?.map((e) => e.ident).join(',');
    final fy = f == null ? '' : '($f)';
    return '$ident$fy';
  }

  @override
  List<Object?> get props => [ident, fields];
}

class ComponentTy extends Ty {
  ComponentTy(this.ident, this.fns);

  final Identifier ident;
  List<FnSign> fns;

  @override
  void build(BuildContext context) {
    context.pushCOmponent(ident, this);
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
  final Ty ty;
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

  List<ImplFn>? _fns;

  @override
  void build(BuildContext context) {
    // check ty
    context.pushImpl(ident, this);
    final ty = context.getStruct(ident);
    if (ty == null) {
      //error
      return;
    }

    for (var fn in staticFns) {
      context.buildFnBB(fn);
    }
    final ifns =
        _fns ??= fns.map((e) => ImplFn(e.fnSign, e.block, ty)).toList();
    for (var fn in ifns) {
      context.buildFnBB(fn);
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
}
