// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:meta/meta.dart';

import '../parsers/lexers/token_kind.dart';

String getWhiteSpace(int level, int pad) {
  return ' ' * level * pad;
}

class Identifier with EquatableMixin {
  Identifier(this.name, this.start, int? end) : end = (end ?? start) + 1;
  Identifier.fromToken(Token token)
      : start = token.start,
        end = token.end,
        name = '';
  final String name;
  final int start;
  final int end;

  @override
  List<Object?> get props {
    final src = Zone.current['astSrc'];
    if (src is String) {
      return [src.substring(start, end)];
    }
    return [name, start, end];
  }

  String get src {
    final src = Zone.current['astSrc'];
    if (src is String) {
      return src.substring(start, end);
    }
    return '';
  }

  @override
  String toString() {
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
  final Ty ty;

  @override
  String toString() {
    return '$ident: $ty';
  }

  @override
  List<Object?> get props => [ident, ty];
}

abstract class Expr extends BuildMixin {
  @override
  Variable? build(BuildContext context) {
    return _ty = buildExpr(context);
  }

  Variable? _ty;
  Variable? get currentTy => _ty;

  Variable? buildExpr(BuildContext context);
  // return ty
}

class UnknownExpr extends Expr {
  UnknownExpr(this.ident, this.message);
  final Identifier ident;
  final String message;

  @override
  String toString() {
    return 'UnknowExpr $ident($message)';
  }

  @override
  Variable? buildExpr(BuildContext context) {
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
}

class BuiltInTy extends Ty {
  BuiltInTy._(this.ident, this.ty);
  BuiltInTy.int(this.ident) : ty = LitKind.kInt;
  BuiltInTy.float(this.ident) : ty = LitKind.kFloat;
  BuiltInTy.double(this.ident) : ty = LitKind.kDouble;
  BuiltInTy.string(this.ident) : ty = LitKind.kString;
  BuiltInTy.kVoid(this.ident) : ty = LitKind.kVoid;
  BuiltInTy.kBool(this.ident) : ty = LitKind.kBool;

  final LitKind ty;
  final Identifier ident;

  static BuiltInTy? from(Identifier ident, String src) {
    final lit = LitKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy._(ident, lit);
  }

  @override
  String toString() {
    return ty.name;
  }

  @override
  List<Object?> get props => [ty, ident];

  @override
  void build(BuildContext context) {}
}

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
    var ty = BuiltInTy.from(ident, tySrc);
    if (ty != null) {
      final hasTy = context.contains(ty);
      assert(hasTy);
    }
  }
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
    block.incLevel(count);
  }

  final FnSign fnSign;
  final Block block;

  @override
  String toString() {
    return '${pad}fn $fnSign$block';
  }

  @override
  List<Object?> get props => [fnSign, block];

  @override
  void build(BuildContext context) {
    context.pushFn(fnSign.fnDecl.ident, this);
    // final fn = context.buildFn(fnSign);
    // // final blockBB =
    // block.build(context);
    context.buildFnBB(this, (child) {
      block.build(child);
    });
  }
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
}

class ImplTy extends Ty {
  ImplTy(this.ident, this.ty, this.label, this.fns) {
    for (var fn in fns) {
      fn.incLevel();
    }
  }
  final Ty ty;
  final Identifier ident;
  final Identifier? label;
  final List<Fn> fns;

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var fn in fns) {
      fn.incLevel(count);
    }
  }

  @override
  void build(BuildContext context) {
    // check ty
    context.pushImpl(ident, this);
  }

  @override
  String toString() {
    final l = label == null ? '' : ': $label';
    return 'impl $ident$l for $ty {\n$pad${fns.map((e) => '$e\n').join()}$pad}';
  }

  @override
  List<Object?> get props => [ident, ty, fns, label];
}
