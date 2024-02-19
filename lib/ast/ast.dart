// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:nop/nop.dart';

import '../abi/abi_fn.dart';
import '../llvm_dart.dart';
import '../parsers/lexers/token_kind.dart';
import 'analysis_context.dart';
import 'builders/builders.dart';
import 'expr.dart';
import 'llvm/build_context_mixin.dart';
import 'llvm/build_methods.dart';
import 'llvm/llvm_types.dart';
import 'llvm/variables.dart';
import 'memory.dart';
import 'stmt.dart';
import 'tys.dart';

part 'ast_base.dart';
part 'ast_block.dart';
part 'ast_fn.dart';
part 'ast_literal.dart';
part 'ast_new_inst_base.dart';
part 'ast_path_ty.dart';
part 'identifier.dart';

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
      ..cloneTys(c, this)
      .._isLimited = newConstraints.isNotEmpty
      .._constraints = newConstraints
      .._buildContext = _buildContext;
  }

  void cloneTys(Tys c, covariant Ty parent) {}

  LLVMTypeRef typeOf(StoreLoadMixin c) => llty.typeOf(c);

  bool extern = false;
  FnBuildMixin? _buildContext;

  FnBuildMixin? get currentContext => _buildContext;

  void prepareBuild(FnBuildMixin context) {
    _buildContext = context;
  }

  AnalysisContext? _analysisContext;
  AnalysisContext? get analysisContext => _analysisContext;

  @mustCallSuper
  void prepareAnalysis(AnalysisContext context) {
    _analysisContext = context;
  }

  Tys? getcurrentContext(Tys base) {
    return switch (base) {
      FnBuildMixin() => currentContext,
      _ => analysisContext,
    } as Tys?;
  }

  void build() {}
  void analysis() {}
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

  static isRefTy(Ty l, Ty r) {
    final ref = l is RefTy ? l : r;
    final rhs = identical(l, ref) ? r : l;
    if (rhs case BuiltInTy(literal: LiteralKind(isInt: true))
        when ref is RefTy) {
      return true;
    }
    return ref.isTy(rhs);
  }

  @override
  bool isTy(Ty? other) {
    if (other is RefTy) {
      return baseTy.isTy(other.baseTy);
    } else if (other is Fn && parent.isTy(LiteralKind.kVoid.ty)) {
      return true;
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
  late LLVMRefType llty = LLVMRefType(this);

  @override
  late final props = [parent, _constraints];

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
    return StructTy(ident, fields.clone(), generics);
  }

  @override
  String toString() {
    var ext = '';
    if (extern) {
      ext = '$extern ';
    }

    return '$pad${ext}struct $ident${generics.str} {${fields.ast}}${tys.str} ${constraints.constraints}';
  }

  @override
  late final props = [ident, fields, _tys, _constraints];

  @override
  void prepareBuild(FnBuildMixin context) {
    super.prepareBuild(context);
    context.pushStruct(ident, parentOrCurrent);
  }

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
    context.pushStruct(ident, parentOrCurrent);
  }

  @override
  late final LLVMStructType llty = LLVMStructType(this);
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
    return '${pad}enum $ident${generics.str} {${variants.ast}}${tys.str}';
  }

  @override
  late final props = [ident, variants, _constraints];

  @override
  void build() {
    for (var v in variants) {
      v.build();
    }
  }

  @override
  void prepareBuild(FnBuildMixin context) {
    super.prepareBuild(context);
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.prepareBuild(context);
    }
  }

  @override
  late LLVMEnumType llty = LLVMEnumType(this);

  @override
  void analysis() {
    for (var v in variants) {
      v.analysis();
    }
  }

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
    context.pushEnum(ident, this);
    for (var v in variants) {
      v.prepareAnalysis(context);
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
    final fy = fields.isEmpty ? '' : '(${fields.ast})';

    return '$ident$fy${parent.tys.str}';
  }

  @override
  EnumItem clone() {
    return EnumItem(ident, fields.clone(), generics);
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
  // ignore: overridden_fields
  late final LLVMEnumItemType llty = LLVMEnumItemType(this);
}

