import 'token_kind.dart';

class TokenTree {
  TokenTree({required this.token, this.child = const []});
  final Token token;
  final List<TokenTree> child;
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

      if (token.kind == TokenKind.openBrace) {
        tokens.add(TokenTree(token: token));
        tokens.add(parse(true));
        continue;
      } else if (token.kind == TokenKind.closeBrace) {
        if (isDelimited) {
          return TokenTree(child: tokens, token: token);
        }
      }
      if (token.kind == TokenKind.eof) {
        return TokenTree(token: token, child: tokens);
      }
      if (token.kind == TokenKind.whiteSpace) continue;
      // if (token.kind == TokenKind.lf) continue;
      tokens.add(TokenTree(token: token));
    }
  }
}
