import 'package:characters/characters.dart';
import 'package:nop/nop.dart';

import 'lexers/token_kind.dart';
import 'token_it.dart';

bool isLF(String text) {
  return text == '\r\n' || text == '\n';
}

String parseStr(String str) {
  if (str.length < 2) {
    Log.e('parse str error: $str');
    return str;
  }

  if (str.startsWith('r')) {
    return str.substring(2, str.length - 1);
  }

  final buf = StringBuffer();
  var lastChar = '';

  final slice = str.substring(1, str.length - 1);
  final pattern = str.characters.last == "'" ? '"' : "'";
  final it = slice.characters.toList().tokenIt;
  bool? eatLn;

  void eatLine() {
    loop(it, () {
      final char = it.current;
      if (whiteSpaceChars.contains(char)) {
        return false;
      }
      it.moveBack();
      return true;
    });
  }

  loop(it, () {
    final char = it.current;

    // 两个反义符号
    if (lastChar == '\\') {
      switch (char) {
        case == 'u':
          var unicodeBuf = StringBuffer();

          if (it.moveNext()) {
            if (it.current != '{') {
              unicodeBuf.write(it.current);
              for (var i = 0; i < 3; i++) {
                if (it.moveNext()) {
                  unicodeBuf.write(it.current);
                }
              }
            } else {
              for (;;) {
                if (it.moveNext()) {
                  if (it.current == '}') break;
                  unicodeBuf.write(it.current);
                }
              }
            }
          }

          final v = int.tryParse(unicodeBuf.toString(), radix: 16);
          // max: 0x10FFFF
          if (v == null || v < 0 || v > 1114111) {
            Log.w('Invalid value: $unicodeBuf: [0..1114111]');
            break;
          }

          buf.write(String.fromCharCode(v));
        case == 'n':
          buf.write('\n');
        case == '\\':
          buf.write('\\');
        case var v when v == pattern:
          buf.write(pattern);
        case var v when isLF(v):
          if (eatLn != false) {
            eatLn = true;
            eatLine();
          }
      }

      lastChar = '';
      return false;
    }

    if (eatLn == null && isLF(char)) {
      eatLn = false;
    }

    if (eatLn == true && isLF(char)) {
      eatLine();
      lastChar = '';
    } else {
      lastChar = char;
      if (lastChar != '\\') buf.write(char);
    }

    return false;
  });
  return buf.toString();
}
