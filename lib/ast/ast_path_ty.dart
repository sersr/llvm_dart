// ignore_for_file: overridden_fields

part of 'ast.dart';

/// [PathTy] 只用于声明
class PathTy with EquatableMixin {
  PathTy(this.ident, this.genericInsts, [this.kind = const []]);
  final Identifier ident;
  final List<PointerKind> kind;

  final List<PathTy> genericInsts;

  static final none = PathTy(Identifier.none, const []);

  @override
  String toString() {
    return '${kind.join('')}$ident${genericInsts.str}';
  }

  Ty? grtOrT(Tys c, {GenTy? gen}) {
    var tempTy =
        BuiltInTy.from(ident.src) ?? gen?.call(ident) ?? c.getTy(ident);

    if (tempTy is NewInst && !tempTy.done) {
      tempTy = tempTy.newInstWithGenerics(c, genericInsts, tempTy.generics,
          gen: gen);
    } else if (tempTy is TypeAliasTy) {
      tempTy = tempTy.getTy(c, genericInsts, gen: gen);
    }

    if (tempTy == null) {
      final size = int.tryParse(ident.src);
      if (size != null) {
        return ConstTy(size);
      }
      return null;
    }

    return kind.wrapRefTy(tempTy);
  }

  Ty grt(Tys c, {GenTy? gen}) {
    return grtOrT(c, gen: gen)!;
  }

  Ty? getBaseTy(Tys c) {
    return BuiltInTy.from(ident.src) ?? c.getTy(ident);
  }

  @override
  late final props = [ident, genericInsts, kind];
}

class PathFnDeclTy extends PathTy {
  PathFnDeclTy(this.decl, [List<PointerKind> kind = const []])
      : super(Identifier.none, const [], kind);
  final FnDecl decl;

  @override
  Ty? grtOrT(Tys c, {GenTy? gen}) {
    return kind.wrapRefTy(decl);
  }

  @override
  Ty? getBaseTy(Tys c) {
    return decl;
  }

  @override
  late final props = [decl];

  @override
  String toString() {
    return decl.toString();
  }
}

class SlicePathTy extends PathTy {
  SlicePathTy(this.elementTy, List<PointerKind> kinds)
      : super(Identifier.none, const [], kinds);
  final PathTy elementTy;

  @override
  Ty? grtOrT(Tys<LifeCycleVariable> c, {GenTy? gen}) {
    final element = elementTy.grtOrT(c, gen: gen);
    if (element == null) return null;
    return kind.wrapRefTy(SliceTy(element));
  }

  @override
  Ty? getBaseTy(Tys<LifeCycleVariable> c) {
    return grtOrT(c);
  }

  @override
  late final props = [super.props, elementTy];

  @override
  String toString() {
    return '[$elementTy]';
  }
}

class ConstTy extends Ty {
  ConstTy(this.size);
  final int size;
  @override
  Ty clone() {
    return ConstTy(size);
  }

  @override
  Identifier get ident => Identifier.none;
  @override
  LLVMType get llty => throw UnimplementedError();

  @override
  late final props = [size];

  @override
  String toString() {
    return '$size';
  }
}

class ArrayPathTy extends SlicePathTy {
  ArrayPathTy(super.elementTy, super.kinds, this.size);

  final PathTy size;
  @override
  Ty? grtOrT(Tys c, {GenTy? gen}) {
    final e = elementTy.grtOrT(c, gen: gen);
    final sizeTy = size.grtOrT(c, gen: gen);
    if (e == null || sizeTy is! ConstTy) return null;

    final array = ArrayTy(e, sizeTy);
    return kind.wrapRefTy(array);
  }

  @override
  Ty? getBaseTy(Tys<LifeCycleVariable> c) {
    return grtOrT(c);
  }

  @override
  late final props = [super.props, size];

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
