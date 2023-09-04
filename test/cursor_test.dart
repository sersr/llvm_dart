import 'package:characters/characters.dart';
import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:llvm_dart/parsers/token_it.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

void main() {
  test('cursor 😯', () {
    const raw = "let 😯";
    final cursor = raw.characters.toList().tokenIt;
    while (cursor.moveNext()) {
      print(cursor.stringCursor);
      print(cursor.stringCursorEnd);
      print(
          'string:${cursor.current}|${raw.substring(cursor.stringCursor, cursor.stringCursorEnd)}|');
    }
  });

  test('light', () {
    final src = testSrcDir.childFile('math.kc').readAsStringSync();
    Log.logPathFn = (path) => path;
    final tokenReader = TokenReader(src);

    void test() {
      final tree = tokenReader.parse(false);
      void loop(TokenTree tree) {
        if (tree.child.isNotEmpty) {
          for (var token in tree.child) {
            loop(token);
          }
        }
        final ident = Identifier.fromToken(tree.token, src);
        Log.i(
            '${ident.light} | ${ident.lineStart} <= ${ident.start} <= ${ident.end} ?? ${ident.lineEnd} | ${ident.offset.pathStyle}');
      }

      loop(tree);
    }

    test();

    final cursor = Cursor(src);

    final list = cursor.lineStartCursors;

    int? start;
    for (var i = 0; i < list.length; i++) {
      final index = list[i];
      if (start == null) {
        start = index;
        continue;
      }

      final token = Token(
        kind: TokenKind.ident,
        start: start,
        lineStart: start,
        lineNumber: i + 1,
        lineEnd: index - 1,
        end: index,
      );
      final ident = Identifier.fromToken(token, src);
      start = index;
      Log.i(
          '${ident.light} | ${token.lineStart} <= ${token.start} <= ${token.end}'
          ' ?? ${token.lineEnd} | ${ident.offset.pathStyle}');
    }
  });
}
