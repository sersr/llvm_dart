import 'package:characters/characters.dart';

import 'lexers/token_kind.dart';
import 'token_it.dart';

bool isLF(String text) {
  return text == '\r\n' || text == '\n';
}

String parseStr(String str) {
  final buf = StringBuffer();
  var lastChar = '';
  final pattern = str.characters.first == "'" ? '"' : "'";
  final slice = str.substring(1, str.length - 1);
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
      if (char == pattern) {
        buf.write(pattern);
      } else if (char == 'n') {
        buf.write('\n');
      } else if (isLF(char)) {
        if (eatLn != false) {
          eatLn = true;
          eatLine();
        }
      } else if (char == '\\') {
        buf.write('\\');
      }
      lastChar = '';
      return false;
    }

    if (eatLn == null) {
      if (isLF(char)) {
        eatLn = false;
      }
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
