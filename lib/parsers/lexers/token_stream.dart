import 'token_kind.dart';

class TokenTree {
  TokenTree({required this.token, this.child = const []});

  ///open token: (, [, {, <
  final Token token;
  final List<TokenTree> child;

  /// close token: ), ], }, >
  Token? end;
}

class TokenReader {
  TokenReader(this.src) {
    init();
  }
  final String src;
  late Cursor cursor;
  void init() {
    cursor = Cursor(src);
  }

  TokenTree parse(bool isDelimited) {
    final tokens = <TokenTree>[];
    while (true) {
      final token = cursor.advanceToken();

      if (token.kind.isOpen) {
        final child = parse(true);
        final tree = TokenTree(child: child.child, token: token)
          ..end = child.token;
        tokens.add(tree);
        continue;
      } else if (token.kind.isClose) {
        if (isDelimited) {
          return TokenTree(child: tokens, token: token);
        }
      }
      if (token.kind == TokenKind.eof) {
        return TokenTree(token: token, child: tokens);
      }
      if (token.kind == TokenKind.whiteSpace) continue;
      if (token.kind == TokenKind.lineCommnet) continue;
      if (token.kind == TokenKind.blockComment) continue;
      // if (token.kind == TokenKind.lf) continue;
      tokens.add(TokenTree(token: token));
    }
  }
}