class ComponentTy extends Ty with NewInst<ComponentTy> {
  ComponentTy(this.ident, this.fns, this.generics);

  @override
  final Identifier ident;
  @override
  final List<GenericDef> generics;
  final List<FnDecl> fns;

  @override
  void prepareBuild(FnBuildMixin context) {
    super.prepareBuild(context);
    context.pushComponent(ident, this);
  }

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
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
  late final props = [ident, fns, _tys, _constraints];

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
  ImplTy(this.generics, this.com, this.struct, this.label, List<Fn> fns,
      List<Fn> staticFns, this.aliasTys, this.orderStmts) {
    implFns = fns.map((e) => ImplFn.decl(e.fnDecl, e.block, this)).toList();

    implStaticFns = staticFns
        .map((e) => ImplFn.decl(e.fnDecl, e.block, this, true))
        .toList();

    for (var stmt in orderStmts) {
      stmt.incLevel();
    }
  }

  ImplTy._(this.generics, this.com, this.struct, this.label, this.implFns,
      this.implStaticFns, this.aliasTys, this.orderStmts);
  final PathTy struct;
  final PathTy? com;
  final PathTy? label;
  late final List<ImplFn> implFns;
  late final List<ImplFn> implStaticFns;
  final List<TyStmt> aliasTys;
  final List<TyStmt> orderStmts;

  @override
  final List<GenericDef> generics;

  @override
  List<FieldDef> get fields => const [];
  @override
  ImplTy newTy(List<FieldDef> fields) {
    return ImplTy._(generics, com, struct, label, implFns, implStaticFns,
        aliasTys, orderStmts);
  }

  @override
  ImplTy clone() {
    return ImplTy._(generics, com, struct, label, implFns, implStaticFns,
        aliasTys.clone(), orderStmts.clone());
  }

  @override
  Identifier get ident => label?.ident ?? Identifier.none;

  bool contains(Identifier ident) {
    return implFns.any((e) => e.fnDecl.ident == ident) ||
        implStaticFns.any((e) => e.fnDecl.ident == ident);
  }

  @override
  void incLevel([int count = 1]) {
    super.incLevel(count);
    for (var stmt in orderStmts) {
      stmt.incLevel(count);
    }
  }

  ImplFnMixin? getFn(Identifier ident) {
    return parentOrCurrent._getFn(ident, this);
  }

  ImplFnMixin? _getFn(Identifier ident, ImplTy ty) {
    final fn = implFns.firstWhereOrNull((e) => e.fnDecl.ident == ident) ??
        implStaticFns.firstWhereOrNull((e) => e.fnDecl.ident == ident);
    return fn?.getWith(ty);
  }

  @override
  Ty? getTy(Tys c, Identifier ident) {
    if (ident == Identifier.Self) {
      return ty;
    }

    return super.getTy(c, ident);
  }

  Ty? _ty;
  Ty? get ty => _ty;

  ComponentTy? _componentTy;
  ComponentTy? get comTy => _componentTy;

  final _implTyList = <Ty, ImplTy>{};

  ImplTy? compareStruct(Tys c, Ty exactTy, Ty? comTy) {
    assert(exactTy is! NewInst || exactTy.done);

    c = getcurrentContext(c)!;

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

      final impl = newInst(genMap, c);
      parentOrCurrent._implTyList[exactTy] = impl;
      cache = impl;
    }

    if (comTy == null || comTy.isTy(cache.comTy)) {
      return cache;
    }

