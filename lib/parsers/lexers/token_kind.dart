import 'package:characters/characters.dart';
import 'package:collection/collection.dart';

import '../../ast/ast.dart';
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

  void back() {
    _it.moveBack();
  }

  List<int>? _lineStartCursors;

  List<int> get lineStartCursors => _lineStartCursors ??= _computedLFCursors();

  List<int> _computedLFCursors() {
    final cursors = <int>[0];
    final it = _it;
    final state = it.cursor;
    while (it.moveNext()) {
      final current = it.current;
      if (current == '\n' || current == '\r\n') {
        cursors.add(it.stringCursorEnd);
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

    if (char == '\r\n') {
      final start = cursor;
      return Token(
          kind: TokenKind.lf,
          getLineStart: getLineStart,
          start: start,
          end: cursorEnd);
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

    var str = char;

    bool isRawStr = false;

    if (str == 'r') {
      isRawStr = true;
      str = nextCharRead;
    }

    if (str == "'" || str == '"') {
      final start = cursor;
      if (isRawStr) nextChar;
      _eatStr(str);
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
    return char != '\r\n' && char.isNotEmpty;
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
    var isXRadix = false;
    if (current == '0') {
      final n = nextCharRead;
      if (n == 'x' || n == 'b' || n == 'o') {
        isFloat = false;
        isXRadix = n == 'x';
        nextChar;
      }
    }
    eatNumberLiteral(isXRadix);

    isFloat &= nextCharRead == '.';

    if (isFloat) {
      nextChar;
      isFloat = numbers.contains(nextCharRead);
      if (!isFloat) {
        back();
      } else {
        eatNumberLiteral(isXRadix);
        if(!isXRadix) {
          if (nextCharRead == 'E' || nextCharRead == 'e') {
          nextChar;
          if (nextCharRead == '-' || nextCharRead == '+') {
            nextChar;
            eatNumberLiteral(false);
          }
        }
        }
      }
    }

    final end = cursorEnd;
    LiteralKind lkd =
        getLitKind() ?? (isFloat ? LiteralKind.f64 : LiteralKind.i32);

    return Token.literal(
        literalKind: lkd, getLineStart: getLineStart, start: start, end: end);
  }

  LiteralKind? getLitKind() {
    var allChar = '';
    LiteralKind? k;
    final state = _it.cursor;
    loop((char) {
      allChar = '$allChar$char';
      final lit = LiteralKind.from(allChar);
      if (lit != null) {
        k = lit;
        return true;
      }
      if (allChar.length > LiteralKind.max) {
        return true;
      }
      return false;
    }, back: false);

    if (k == null) {
      state.restore();
    }

    return k;
  }

  void eatNumberLiteral(bool isXRadix) {
    loop((char) {
      if (rawNumbers.contains(char)) return false;
      if (isXRadix && _radixList.contains(char.toLowerCase())) return false;
      if (char == '_') return false;
      return true;
    });
  }

  void eatLine() {
    loop((char) {
      if (char == '\n' || char == '\r\n') return true;
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
final _radixList = ['a','b','c','d','e','f'];
List<String> get numbers {
  if (_numbers != null) return _numbers!;
  final n = rawNumbers.toList();
  n.add('_');
  n.add('.');
  n.add('E');
  n.add('e');
  return _numbers = n;
}
