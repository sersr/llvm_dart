import 'package:characters/characters.dart';
import 'package:collection/collection.dart';

import '../token_it.dart';

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
  // shr('<<'),

  /// ">"
  gt('>'),
  // shl('>>'),

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

  /// "!"
  not('!'),

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

  bool get isOpen {
    return this == openBrace || this == openParen || this == openBracket;
  }

  bool get isClose {
    return this == closeBrace || this == closeParen || this == closeBracket;
  }

  final String char;
  const TokenKind(this.char);

  static Token? parse(
      String char,
      (int, int, int) Function(int start) getLineStart,
      int cursor,
      int cursorEnd) {
    final kind = values.firstWhereOrNull((e) {
      return e.char == char;
    });
    if (kind == null) return null;
    return Token(
        kind: kind, getLineStart: getLineStart, start: cursor, end: cursorEnd);
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
  kStr('str'),

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
  Token(
      {required this.kind,
      required this.start,
      (int, int, int) Function(int start)? getLineStart,
      int? lineStart,
      int? lineNumber,
      int? lineEnd,
      required this.end})
      : literalKind = null,
        lineStart = getLineStart?.call(start).$1 ?? lineStart!,
        lineNumber = getLineStart?.call(start).$3 ?? lineNumber ?? -1,
        lineEnd = getLineStart?.call(start).$2 ?? lineEnd ?? end;
  Token.literal({
    required LiteralKind this.literalKind,
    required this.start,
    (int, int, int) Function(int start)? getLineStart,
    int? lineStart,
    int? lineNumber,
    int? lineEnd,
    required this.end,
  })  : kind = TokenKind.literal,
        lineStart = getLineStart?.call(start).$1 ?? lineStart!,
        lineNumber = getLineStart?.call(start).$3 ?? lineNumber ?? -1,
        lineEnd = getLineStart?.call(start).$2 ?? lineEnd ?? end;

  final TokenKind kind;
  final int start;
  final int end;
  final int lineStart;
  final int lineEnd;
  final int lineNumber;
  final LiteralKind? literalKind;

  @override
  String toString() {
    final lit = literalKind == null ? '' : '$literalKind';
    return '[${start.toString().padLeft(5, '0')} - ${end.toString().padLeft(5, '0')}] ${kind.str} $lit';
  }
}

class Cursor {
  Cursor(this.src) {
    final pc = src.characters;
    _it = pc.toList().tokenIt;
    _state = _it.cursor;
    lineStartCursors;
  }

  void reset() {
    _state.restore();
    _lastLineNumber = 0;
  }

  final String src;

  late final CursorState _state;
  late BackIteratorString _it;

  int get cursor => _it.stringCursor;
  int get cursorEnd => _it.stringCursorEnd;

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

  List<int>? _lineStartCursors;

  List<int> get lineStartCursors => _lineStartCursors ??= _computedLFCursors();

  // ignore: constant_identifier_names
  static const _CR = '\r';
  // ignore: constant_identifier_names
  static const _LF = '\n';

  List<int> _computedLFCursors() {
    final cursors = <int>[0];
    final it = _it;
    final state = it.cursor;
    while (it.moveNext()) {
      final current = it.current;
      final firstCursor = it.stringCursor + 1;
      final nextIsLF = it.moveNext() ? it.current == _LF : false;
      if (current == _CR) {
        if (nextIsLF) {
          cursors.add(it.stringCursor + 1);
        } else {
          cursors.add(firstCursor);
        }
        continue;
      } else if (current == _LF) {
        cursors.add(firstCursor);
      }
      if (nextIsLF) {
        cursors.add(it.stringCursor + 1);
      }
    }
    // stringCursorEnd: 由于 cursor 并没有下移，所以要加上当前字符的长度
    cursors.add(it.stringCursorEnd + 1);
    state.restore();
    _max = cursors.length - 1;
    return cursors;
  }

  int _lastLineNumber = 0;
  var _max = 0;

  /// 获取当前指针所在行的数据信息
  ///
  /// [_lastLineNumber] : [key]的值只会递增，提供缓存可减少循环次数
  (int start, int end, int lineNumber) getLineStart(int key) {
    var nextIndex = _lastLineNumber + 1;
    final start = lineStartCursors[_lastLineNumber];
    final end = lineStartCursors[nextIndex];

    if (key >= start && key < end) {
      return (start, end - 1, _lastLineNumber + 1);
    }

    var index = nextIndex;
    while (index < _max) {
      final start = lineStartCursors[index];
      final end = lineStartCursors[index + 1];

      if (key >= start && key < end) {
        _lastLineNumber = index;
        return (start, end - 1, index + 1);
      }
      index += 1;
    }

    throw StateError('确保`key`是正向增长的，当前算法不支持获取`_lastLineNumber`之前的信息。');
  }

