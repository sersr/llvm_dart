import 'package:llvm_dart/parsers/base.dart';

import '../ast/ast.dart';
import 'global.dart';

mixin ParseStmt on ParserGlobals, ParseExpr, ParseVariable {
  Stmt? parseStmt() {
    final b = StringBuffer();
    Token? token;
    Stmt? stmt;
    loop((char) {
      if (b.isEmpty && char == '}') {
        // `}` 字符不属于`Stmt`处理范围
        moveBack();
        return true;
      }
      if (stmtKey.hasMatch(char)) {
        b.write(char);
      } else {
        final text = b.toString().trim();
        if (text.isEmpty) return false;
        if (text == 'let') {
          token = Token.let;
          b.clear();
          stmt = parseLet();
          return true;
        } else {
          if (char == '(') {
            token = Token.fnCall;
            b.clear();
            stmt = parseFunctionCall(text);
            return true;
          } else {
            // 变量引用
            if (stringAllReg.hasMatch(text)) {
              moveBack();
              b.clear();
              stmt = ValueExpr(BuiltinTypeAst(BuiltinType.kString), text);
              return true;
            } else if (numberReg.hasMatch(text)) {
              moveBack();
              b.clear();
              stmt = ValueExpr(BuiltinTypeAst(BuiltinType.kDouble), text);
              return true;
            } else if (stmtKey.hasMatch(text)) {
              return true;
            }
          }
        }
      }
      return false;
    });
    return stmt;
  }

  Stmt? parseCall() {
    Stmt? stmt;
    final b = StringBuffer();
    loop((char) {
      if (b.isEmpty && whiteSpace.hasMatch(char)) return false;

      if (b.isEmpty && char == '.') {}
      return false;
    });
    return stmt;
  }

  AssignStmt? parseLet() {
    final b = StringBuffer();
    var name = '', type = '';
    Expr? expr;
    loop((char) {
      if (b.isEmpty && whiteSpace.hasMatch(char)) return false;
      if (char == ':') {
        name = b.toString().trim();
        b.clear();
        return false;
      }
      if (char == '=') {
        expr = paserExpr();
        return true;
      }
      b.write(char);
      return false;
    });

    if (name.isEmpty) {
      name = b.toString().trim();
    }
    final ty = BuiltinTypeAst.parse(type);

    if (expr != null) {
      return AssignStmt(name, ty, expr!, AssignOperand.eq);
    }
    return null;
  }
}
