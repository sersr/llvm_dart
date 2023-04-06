import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:llvm_dart/parsers/token_it.dart';

enum TokenKind {
  /// "//"
  lineCommnet(''),

  /// "///", "/* */"
  blockComment(''),

  /// keys or identifiers
  ident(''),

  unknownIdent(''),

  /// " "
  whiteSpace(''),

  /// '\n'
  lf('\n'),

  /// string, number
  literal(''),

  /// "("
  openParen('('),

  /// ")"
  closeParen(')'),

  /// "{"
  openBrace('{'),

  /// "}"
  closeBrace('}'),

  /// "["
  openBracket('['),

  /// "]"
  closeBracket(']'),

  /// ";"
  semi(';'),

  /// ","
  comma(','),

  /// "."
  dot('.'),

  /// "$"
  dollar('\$'),

  /// "<"
  lt('<'),
  shr('<<'),

  /// ">"
  gt('>'),
  shl('>>'),

  /// "="
  eq('='),

  /// "|"
  or('|'),

  /// "+"
  plus('+'),

  /// "-",
  minus('-'),

  /// "&"
  and('&'),

  /// "*",
  star('*'),

  /// "/"
  div('/'),

  /// "\"
  slash('\\'),

  /// ":"
  colon(":"),

  /// "^"
  caret('^'),

  /// "%"
  percent('%'),

  /// "@"
  at('@'),

  /// "#"
  pound('#'),

  /// "~"
  tilde('~'),

  /// "?"
  question('?'),

  unknown(''),

  /// end
  eof(''),
  ;

  String get str {
    if (char.isEmpty) return toString();
    if (this == lf) {
      return '${toString()} "\\n"';
    }
    return '${toString()} "$char"';
  }

  final String char;
  const TokenKind(this.char);

  static Token? parse(String char, int cursor) {
    final kind = values.firstWhereOrNull((e) {
      return e.char == char;
    });
    if (kind == null) return null;
    return Token(kind: kind, start: cursor);
  }
}

const whiteSpaceChars = [
  '\u{0009}', // \t
  // '\u{000A}', // \n
  '\u{000B}', // vertical tab
  '\u{000C}', // form feed
  '\u{000D}', // \r
  '\u{0020}', // space

  // NEXT LINE from latin1
  '\u{0085}',

  // Bidi markers
  '\u{200E}', // LEFT-TO-RIGHT MARK
  '\u{200F}', // RIGHT-TO-LEFT MARK

  // Dedicated whitespace characters from Unicode
  '\u{2028}', // LINE SEPARATOR
  '\u{2029}', // PARAGRAPH SEPARATOR
];

enum LiteralKind {
  kFloat('float'),
  kDouble('double'),
  f32('f32'),
  f64('f64'),
  kInt('int'),
  kString('string'),

  i8('i8'),
  i16('i16'),
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

  static int? _max;
  static int get max {
    if (_max != null) return _max!;
    return _max = values.fold<int>(0, (previousValue, element) {
      if (previousValue > element.lit.length) {
        return previousValue;
      }
      return element.lit.length;
    });
  }

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

  bool get signed {
    assert(isInt);
    if (index >= i8.index && index <= i128.index) {
      return true;
    }
    return false;
  }

  final String lit;
  const LiteralKind(this.lit);
}

class Token {
  Token({required this.kind, required this.start, int? end})
      : literalKind = null,
        end = (end ?? start) + 1;
  Token.literal({
    required LiteralKind this.literalKind,
    required this.start,
    required int end,
  })  : end = end + 1,
        kind = TokenKind.literal;

  final TokenKind kind;
  final int start;
  final int end;
  final LiteralKind? literalKind;

  @override
  String toString() {
    final lit = literalKind == null ? '' : '$literalKind';
    return '[${start.toString().padLeft(5, '0')} - ${end.toString().padLeft(5, '0')}] ${kind.str} $lit';
  }
}

class Cursor {
  Cursor(this.src) {
    _reset();
  }
  void _reset() {
    final pc = src.characters;
    _it = pc.toList().tokenIt;
  }

  final String src;

  late BackIterator<String> _it;

  int get cursor => _it.cursor.cursor;

  void moveBack() {
    _it.moveBack();
  }

  String get current {
    if (!_it.curentIsValid) return '';
    return _it.current;
  }

  String get nextChar {
    if (_it.moveNext()) {
      return _it.current;
    }
    return '';
  }

  // 不移动光标
  String get nextCharRead {
    if (_it.moveNext()) {
      final current = _it.current;
      _it.moveBack();
      return current;
    }
    return '';
  }

  final idenStartKey = RegExp('[a-zA-Z_]');
  final idenKey = RegExp('[a-zA-Z_0-9]');

