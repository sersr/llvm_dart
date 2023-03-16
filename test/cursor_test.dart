import 'package:llvm_dart/parsers/lexers/token_kind.dart';
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
}
