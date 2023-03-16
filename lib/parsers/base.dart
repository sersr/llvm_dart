import '../ast/ast.dart';
import 'global.dart';
import 'parse_block.dart';

final stmtKey = RegExp('[a-zA-Z_0-9\'"]');

final whiteSpace = RegExp(r'[ \n\r]+');
final whiteReg = RegExp(r' +');

final stringQutReg = RegExp('["\']');
final stringReg = RegExp(r'\w+');
final stringAllReg = RegExp('[\'"]+\\w*?[\'"]+');
// final stringReg = RegExp('(["\']|[(?:""")(?:\'\'\')][.*]["\']|[(?:""")(?:\'\'\')])',multiLine: true);

final variableReg = RegExp(r'[_a-zA-Z]+\w*');
final words = RegExp(r'[_\w]+');
final numberReg = RegExp(r'[\.0-9_]+');
final structInitReg = RegExp(r'[ \n]*(\w+) *{', multiLine: true);
final fnNameReg = RegExp(r'\(');
final fnCallReg = RegExp(r'[ \n]*(\w+)[ \n]*\(', multiLine: true);
mixin ParseExpr on ParserGlobals {
  Expr? paserExpr() {
    Expr? expr;
    final b = StringBuffer();
    loop((char) {
      if (whiteSpace.hasMatch(char)) return false;

      if (stringQutReg.hasMatch(char)) {
        expr = parseString();
      } else if (numberReg.hasMatch(char)) {
        moveBack();
        expr = parseNumber();
      } else {
        if (b.isEmpty && char == ',') return true;
        b.write(char);
        final text = b.toString();
        final stru = structInitReg.firstMatch(text);
        if (stru != null) {
          expr = parseStructInit(stru[1] ?? '');
          return true;
        }

        return false;
      }
      return true;
    });
    return expr;
  }

  Expr? parseNumber() {
    final b = StringBuffer();
    loop((char) {
      if (numberReg.hasMatch(char)) {
        b.write(char);
        return false;
      }
      // 需要回到上一个位置
      moveBack();
      return true;
    });
    if (b.isNotEmpty) {
      return ValueExpr(BuiltinTypeAst(BuiltinType.kDouble), b.toString());
    }
    return null;
  }

  Expr? parseString() {
    final b = StringBuffer();
    var ignore = false;
    loop((char) {
      if (whiteSpace.hasMatch(char)) {
        return false;
      }
      if (stringQutReg.hasMatch(char)) {
        if (!ignore) return true;
      }
      b.write(char);
      final e = char == r'\';
      if (ignore == true && e) {
        ignore = false;
      } else {
        ignore = e;
      }
      return false;
    });
    return ValueExpr(BuiltinTypeAst(BuiltinType.kString), b.toString());
  }

  Expr? parseStructInit(String name) {
    final struct =
        globalStructNamed.putIfAbsent(name, () => StructAst(name, []));
    final params = <Expr>[];
    loop((char) {
      if (whiteSpace.hasMatch(char)) return false;
      if (char == "}") return true;
      moveBack();
      final expr = paserExpr();
      if (expr != null) params.add(expr);
      return false;
    });

    return StructInitExpr(struct, params);
  }

  Stmt? parseFunctionCall(String name) {
    final params = <Expr>[];
    loop((char) {
      if (whiteSpace.hasMatch(char)) return false;
      if (char == ")") return true;
      moveBack();
      final expr = paserExpr();
      if (expr != null) params.add(expr);
      return false;
    });

    var function = globalFunction[name] ??
        globalFnCall.putIfAbsent(
            name, () => FunctionAst(name, [], Block([]), VoidTypeAst()));

    final fnCall = FunctionCallExpr(function, params);
    return VoidExprStmt(fnCall);
  }
}

