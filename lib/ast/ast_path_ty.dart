part of 'ast.dart';

/// [PathTy] 只用于声明
class PathTy {
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
        BuiltInTy.from(ident.src) ?? c.getTy(ident) ?? gen?.call(ident);

    if (tempTy is NewInst && !tempTy.done) {
      tempTy = tempTy.newInstWithGenerics(c, genericInsts, tempTy.generics,
          gen: gen);
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
    return BuiltInTy.from(ident.src) ?? c.getTy(ident);
  }
}

class PathFnDeclTy extends PathTy with EquatableMixin {
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
