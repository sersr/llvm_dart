import 'package:characters/characters.dart';
import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/fs/fs.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:llvm_dart/parsers/token_it.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

void main() {
  test('cursor', () {
    final cursor = Cursor("hello");
    final char = cursor.nextChar;
    expect(char, 'h');
    expect(cursor.cursor, 0);
    cursor.moveBack();
    expect(cursor.cursor, -1);
  });

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

  test('cursor all', () {
    final cursor = Cursor("hello");
    // final char = cursor.nextChar;
    cursor
          ..nextChar // 'h'
          ..nextChar // 'e'
          ..nextChar // 'l'
          ..nextChar // 'l'
          ..nextChar // 'o'
          ..nextChar // '', EOF
        ;
    expect(cursor.cursor, 4);
    cursor.moveBack(); // 'h'

    expect(cursor.cursor, 3);
    expect(cursor.current, 'l');
    cursor
          ..moveBack() // 'l'
          ..moveBack() // 'e'
          ..moveBack() // 'h'
        ;
    expect(cursor.cursor, 0);
    cursor.moveBack(); // ''
    expect(cursor.cursor, -1);
    cursor.moveBack(); // ''
    expect(cursor.cursor, -1);
  });

  test('light', () {
    final src = testSrcDir.childFile('math.kc').readAsStringSync();
    Log.logPathFn = (path) => path;
    final tokenReader = TokenReader(src);

    final tree = tokenReader.parse(false);
    void loop(TokenTree tree) {
      if (tree.child.isNotEmpty) {
        for (var token in tree.child) {
          loop(token);
        }
      }
      final ident = Identifier.fromToken(tree.token, src);
      Log.i('${ident.light} ${ident.offset.pathStyle}');
    }

    loop(tree);

    final cursor = Cursor(src);

    final list = cursor.lineStartCursors;

    int? start;
    for (var index in list) {
      if (start == null) {
        start = index;
        continue;
      }

      final token = Token(
          kind: TokenKind.ident,
          getLineStart: cursor.getLineStart,
          start: start,
          end: index - 1);
      final ident = Identifier.fromToken(token, src);
      start = index;
      Log.i(
          '${ident.light} | ${token.start} <= ${token.lineStart} <= ${token.end}'
          ' <= ${token.lineEnd} | ${ident.offset}');
    }
  });
}