    return null;
  }

  @override
  void initNewInst(Tys c) {
    _getComAndTy(c);
  }

  void _getComAndTy(Tys context) {
    final comTy = com?.grtOrT(context, gen: (ident) => tys[ident]);

    assert(comTy == null ||
        comTy is ComponentTy ||
        Log.e('${com?.ident} is not Com\n$comTy\n$comTy'));

    if (comTy is ComponentTy) {
      _componentTy = comTy;
    }

    final ty = struct.grtOrT(context, gen: (ident) => tys[ident]);
    if (ty == null) {
      if (struct case SlicePathTy ty) {
        context.pushImplSliceTy(ty, this);
      } else {
        context.pushImplTy(this);
      }
      return;
    }
    _ty = ty;

    context.pushImplForStruct(ty, this);
  }

  @override
  void build() {
    _getComAndTy(currentContext!);
  }

  @override
  void prepareBuild(FnBuildMixin context) {
    super.prepareBuild(context);
    final child = context.createBlockContext();
    for (var impl in implFns) {
      impl.prepareBuild(child, push: false);
    }
    for (var impl in implStaticFns) {
      impl.prepareBuild(child, push: false);
    }
    for (var alias in aliasTys) {
      alias.prepareBuild(child);
    }
  }

  @override
  void analysis() {
    _getComAndTy(analysisContext!);
    for (var alias in aliasTys) {
      alias.analysis(false);
    }
    for (var impl in implFns) {
      impl.analysisFn();
    }
    for (var impl in implStaticFns) {
      impl.analysisFn();
    }
  }

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
    final child = context.childContext();
    for (var impl in implFns) {
      impl.prepareAnalysis(child, push: false);
    }
    for (var impl in implStaticFns) {
      impl.prepareAnalysis(child, push: false);
    }
    for (var alias in aliasTys) {
      alias.prepareAnalysis(child);
    }
  }

  @override
  String toString() {
    final l = label == null ? '' : ': $label';
    final cc = com == null ? '' : '$com$l for ';
    return 'impl${generics.str} $cc$struct {\n${orderStmts.join('\n')}\n$pad}${tys.str}';
  }

  @override
  late List<Object?> props = [tys, struct, _constraints];

  @override
  LLVMType get llty => throw UnimplementedError();
}

class SliceTy extends Ty {
  SliceTy(this.elementTy);
  final Ty elementTy;

  @override
  Ty clone() {
    return SliceTy(elementTy.clone());
  }

  Identifier? _ident;
  @override
  Identifier get ident => _ident ??= '[$elementTy]'.ident;

  @override
  late final SliceLLVMType llty = SliceLLVMType(this);

  @override
  late final props = [elementTy, _constraints];
}

class ArrayTy extends SliceTy {
  ArrayTy(super.elementTy, this.sizeTy);
  ArrayTy.int(super.elementTy, int size) : sizeTy = ConstTy(size);
  final ConstTy sizeTy;

  int get size => sizeTy.size;

  @override
  Identifier get ident => _ident ??= '[$sizeTy; $elementTy]'.ident;

  @override
  ArrayTy clone() {
    return ArrayTy(elementTy.clone(), sizeTy);
  }

  SliceTy getSlice() {
    return SliceTy(elementTy);
  }

  @override
  // ignore: overridden_fields
  late final ArrayLLVMType llty = ArrayLLVMType(this);

  @override
  List<Object?> get props => [elementTy, sizeTy];

  @override
  String toString() {
    return '[$elementTy; $sizeTy]';
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

    final t = grt(c, gen: (ident) => map[ident]);

    if (t is! T) return null;

    return t;
  }

  @override
  void prepareAnalysis(AnalysisContext context) {
    super.prepareAnalysis(context);
    context.pushAliasTy(ident, this);
  }

  @override
  void prepareBuild(FnBuildMixin context) {
    super.prepareBuild(context);
    context.pushAliasTy(ident, this);
  }

  @override
  late final LLVMAliasType llty = LLVMAliasType(this);

  @override
  late final props = [ident, generics, aliasTy, _constraints];

  @override
  String toString() {
    return '${pad}type $ident${generics.str} = $aliasTy';
  }
}