  Token advanceToken() {
    final char = nextChar;
    if (char.isEmpty) {
      return Token(kind: TokenKind.eof, start: cursor);
    }
    if (whiteSpaceChars.contains(char)) {
      return whiteSpace();
    }

    if (char == '/') {
      final t = comment();
      if (t != null) {
        return t;
      }
    }
    if (idenStartKey.hasMatch(char)) {
      return ident();
    }

    if (rawNumbers.contains(char)) {
      return number();
    }
    if (char == '\'') {
      return singleQuotedString();
    } else if (char == '"') {
      return doubleQuotedString();
    }

    if (char == '>' && nextCharRead == '>') {
      final start = cursor;
      nextChar;
      return Token(kind: TokenKind.shl, start: start, end: cursor);
    }

    if (char == '<' && nextCharRead == '<') {
      final start = cursor;
      nextChar;
      return Token(kind: TokenKind.shr, start: start, end: cursor);
    }
    final tk = TokenKind.parse(char, cursor);
    if (tk != null) return tk;

    return Token(kind: TokenKind.unknown, start: cursor);
  }

  Token? comment() {
    assert(current == '/');
    final start = cursor;
    if (nextCharRead == '/') {
      eatLine();
      return Token(kind: TokenKind.lineCommnet, start: start, end: cursor);
    }
    if (nextCharRead == '*') {
      String preChar = '';
      loop((char) {
        if (preChar == '*' && char == '/') {
          return true;
        }
        preChar = char;
        return false;
      }, back: false);
      return Token(kind: TokenKind.blockComment, start: start, end: cursor);
    }
    return null;
  }

  Token ident() {
    final start = cursor;
    loop((char) {
      if (idenKey.hasMatch(char)) {
        return false;
      }
      return true;
    });
    return Token(kind: TokenKind.ident, start: start, end: cursor);
  }

  Token whiteSpace() {
    final start = cursor;
    loop((char) {
      return !whiteSpaceChars.contains(char);
    });
    return Token(kind: TokenKind.whiteSpace, start: start, end: cursor);
  }

  Token singleQuotedString() {
    final start = cursor;

    var lastChar = '';
    // 字符串自带结尾
    loop(back: false, (char) {
      if (lastChar != '\\' && char == "'") return true;

      // 两个反义符号
      if (lastChar == '\\' && char == '\\') {
        lastChar = '';
        return false;
      }
      lastChar = char;

      return false;
    });
    return Token.literal(
        literalKind: LiteralKind.kString, start: start, end: cursor);
  }

  Token doubleQuotedString() {
    final start = cursor;

    var lastChar = '';
    // 字符串自带结尾
    loop(back: false, (char) {
      // if (char == '"') return true;
      if (lastChar != '\\' && char == '"') return true;

      // 两个反义符号
      if (lastChar == '\\' && char == '\\') {
        lastChar = '';
        return false;
      }
      lastChar = char;

      // if(whiteSpaceChars.contains(char)) return true;
      return false;
    });

    return Token.literal(
        literalKind: LiteralKind.kString, start: start, end: cursor);
  }

  Token number() {
    final start = cursor;
    eatNumberLiteral();
    final isFloat = nextCharRead == '.';
    if (isFloat) {
      nextChar;
      eatNumberLiteral();
      if (nextCharRead == 'E' || nextCharRead == 'e') {
        nextChar;
        if (nextCharRead == '-' || nextCharRead == '+') {
          nextChar;
          eatNumberLiteral();
        }
      }
      final c = cursor;
      final k = getLitKind() ?? LiteralKind.kDouble;

      return Token.literal(literalKind: k, start: start, end: c);
    }

    final end = cursor;
    LiteralKind lkd = getLitKind() ?? LiteralKind.kInt;

    return Token.literal(literalKind: lkd, start: start, end: end);
  }

  LiteralKind? getLitKind() {
    var allChar = '';
    LiteralKind? k;
    final state = _it.cursor;
    loop((char) {
      allChar = '$allChar$char';
      if (allChar.length > LiteralKind.max) {
        return true;
      }
      final lit = LiteralKind.values
          .firstWhereOrNull((element) => element.lit == allChar);
      if (lit != null) {
        k = lit;
        return true;
      }
      return false;
    }, back: false);

    if (k == null) {
      state.restore();
    }

    return k;
  }

  void eatNumberLiteral() {
    loop((char) {
      if (rawNumbers.contains(char)) return false;
      if (char == '_') return false;
      return true;
    });
  }

  void eatLine() {
    loop((char) {
      if (char == '\n') return true;
      return false;
    });
  }

  void loop(bool Function(String char) test, {bool back = true}) {
    while (true) {
      final next = nextChar;
      if (next.isEmpty) return;
      if (test(next)) {
        if (back) moveBack();
        return;
      }
    }
  }
}

List<String>? _numbers;
final List<String> rawNumbers =
    List.generate(10, (index) => '$index', growable: false);

List<String> floats = ['.'];
List<String> get numbers {
  if (_numbers != null) return _numbers!;
  final n = rawNumbers.toList();
  n.add('_');
  n.add('.');
  n.add('E');
  n.add('e');
  return _numbers = n;
}
