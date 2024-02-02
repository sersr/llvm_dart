// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../llvm_core.dart';
import '../parsers/lexers/token_kind.dart';
import 'tys.dart';
import 'analysis_context.dart';
import 'builders/builders.dart';
import 'expr.dart';
import 'llvm/build_context_mixin.dart';
import 'llvm/build_methods.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
import 'stmt.dart';

part 'ast_base.dart';
part 'ast_block.dart';
part 'ast_fn.dart';
part 'ast_literal.dart';
part 'ast_new_inst_base.dart';
part 'identifier.dart';
part 'ast_path_ty.dart';

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
  bool _isLimited = false;
  bool get isLimited => _isLimited;
  Ty newConstraints(Tys c, List<ComponentTy> newConstraints, bool isLimited) {
    return clone()
      .._isLimited = isLimited
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

class BuiltInTy extends Ty {
  BuiltInTy._lit(this.literal);

  static final _instances = <LiteralKind, BuiltInTy>{};

  factory BuiltInTy._get(LiteralKind lit) {
    if (lit == LiteralKind.kFloat) {
      lit = LiteralKind.f32;
    } else if (lit == LiteralKind.kDouble) {
      lit = LiteralKind.f64;
    }

    return _instances.putIfAbsent(lit, () => BuiltInTy._lit(lit));
  }

  static BuiltInTy? from(String src) {
    final lit = LiteralKind.values.firstWhereOrNull((e) => e.lit == src);
    if (lit == null) return null;

    return BuiltInTy._get(lit);
  }

  final LiteralKind literal;

  Identifier? _ident;
  @override
  Identifier get ident => _ident ??= literal.name.ident;

  @override
  bool isTy(Ty? other) {
    if (other is BuiltInTy) {
      return other.literal == literal;
    }
    return super.isTy(other);
  }

  @override
  BuiltInTy clone() {
    return BuiltInTy._lit(literal);
  }

  @override
  String toString() {
    return '${literal.lit}${constraints.constraints}';
  }

  @override
  List<Object?> get props => [literal, _constraints];

  @override
  LLVMTypeLit get llty => LLVMTypeLit(this);

  @override
  @override
  void analysis(AnalysisContext context) {}
}

class RefTy extends Ty {
  RefTy(this.parent)
      : isPointer = false,
        ident = '&'.ident;
  RefTy.pointer(this.parent)
      : isPointer = true,
        ident = '*'.ident;
  RefTy.from(this.parent, this.isPointer)
      : ident = isPointer ? '*'.ident : '&'.ident;

  final bool isPointer;
  final Ty parent;

  @override
  final Identifier ident;

  @override
  bool isTy(Ty? other) {
    if (other is RefTy) {
      return baseTy.isTy(other.baseTy);
    }
    return super.isTy(other);
  }

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
  late LLVMRefType llty = LLVMRefType(this);

  @override
  List<Object?> get props => [parent, _constraints];

  @override
  String toString() {
    return 'RefTy($parent)';
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
    return StructTy(ident, fields.clone(), generics).._llty = llty;
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
    context.pushStruct(ident, parentOrCurrent);
  }

  @override
  void analysis(AnalysisContext context) {
    context.pushStruct(ident, parentOrCurrent);
  }

  LLVMStructType? _llty;

  @override
  LLVMStructType get llty => _llty ??= LLVMStructType(this);
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

    final newVariants = <EnumItem>[];
    for (var item in variants) {
      final end = index + item.fields.length;
      final itemFields = fields.sublist(index, end);
      newVariants.add(EnumItem(item.ident, itemFields, item.generics));
      index = end;
    }

    return EnumTy(ident, newVariants, generics);
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
    return EnumItem(ident, fields.clone(), generics).._llty = llty;
  }

  @override
  @protected
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
  LLVMEnumItemType get llty =>
      (_llty ??= LLVMEnumItemType(this)) as LLVMEnumItemType;
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
  ImplTy._(this.generics, this.com, this.struct, this.label, this.fns,
      this.staticFns);
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
    return ImplTy._(generics, com, struct, label, fns, staticFns);
  }

  @override
  ImplTy clone() {
    return this;
  }

  @override
  Identifier get ident => label?.ident ?? Identifier.none;

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
      final result =
          NewInst.resolve(c, exactTy, struct, generics, genMap, true);
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
  List<Object?> get props => [tys, struct, staticFns, fns, label, _constraints];

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
  Identifier get ident => _ident ??= '[$size; $elementTy]'.ident;

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

    final t = grt(c, gen: (ident) => map[ident]);

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
