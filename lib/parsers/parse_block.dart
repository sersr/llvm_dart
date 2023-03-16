import 'package:llvm_dart/parsers/parse_stmt.dart';

import '../ast/ast.dart';
import 'global.dart';

mixin ParseBlock on ParserGlobals, ParseStmt {
  Block parseBlock() {
    final stmts = <Stmt>[];

    loop((char) {
      if (char == '}') return true;
      final stmt = parseStmt();
      if (stmt != null) {
        stmts.add(stmt);
      }
      return false;
    });
    return Block(stmts);
  }
}