  Token advanceToken() {
    final char = nextChar;
    if (char.isEmpty) {
      return Token(
          kind: TokenKind.eof, lineStart: -1, start: cursor, end: cursorEnd);
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

    if (rawNumbers.contains(char)) {
      return number();
    }
    if (char == "'" || char == '"') {
      final start = cursor;
      _eatStr(char);
      return Token.literal(
        literalKind: LiteralKind.kStr,
        getLineStart: getLineStart,
        start: start,
        end: cursorEnd,
      );
    }

    final tk = TokenKind.parse(char, getLineStart, cursor, cursorEnd);
    if (tk != null) return tk;

    if (isIdent(char)) {
      return ident();
    }
    return Token(
        kind: TokenKind.unknown,
        getLineStart: getLineStart,
        start: cursor,
        end: cursorEnd);
  }

  Token? comment() {
    assert(current == '/');
    final start = cursor;
    if (nextCharRead == '/') {
      eatLine();
      return Token(
          kind: TokenKind.lineCommnet,
          getLineStart: getLineStart,
          start: start,
          end: cursorEnd);
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
      return Token(
          kind: TokenKind.blockComment,
          getLineStart: getLineStart,
          start: start,
          end: cursorEnd);
    }
    return null;
  }

  /// a-z A-Z _ $
  bool isIdent(String char, {bool supportNum = false}) {
    if (char.codeUnits case [int unit]) {
      return unit > 0x7F ||
          unit >= 0x61 && unit <= 0x7A || // a-z
          unit >= 0x41 && unit <= 0x5A || // A-Z
          unit == 0x5F || // _
          unit == 0x24 || // $
          supportNum && // 0-9
              unit >= 0x30 &&
              unit <= 0x39;
    }
    return char.isNotEmpty;
  }

  Token ident() {
    final start = cursor;
    loop((char) {
      if (!whiteSpaceChars.contains(char) && isIdent(char, supportNum: true)) {
        assert(TokenKind.parse(char, getLineStart, cursor, cursorEnd) == null);
        return false;
      }
      return true;
    });

    return Token(
        kind: TokenKind.ident,
        getLineStart: getLineStart,
        start: start,
        end: cursorEnd);
  }

  Token whiteSpace() {
    final start = cursor;
    loop((char) {
      return !whiteSpaceChars.contains(char);
    });
    return Token(
        kind: TokenKind.whiteSpace,
        getLineStart: getLineStart,
        start: start,
        end: cursorEnd);
  }

  void _eatStr(String pattern) {
    assert(pattern == '"' || pattern == "'");
    var lastChar = '';
    // 字符串自带结尾
    loop(back: false, (char) {
      // if (char == '"') return true;
      if (lastChar != '\\' && char == pattern) return true;

      // 两个反义符号
      if (lastChar == '\\' && char == '\\') {
        lastChar = '';
        return false;
      }
      lastChar = char;

      return false;
    });
  }

  Token number() {
    final start = cursor;
    var isFloat = true;
    if (current == '0') {
      final n = nextCharRead;
      if (n == 'x' || n == 'b' || n == 'o') {
        isFloat = false;
        nextChar;
      }
    }
    eatNumberLiteral();
    final state = _it.cursor;
    if (isFloat) {
      isFloat = nextCharRead == '.';
    }
    if (isFloat) {
      nextChar;
      if (!numbers.contains(nextCharRead)) {
        state.restore();
        isFloat = false;
      }
    }
    if (isFloat) {
      eatNumberLiteral();
      if (nextCharRead == 'E' || nextCharRead == 'e') {
        nextChar;
        if (nextCharRead == '-' || nextCharRead == '+') {
          nextChar;
          eatNumberLiteral();
        }
        final c = cursorEnd;
        final k = getLitKind() ?? LiteralKind.f64;

        return Token.literal(
            literalKind: k, getLineStart: getLineStart, start: start, end: c);
      }
    }

    final end = cursorEnd;
    LiteralKind lkd =
        getLitKind() ?? (isFloat ? LiteralKind.f32 : LiteralKind.i32);

    return Token.literal(
        literalKind: lkd, getLineStart: getLineStart, start: start, end: end);
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
    while (_it.moveNext()) {
      final next = _it.current;
      if (test(next)) {
        if (back) _it.moveBack();
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
