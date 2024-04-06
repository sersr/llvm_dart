part of 'ast.dart';

enum LiteralKind {
  f32('f32'),
  f64('f64'),
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

  LiteralKind get convert {
    if (index >= u8.index && index <= usize.index) {
      final diff = index - u8.index;
      return values[i8.index + diff];
    }

    return this;
  }

  bool get signed {
    if (index >= i8.index && index <= isize.index) {
      return true;
    }
    return false;
  }

  final String lit;
  const LiteralKind(this.lit);

  static const max = 6;

  static LiteralKind? from(String src) {
    return switch (src) {
      'float' => f32,
      'double' => f64,
      var src => values.firstWhereOrNull((e) => e.lit == src)
    };
  }

  BuiltInTy get ty => BuiltInTy._get(this);

  LLVMTypeLit get llty => ty.llty;
}

class BuiltInTy extends Ty {
  BuiltInTy._lit(this.literal);

  static final _instances = <LiteralKind, BuiltInTy>{};

  factory BuiltInTy._get(LiteralKind lit) {
    return _instances.putIfAbsent(lit, () => BuiltInTy._lit(lit));
  }

  static BuiltInTy? from(String src) {
    if (LiteralKind.from(src) case var lit?) {
      return BuiltInTy._get(lit);
    }

    return null;
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
  late final props = [literal, _constraints];

  @override
  LLVMTypeLit get llty => LLVMTypeLit(this);
}
