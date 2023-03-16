import 'package:characters/characters.dart';

import '../ast/ast.dart';

enum Token {
  eof('eof'), // 结尾
  fn('fn'),
  static('static'),
  struct('struct'),
  fnCall('fnCall'),
  varRef('varRef'),
  let('let');

  final String token;
  const Token(this.token);
}

mixin ParserGlobals {
  final globalVar = <AssignStmt>[];
  final globalStruct = <String, StructAst>{};
  final globalStructNamed = <String, StructAst>{};
  final globalFnCall = <String, FunctionAst>{};
  final globalFunction = <String, FunctionAst>{};

  late CharacterRange _it;

  void init(String src) {
    _it = src.characters.iterator;
    _cursor = -1;
  }

  var _cursor = -1;

  int get cursor => _cursor;

  void moveBack() {
    if (_it.moveBack()) {
      _cursor -= 1;
    }
  }

  String get current => _it.current;

  void loop(bool Function(String char) action) {
    while (_it.moveNext()) {
      _cursor += 1;
      if (action(_it.current)) return;
    }
  }
}
