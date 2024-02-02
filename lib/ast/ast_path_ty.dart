part of 'ast.dart';

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
