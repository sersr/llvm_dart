import 'package:characters/characters.dart';
import 'package:collection/collection.dart';

enum TokenKind {
  /// "//"
  lineCommnet(''),

  /// "///"
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

  /// ">"
  gt('>'),

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
  kInt,
  kFloat,
  kDouble,

  kString,
  kVoid,
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
    _it = pc.iterator;
    _cursor = -1;
    _len = src.length;
  }

  final String src;

  late CharacterRange _it;

  int _len = 0;
  int _cursor = -1;
  int get cursor => _cursor;

  void moveBack() {
    if (_cursor <= -1) return;
    _cursor -= _it.current.length;
    _it.moveBack();
  }

  String get current {
    if (_cursor <= -1) return '';
    return _it.current;
  }

  String get nextChar {
    if (_cursor >= _len) return '';
    if (_cursor <= -1) {
      _cursor = 0;
    } else {
      final cursor = _cursor + _it.current.length;
      if (cursor < _len) {
        _cursor = cursor;
      } else {
        return '';
      }
    }

    _it.moveNext();
    final char = _it.current;
    return char;
  }

  // 不移动光标
  String get nextCharRead {
    if (_cursor >= _len) return '';
    final cursor = _cursor + _it.current.length;
    if (cursor >= _len) {
      return '';
    }

    _it.moveNext();
    final char = _it.current;
    _it.moveBack();
    return char;
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

    final tk = TokenKind.parse(char, cursor);
    if (tk != null) return tk;

    return Token(kind: TokenKind.unknown, start: cursor);
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
      return Token.literal(
          literalKind: LiteralKind.kFloat, start: start, end: cursor);
    }

    return Token.literal(
        literalKind: LiteralKind.kInt, start: start, end: cursor);
  }

  void eatNumberLiteral() {
    loop((char) {
      if (rawNumbers.contains(char)) return false;
      if (char == '_') return false;
      return true;
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