mixin ParseVariable on ParserGlobals, ParseExpr {
  (String, TypeAst?, AssignOperand, Expr)? parserVariable() {
    final b = StringBuffer();
    const op = ['+', '-', '*', '/', '%', '='];
    final opBuf = StringBuffer();
    loop((char) {
      if (op.contains(char)) {
        opBuf.write(char);
        return true;
      }
      if (whiteSpace.hasMatch(char)) return false;
      b.write(char);
      return false;
    });
    loop((char) {
      if (!op.contains(char)) {
        moveBack();
        return true;
      }
      opBuf.write(char);
      return false;
    });

    final expr = paserExpr();
    if (expr == null) return null;
    final name = b.toString().trim();
    final operand =
        AssignOperand.parse(opBuf.toString().trim()) ?? AssignOperand.eq;
    return (name, null, operand, expr);
  }

  void parseStaticVariable() {
    final record = parserVariable();
    if (record != null) {
      var (name, type, op, expr) = record;
      final static = AssignStmt(name, type, expr, op);
      globalVar.add(static);
    }
  }

  AssignStmt? parseAssignVariable() {
    final record = parserVariable();
    if (record != null) {
      var (name, type, op, expr) = record;
      return AssignStmt(name, type, expr, op);
    }
    return null;
  }

  LetStmt? parseLetVariable() {
    final record = parserVariable();
    if (record != null) {
      var (name, type, _, expr) = record;
      return LetStmt(name, type, expr);
    }
    return null;
  }
}

mixin ParseFunction on ParserGlobals, ParseBlock {
  void parseFunction() {
    final b = StringBuffer();
    loop((char) {
      if (whiteSpace.hasMatch(char) && b.isEmpty) return false;
      if (fnNameReg.hasMatch(char)) {
        return true;
      }
      b.write(char);
      return false;
    });

    final params = parseFunctionParams();
    final returnType = parseFunctionReturnType() ?? VoidTypeAst();
    final block = parseBlock();
    final name = b.toString().trim();
    var fn = globalFnCall.remove(name);
    if (fn != null) {
      fn.params.addAll(params);
      fn.block.stmts.addAll(block.stmts);
      fn.returnType = returnType;
    } else {
      fn = FunctionAst(name, params, block, returnType);
    }
    globalFunction[name] = fn;
  }

  TypeAst? parseFunctionReturnType() {
    final b = StringBuffer();
    loop((char) {
      if (whiteSpace.hasMatch(char)) return false;
      if (char == '{') return true;
      b.write(char);
      return false;
    });
    final text = b.toString();
    return BuiltinTypeAst.parse(text);
  }

  List<ParamField> parseFunctionParams() {
    final params = <ParamField>[];
    final b = StringBuffer();
    var name = '';
    loop((char) {
      if (b.isEmpty && whiteSpace.hasMatch(char)) return false;
      if (name.isEmpty && char == ':') {
        name = b.toString();
        b.clear();
        return false;
      }
      if (char == ')' || char == ',') {
        final text = b.toString().trim();
        final type = BuiltinTypeAst.parse(text);
        if (type != null) {
          final p = ParamField(name, type);
          params.add(p);
        }
        name = '';
        b.clear();
        if (char == ')') {
          return true;
        }
        return false;
      }
      b.write(char);
      return false;
    });
    return params;
  }
}

mixin ParseStruct on ParserGlobals {
  void parseStruct() {
    final b = StringBuffer();

    // name
    loop((char) {
      if (b.isEmpty && whiteSpace.hasMatch(char)) return false;
      if (char == '{') return true;
      b.write(char);
      return false;
    });

    final name = b.toString().trim();
    b.clear();
    final params = parseStructFields();

    var struct = globalStruct.remove(name);
    if (struct != null) {
      struct.fields.addAll(params);
    } else {
      struct = StructAst(name, params);
    }
    globalStruct[name] = struct;
  }

  List<StructField> parseStructFields() {
    final params = <StructField>[];
    final b = StringBuffer();
    var name = '';
    loop((char) {
      if (b.isEmpty && whiteSpace.hasMatch(char)) return false;
      if (name.isEmpty && char == ':') {
        name = b.toString();
        b.clear();
        return false;
      }
      if (char == ')' || char == ',') {
        final text = b.toString().trim();
        final type = BuiltinTypeAst.parse(text);
        if (type != null) {
          final p = StructField(name, type);
          params.add(p);
        }
        name = '';
        b.clear();
        if (char == ')') {
          return true;
        }
        return false;
      }
      b.write(char);
      return false;
    });
    return params;
  }
}
