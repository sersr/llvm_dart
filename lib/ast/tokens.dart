enum BinOpToken {
  plus, // +
  minus, // -
  star, // *
  slash, // /
  percent, // %
  caret, // ^
  and, // &
  or, // |
  shl, // <<
  shr, // >>
}

enum TokenKind {
  eq('='),
  lt('<'),
  le('<='),
  eqEq('=='), // ==
  ne('!='), // !=
  ge('>='), // >=
  gt('>'), // >
  andAnd('&&'), // &&
  orOr('||'), // ||
  tilde('~'), // ~

  // 二进制
  plus('+'), // +
  minus('-'), // -
  star('*'), // *
  slash('/'), // /
  percent('%'), // %
  caret('^'), // ^
  and('&'), // &
  or('|'), // |
  shl('<<'), // <<
  shr('>>'), // >>

  dot('.'), // .
  at('@'), // @
  comma(','), // ,
  dollar('\$'), // $
  colon(':'), //

  /// "//"
  lineCommnet(''),

  /// "///"
  blockComment(''),

  /// keys or identifiers
  ident(''),

  unknownIdent(''),

  /// " "
  whiteSpace(''),

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

  /// "#"
  pound('#'),

  /// "?"
  question('?'),

  /// ->
  rArrow('->'),
  lArrow('<-'),

  unknown(''),

  /// end
  eof(''),
  ;

  String get str {
    if (char.isEmpty) return toString();
    return '${toString()} "$char"';
  }

  final String char;
  const TokenKind(this.char);

  // static Token? parse(String char, int cursor) {
  //   final kind = values.firstWhereOrNull((e) {
  //     return e.char == char;
  //   });
  //   if (kind == null) return null;
  //   return Token(kind: kind, start: cursor);
  // }
}
