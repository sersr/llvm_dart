import 'package:llvm_dart/ast/ast.dart';
import 'package:llvm_dart/parsers/base.dart';
import 'package:llvm_dart/parsers/parse_stmt.dart';

import 'global.dart';
import 'parse_block.dart';

class Module {
  final List<FunctionAst> function = [];
  final List<TypeAst> elements = [];
}

class Parser
    with
        ParserGlobals,
        ParseExpr,
        ParseVariable,
        ParseStmt,
        ParseBlock,
        ParseFunction,
        ParseStruct {
  Parser(String src) {
    init(src);
  }

  void parse() {
    final buf = StringBuffer();
    Token? token;
    loop((char) {
      if (langKey.hasMatch(char)) {
        buf.write(char);
      } else {
        final text = buf.toString();
        buf.clear();
        if (text == Token.static.token) {
          token = Token.static;
          parseStaticVariable();
        }
        if (char == ',' && token == Token.static) {
          parseStaticVariable();
        }
        if (text == 'fn') {
          token = Token.fn;
          parseFunction();
        } else if (text == 'struct') {
          token = Token.struct;
          parseStruct();
        }
      }
      return false;
    });
  }
}

final langKey = RegExp(r'[a-zA-Z]');

final whiteSpace = RegExp(r'[ \n\r]+');
final whiteReg = RegExp(r' +');

final stringQutReg = RegExp('["\']');
final stringReg = RegExp(r'\w+');
// final stringReg = RegExp('(["\']|[(?:""")(?:\'\'\')][.*]["\']|[(?:""")(?:\'\'\')])',multiLine: true);

final variableReg = RegExp(r'[_a-zA-Z]+\w*');
final words = RegExp(r'[_\w]+');
final numberReg = RegExp(r'[\.0-9_]+');
final structInitReg = RegExp(r'[ \n]*(\w+) *{');
final fnNameReg = RegExp(r'\(');
