import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:test/test.dart';

void main() {
  test('token', () {
    final s = '''
fn main() int {
  let x: string = 1
}

啊发发发
"helloss 你啊"
struct Gen<T> {
  name: string,
  value: int,
}

''';
    final cursor = Cursor(s);
    final tokens = <Token>[];
    while (true) {
      final token = cursor.advanceToken();
      tokens.add(token);
      print(token);
      if (token.kind == TokenKind.eof) {
        break;
      }
    }
    for (var t in tokens) {
      if (t.kind == TokenKind.eof) continue;
      if (t.kind != TokenKind.unknown) continue;
      print('unknown:${s.substring(t.start, t.end)}');
    }
  });

  test('token reader', () {
    final src = r'''

"hello world
你好
"
fn main() int {
  let x: string = 11.1
  let haha: float = 10202.111
  let h: float = 10.e+10
  fn inner() {
    lex y: string = "1012\""
  }
}

啊发发发
"helloss 你啊"
llllsss
struct Gen<T> {
  name: string,
  value: int,
}''';
    final reader = TokenReader(src);
    final tree = reader.parse(false);
    forE(tree, src, isMain: true);
  });
}

void forE(TokenTree tree, String src, {int padWidth = 0, bool isMain = false}) {
  final token = tree.token;
  for (var token in tree.child) {
    forE(token, src, padWidth: padWidth + 2);
  }
  if (token != null) {
    final str = src.substring(token.start, token.end);

    print('${' ' * padWidth}$str  ->  $token');
  }
}
