import 'dart:async';

import 'package:collection/collection.dart';
import 'package:llvm_dart/ast/expr.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:llvm_dart/parsers/token_it.dart';
import 'package:nop/nop.dart';

import '../ast/ast.dart';
import '../ast/stmt.dart';

Modules parseTopItem(String src) {
  final m = Modules(src);
  m.parse();
  return m;
}

class Modules {
  Modules(this.src);
  final String src;
  void parse() {
    runZoned(() {
      final reader = TokenReader(src);
      final root = reader.parse(false);
      final it = root.child.tokenIt;
      loop(it, () {
        final token = getToken(it);
        if (token.kind == TokenKind.lf) return false;
        print('token : ${Identifier.fromToken(token)}');
        if (token.kind == TokenKind.ident) {
          parseIdent(it, global: true);
        }
        return false;
      });
    }, zoneValues: {'astSrc': src});
  }

  String getSrc(int s, int e) {
    return src.substring(s, e);
  }

  // final globalFn = <Identifier, Fn>{};
  // final globalStruct = <Identifier, StructTy>{};
  // final globalEnum = <Identifier, EnumTy>{};
  final globalTy = <Token, Ty>{};
  final globalVar = <Token, Stmt>{};

  Ty? parseIdent(TokenIterator it, {bool global = true}) {
    final token = getToken(it);
    assert(token.kind == TokenKind.ident);

    final key = Key.from(getSrc(token.start, token.end));
    Ty? ty;
    if (key != null) {
      switch (key) {
        case Key.fn:
          ty = parseFn(it);
          break;
        case Key.struct:
          ty = parseStruct(it);
          break;
        case Key.kEnum:
          ty = parseEnum(it);
          break;
        case Key.kStatic:
          final token = getToken(it);
          final stmt = parseStaticExpr(it);
          if (stmt != null) {
            globalVar[token] = stmt;
          }
          break;
        case Key.kComponent:
          ty = parseCom(it);
          break;
        case Key.kImpl:
          ty = parseImpl(it);
          break;
        case Key.kExtern:
          ty = parseExtern(it);
          break;
        default:
      }
      if (ty != null && global) {
        globalTy[token] = ty;
      }
    }
    return ty;
  }

  Ty? parseExtern(TokenIterator it) {
    eatLfIfNeed(it);
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind == TokenKind.openBrace) {
        it.moveNext(); // {
        final childIt = it.current.child.tokenIt;
        eatLfIfNeed(childIt);
        if (it.moveNext()) {
          final t = getToken(it);
          if (t.kind == TokenKind.ident) {
            return parseIdent(it, global: false)?..extern = true;
          }
        }
      } else if (t.kind == TokenKind.ident) {
        return parseIdent(it, global: false)?..extern = true;
      }
    }
    return null;
  }

  ImplTy? parseImpl(TokenIterator it) {
    eatLfIfNeed(it);
    if (!it.moveNext()) return null;
    Identifier? com = getIdent(it);
    Identifier? label;
    Identifier? ident;
    if (getKey(it) == Key.kFor) {
      com = null;
      eatLfIfNeed(it);
      if (it.moveNext()) {
        ident = getIdent(it);
      }
    } else {
      eatLfIfNeed(it);
      if (!it.moveNext()) return null;
      final t = getToken(it);
      if (t.kind == TokenKind.colon) {
        eatLfIfNeed(it);
        if (!it.moveNext()) {
          label = getIdent(it);
          if (!it.moveNext()) return null;
        }
      } else if (t.kind == TokenKind.openBrace) {
        // no com
        ident = com;
        com = null;
      } else {
        eatLfIfNeed(it);
        if (!it.moveNext()) return null;
        ident = getIdent(it);
      }
    }

    if (ident == null) {
      // error
      return null;
    }

    final ty = PathTy(ident);

    eatLfIfNeed(it);
    checkBlock(it);

    if (getToken(it).kind == TokenKind.openBrace) {
      final fns = <Fn>[];
      final staticFns = <Fn>[];
      it.moveNext();
      it = it.current.child.tokenIt;
      loop(it, () {
        final t = getToken(it);
        if (t.kind == TokenKind.closeBrace) return true;
        if (t.kind == TokenKind.ident) {
          var key = getKey(it);
          var isStatic = false;
          if (key == Key.kStatic) {
            eatLfIfNeed(it);
            it.moveNext();
            key = getKey(it);
            isStatic = true;
          }
          if (key == Key.fn) {
            var fn = parseFn(it);
            if (fn != null) {
              if (isStatic) {
                staticFns.add(fn);
              } else {
                fns.add(fn);
              }
            }
          }
        }
        return false;
      });

      return ImplTy(ident, com, ty, label, fns, staticFns);
    }

    return null;
  }

  ComponentTy? parseCom(TokenIterator it) {
    eatLfIfNeed(it);
    if (!it.moveNext()) return null;
    final ident = getIdent(it);

    eatLfIfNeed(it);

    checkBlock(it);

    if (getToken(it).kind == TokenKind.openBrace) {
      final fns = <FnSign>[];
      it.moveNext();
      it = it.current.child.tokenIt;
      loop(it, () {
        final t = getToken(it);
        if (t.kind == TokenKind.closeBrace) return true;
        if (t.kind == TokenKind.ident) {
          final key = getKey(it);
          if (key == Key.fn) {
            it.moveNext();
            final ident = getIdent(it);
            final fn = parseFnDecl(it, ident);
            fns.add(FnSign(true, fn));
          }
        }
        return false;
      });

      return ComponentTy(ident, fns);
    }

    return null;
  }

  FnDecl parseFnDecl(TokenIterator it, Identifier ident) {
    final params = <GenericParam>[];

    loop(it, () {
      final token = getToken(it);
      final kind = token.kind;

      if (kind == TokenKind.ident) {
        final ident = Identifier.fromToken(token);
        eatLfIfNeed(it);
        if (it.moveNext()) {
          assert(it.current.token.kind == TokenKind.colon);
          eatLfIfNeed(it);
          if (it.moveNext()) {
            final t = getToken(it);
            bool isRef = false;
            if (t.kind == TokenKind.and) {
              isRef = true;
              eatLfIfNeed(it);
              it.moveNext();
            }
            final name = it.current;
            final ty = PathTy(Identifier.fromToken(name.token));
            final param = GenericParam(ident, ty, isRef);
            params.add(param);
          }
        }
      } else {
        if (kind == TokenKind.closeParen || kind == TokenKind.closeBrace) {
          return true;
        }
      }
      return false;
    });

    Ty? retTy;

    eatLfIfNeed(it);
    if (it.moveNext()) {
      final c = it.current;
      if (c.token.kind == TokenKind.ident) {
        final key = getKey(it);
        if (key == null) {
          retTy = PathTy(Identifier.fromToken(c.token));
        } else {
          it.moveBack();
        }
      } else {
        it.moveBack();
      }
    }
    retTy ??= BuiltInTy.kVoid;

    return FnDecl(ident, params, retTy);
  }

  Fn? parseFn(TokenIterator it) {
    if (!it.moveNext()) {
      return null;
    }
    final ident = getIdent(it);
    it.moveNext(); // '('

    final fnSign = FnSign(true, parseFnDecl(it, ident));

    final state = it.cursor;

    if (it.moveNext()) {
      final key = getKey(it);
      if (key == null) {
        checkBlock(it);

        if (getToken(it).kind == TokenKind.openBrace) {
          final block = parseBlock(it);
          return Fn(fnSign, block);
        } else {
          state.restore();
        }
      } else {
        state.restore();
      }
    }
    return Fn(fnSign, null);
  }

  bool isBlockStart(TokenIterator it) {
    return getToken(it).kind == TokenKind.openBrace;
  }

  Block parseBlock(TokenIterator it) {
    assert(it.current.token.kind == TokenKind.openBrace, getToken(it).kind.str);
    final stmts = <Stmt>[];
    if (!it.moveNext()) return Block([], getIdent(it));
    it = it.current.child.tokenIt;

    loop(it, () {
      final t = getToken(it);
      final k = t.kind;
      if (k == TokenKind.lf) return false;

      final stmt = parseStmt(it);
      if (stmt != null) {
        stmts.add(stmt);
      }
      return false;
    });
    return Block(stmts, null);
  }

  Key? getKey(TokenIterator it) {
    final t = it.current.token;
    return Key.from(getSrc(t.start, t.end));
  }

  Token getToken(TokenIterator it) {
    return it.current.token;
  }

  Identifier getIdent(TokenIterator it) {
    return Identifier.fromToken(it.current.token);
  }

  Stmt? parseStmt(TokenIterator it) {
    Stmt? stmt = parseLetStmt(it);
    stmt ??= parseIfExpr(it);
    stmt ??= parseLoopExpr(it);
    stmt ??= parseWhileExpr(it);

    final key = getKey(it);
    if (stmt == null) {
      if (key == Key.fn) {
        final fn = parseFn(it);
        if (fn != null) {
          stmt = FnStmt(fn);
        }
      } else if (key == Key.kRet) {
        final ident = getIdent(it);
        Expr? expr;
        if (it.moveNext()) {
          final t = getToken(it);
          if (t.kind != TokenKind.lf) {
            it.moveBack();
            expr = parseExpr(it);
          } else {
            it.moveBack();
          }
        }
        stmt = ExprStmt(RetExpr(expr, ident));
      }
    }
    stmt ??= parseStmtBase(it);

    return stmt;
  }

  Stmt? parseStaticExpr(TokenIterator it) {
    return parseLetStmt(it);
  }

  Stmt? parseLoopExpr(TokenIterator it) {
    final isLoop = getKey(it) == Key.kLoop;
    if (!isLoop) return null;
    final ident = getIdent(it);

    eatLfIfNeed(it);
    checkBlock(it);
    if (isBlockStart(it)) {
      final block = parseBlock(it);
      final expr = LoopExpr(ident, block);
      return ExprStmt(expr);
    }

    return null;
  }

  Stmt? parseWhileExpr(TokenIterator it) {
    final isLoop = getKey(it) == Key.kWhile;
    if (!isLoop) return null;
    final ident = getIdent(it);
    eatLfIfNeed(it);

    // if (getToken(it).kind == TokenKind.openParen) return null;
    final expr = parseExpr(it);

    checkBlock(it);
    if (isBlockStart(it)) {
      final block = parseBlock(it);
      final wExpr = WhileExpr(ident, expr, block);

      return ExprStmt(wExpr);
    }

    return null;
  }

  Stmt parseStmtBase(TokenIterator it) {
    final ident = getIdent(it);
    it.moveBack();
    final lhs = parseExpr(it, runOp: true);

    eatLfIfNeed(it);
    OpKind? key;
    if (it.moveNext()) {
      final t = getToken(it);
      key = OpKind.from(t.kind.char);
      if (key == null) {
        it.moveBack();
      }
    }

    if (it.moveNext()) {
      final e = getToken(it);
      if (e.kind == TokenKind.eq) {
        final rhs = parseExpr(it);
        if (key != null) {
          return ExprStmt(AssignOpExpr(key, lhs, ident, rhs));
        } else {
          return ExprStmt(AssignExpr(lhs, ident, rhs));
        }
      } else if (e.kind != TokenKind.lf) {
        it.moveBack();
      }
    }

    return ExprStmt(lhs);
  }

  Stmt? parseIfExpr(TokenIterator it) {
    final isIfExpr = getKey(it) == Key.kIf;
    if (!isIfExpr) return null;
    eatLfIfNeed(it);

    final expr = parseExpr(it);
    Block block;
    checkBlock(it);

    if (getToken(it).kind == TokenKind.openBrace) {
      block = parseBlock(it);
    } else {
      block = Block([], getIdent(it));
    }

    List<IfExprBlock>? elseIfExprs = parseElseIfExpr(it);
    Block? kElse;

    eatLfIfNeed(it);

    if (getToken(it).kind == TokenKind.closeBrace) {
      it.moveNext();
      eatLfIfNeed(it);
    }
    final hasElse = getKey(it) == Key.kElse;
    if (hasElse) {
      checkBlock(it);
      kElse = parseBlock(it);
    }

    final ifExpr = IfExpr(IfExprBlock(expr, block), elseIfExprs, kElse);

    return ExprStmt(ifExpr);
  }

  List<IfExprBlock>? parseElseIfExpr(TokenIterator it) {
    List<IfExprBlock>? elseIf;
    loop(it, () {
      final key = getKey(it);
      final t = getToken(it);

      if (t.kind == TokenKind.closeBrace || t.kind == TokenKind.lf) {
        return false;
      }
      final hasElse = key == Key.kElse;

      if (hasElse) {
        var hasElseIf = false;
        if (it.moveNext()) {
          eatLfIfNeed(it);
          hasElseIf = getKey(it) == Key.kIf;
        }
        if (hasElseIf) {
          final expr = parseExpr(it);

          eatLfIfNeed(it);
          // it.moveNext(); // {
          Block block;
          checkBlock(it);

          if (getToken(it).kind == TokenKind.openBrace) {
            block = parseBlock(it);
          } else {
            block = Block([], getIdent(it));
          }
          final b = elseIf ??= [];
          final elf = IfExprBlock(expr, block);
          b.add(elf);
          return false;
        }
      }
      it.moveBack();
      return true;
    });

    return elseIf;
  }

  void checkParen(TokenIterator it) {
    if (getToken(it).kind != TokenKind.openParen) {
      loop(it, () {
        final t = getToken(it);
        if (t.kind == TokenKind.lf) return true;
        if (t.kind == TokenKind.openParen) return true;
        return false;
      });
    }
  }

  void checkBlock(TokenIterator it) {
    if (getToken(it).kind != TokenKind.openBrace) {
      loop(it, () {
        final t = getToken(it);
        if (t.kind == TokenKind.lf) return true;
        if (t.kind == TokenKind.openBrace) return true;
        return false;
      });
    }
  }

  /// let x: string = "10101"
  /// let y = 1111
  Stmt? parseLetStmt(TokenIterator it) {
    final key = getKey(it);
    final isLet = key == Key.let;
    final isStatic = key == Key.kStatic;
    if (!isLet && !isStatic) return null;
    final ident = getIdent(it);
    eatLfIfNeed(it);
    it.moveNext();

    final l = getIdent(it);

    eatLfIfNeed(it);
    it.moveNext();

    var c = getToken(it);
    PathTy? ty;

    if (c.kind == TokenKind.colon) {
      eatLfIfNeed(it);
      it.moveNext();
      final tyy = getToken(it);
      ty = PathTy(Identifier.fromToken(tyy));
      eatLfIfNeed(it);

      it.moveNext();
      c = getToken(it);
    }

    if (c.kind == TokenKind.eq) {
      final r = parseExpr(it);
      if (isStatic) {
        return StaticStmt(ident, l, r, ty);
      }
      return LetStmt(ident, l, r, ty);
    } else {
      return LetStmt(ident, l, null, ty);
    }
  }

  Expr parseExpr(TokenIterator it, {bool runOp = false}) {
    eatLfIfNeed(it);
    var isRef = false;

    if (it.moveNext()) {
      if (getToken(it).kind == TokenKind.and) {
        isRef = true;
        eatLfIfNeed(it);
      } else {
        it.moveBack();
      }
    }

    if (it.moveNext()) {
      final t = getToken(it);
      Expr? lhs;
      if (t.kind == TokenKind.literal) {
        final lit = t.literalKind!;
        BuiltInTy? ty;
        if (lit == LiteralKind.kString) {
          ty = BuiltInTy.string;
        } else if (lit == LiteralKind.kInt) {
          ty = BuiltInTy.int;
        } else if (lit == LiteralKind.kFloat) {
          ty = BuiltInTy.float;
        }
        if (ty != null) {
          lhs = LiteralExpr(getIdent(it), ty);
        }
      }

      if (lhs == null) {
        if (t.kind == TokenKind.ident) {
          final ident = getIdent(it);
          final key = getKey(it);

          if (key == Key.kBreak) {
            Identifier? label;
            if (it.moveNext()) {
              final t = getToken(it);
              if (t.kind == TokenKind.ident) {
                label = getIdent(it);
              } else {
                it.moveBack();
              }
            }
            eatLine(it);
            return BreakExpr(ident, label);
          } else if (key == Key.kContinue) {
            eatLine(it);
            return ContinueExpr(ident);
          }
          eatLfIfNeed(it);

          if (it.moveNext()) {
            final t = getToken(it);
            final cursor = it.cursor;
            if (t.kind == TokenKind.openBrace) {
              final struct = parseStructExpr(it, ident);
              if (struct.fields.any((e) => e.expr is UnknownExpr)) {
                cursor.restore();
              } else {
                return struct;
              }
            } else if (t.kind == TokenKind.openParen) {
              return parseCallExpr(it, ident);
            } else if (t.kind == TokenKind.dot) {
              return parseMethodCallExpr(it, ident);
            }
            it.moveBack();
          }

          lhs = VariableIdentExpr(ident);
        } else if (t.kind == TokenKind.openParen) {
          it.moveBack();
          var expr = parseOpExpr(it, null);
          if (expr == null) {
            it.moveNext();
            expr = parseExpr(it);
          }
          return RefExpr(expr, isRef);
        }
      }
      if (lhs != null) {
        if (runOp) {
          return RefExpr(lhs, isRef);
        }
        final op = parseOpExpr(it, lhs);
        if (op != null) {
          return RefExpr(op, isRef);
        }
      }
    }
    return UnknownExpr(getIdent(it), '');
  }

  Expr? parseOpParen(TokenIterator it) {
    return parseExpr(it, runOp: true);
  }

  Expr? parseOpExpr(TokenIterator it, Expr? lhs) {
    Expr? opLhs = lhs;
    loop(it, () {
      final k = getToken(it).kind;
      if (k == TokenKind.lf) return true;
      if (k == TokenKind.semi) return true;
      if (k == TokenKind.closeParen) {
        // 操作符行为
        if (opLhs is OpExpr) return false;
        // 保留上一个 token, stmt语句有一次移动操作
        it.moveBack();
        return true;
      }
      if (opLhs == null && k == TokenKind.openParen) {
        final lhs = parseExpr(it, runOp: true);
        opLhs = lhs;
        return false;
      }

      final op = resolveOp(it);
      if (op != null) {
        eatLfIfNeed(it);
        it.moveNext();
        Expr rhs;
        if (getToken(it).kind == TokenKind.openParen) {
          rhs = parseExpr(it);
        } else {
          it.moveBack();
          rhs = parseExpr(it, runOp: true);
        }
        final ope = opLhs;
        if (ope == null) {
          opLhs = rhs;
        } else {
          opLhs = OpExpr(op, opLhs!, rhs);
        }
        return false;
      }
      it.moveBack();
      opLhs ??= parseExpr(it);
      return true;
    });

    return opLhs;
  }

  FnCallExpr parseCallExpr(TokenIterator it, Identifier ident) {
    return FnCallExpr(ident, parseFieldExpr(it));
  }

  List<FieldExpr> parseFieldExpr(TokenIterator it) {
    final fields = <FieldExpr>[];

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.comma) return false;
      if (t.kind == TokenKind.lf || t.kind == TokenKind.openParen) return false;
      if (t.kind == TokenKind.closeParen || t.kind == TokenKind.semi) {
        return true;
      }

      void parseCommon() {
        it.moveBack();
        final expr = parseExpr(it);
        final f = FieldExpr(expr, null);
        fields.add(f);
        Log.i('...$expr ${getIdent(it)}');
      }

      if (t.kind == TokenKind.ident) {
        final ident = getIdent(it);
        eatLfIfNeed(it);
        if (it.moveNext()) {
          // ignore: unused_local_variable
          final t = getToken(it); // :
          if (t.kind == TokenKind.closeParen) {
            it.moveBack();
            it.moveBack();
            final expr = parseExpr(it);
            final f = FieldExpr(expr, null);
            fields.add(f);
            it.moveNext(); // eat `)`
            return true;
          } else if (t.kind == TokenKind.colon) {
            final expr = parseExpr(it);
            final f = FieldExpr(expr, ident);
            fields.add(f);
          } else {
            it.moveBack();
            parseCommon();
          }
        }
      } else {
        parseCommon();
      }
      return false;
    });
    return fields;
  }

  Expr parseMethodCallExpr(TokenIterator it, Identifier ident) {
    eatLfIfNeed(it);
    it.moveNext(); // .

    final fnOrFieldName = getIdent(it);
    eatLfIfNeed(it);
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind != TokenKind.openParen) {
        final expr = StructDotFieldExpr(ident, fnOrFieldName);
        it.moveBack();
        return expr;
      } else {
        it.moveBack();
      }
    } else {
      final expr = StructDotFieldExpr(ident, fnOrFieldName);
      it.moveBack();
      return expr;
    }

    // check Syntax
    return MethodCallExpr(
        fnOrFieldName, VariableIdentExpr(ident), parseFieldExpr(it));
  }

  /// { }: 由于这个token会回解析到`child`中
  /// 和[parseCallExpr]有点区别
  StructExpr parseStructExpr(TokenIterator it, Identifier ident) {
    final fields = <StructExprField>[];
    it.moveNext(); // `}`
    it = it.current.child.tokenIt;

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.closeBrace || t.kind == TokenKind.semi) {
        return true;
      }

      if (t.kind == TokenKind.comma) return false;

      void parseCommon() {
        it.moveBack();
        final expr = parseExpr(it);
        final f = StructExprField(null, expr);
        fields.add(f);
      }

      if (t.kind == TokenKind.ident) {
        final ident = getIdent(it);
        final state = it.cursor;
        eatLfIfNeed(it);
        if (it.moveNext()) {
          final t = getToken(it); // :
          if (t.kind == TokenKind.colon) {
            final expr = parseExpr(it);
            final f = StructExprField(ident, expr);
            fields.add(f);
          } else {
            state.restore();
            parseCommon();
          }
        } else {
          // 最后一个
          parseCommon();
          return true;
        }
      } else {
        parseCommon();
      }

      return false;
    });
    return StructExpr(ident, fields);
  }

  OpKind? resolveOp(TokenIterator it) {
    final current = it.current;
    final firstOp = current.token.kind.char;
    OpKind? lastOp;
    loop(it, () {
      final t = getToken(it);
      if (t.kind.char.isEmpty) {
        it.moveBack();
        return true;
      }
      final text = firstOp + t.kind.char;
      final newOp = OpKind.from(text);
      if (newOp != null) {
        lastOp = newOp;
      } else {
        it.moveBack();
        return true;
      }
      return false;
    });

    // 处理未知操作符
    loop(it, () {
      final t = getToken(it).kind;
      final op = OpKind.from(t.char);
      if (op != null) return false;
      it.moveBack();
      return true;
    });

    return lastOp ?? OpKind.from(firstOp);
  }

  StructTy? parseStruct(TokenIterator it) {
    eatLfIfNeed(it);

    if (!it.moveNext()) return null;
    final ident = getIdent(it);
    eatLfIfNeed(it);

    it.moveNext(); // {
    it.moveNext(); // block

    final fields = <FieldDef>[];
    it = it.current.child.tokenIt;
    loop(it, () {
      final k = getToken(it).kind;
      if (k == TokenKind.closeBrace) return true;
      if (k == TokenKind.ident) {
        final name = getIdent(it);

        eatLfIfNeed(it);
        it.moveNext(); // :
        if (it.moveNext()) {
          final t = getToken(it);

          final k = t.kind;
          Ty? ty;
          if (k == TokenKind.ident) {
            ty = PathTy(Identifier.fromToken(t));
          } else {
            ty = UnknownTy(ident);
          }
          fields.add(FieldDef(name, ty));
        }
      }
      return false;
    });

    return StructTy(ident, fields);
  }

  EnumTy? parseEnum(TokenIterator it) {
    eatLfIfNeed(it);

    if (!it.moveNext()) return null;
    if (getToken(it).kind != TokenKind.ident) return null;

    final ident = getIdent(it);
    eatLfIfNeed(it);

    it.moveNext(); // {
    it.moveNext(); // block

    it = it.current.child.tokenIt;

    final variants = <EnumItem>[];
    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.closeBrace) return true;
      // e.g. Some
      if (t.kind == TokenKind.ident) {
        final item = parseEnumItem(it);

        variants.add(item);
      }
      return false;
    });

    return EnumTy(ident, variants);
  }

  EnumItem parseEnumItem(TokenIterator it) {
    final ident = getIdent(it);
    eatLfIfNeed(it);

    it.moveNext(); // (
    if (getToken(it).kind != TokenKind.openParen) return EnumItem(ident, null);

    final fields = <FieldDef>[];

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.closeParen) return true;

      // ,
      if (t.kind == TokenKind.ident) {
        final ident = getIdent(it);
        final f = FieldDef(ident, PathTy(ident));
        fields.add(f);
      }
      return false;
    });

    return EnumItem(ident, fields);
  }

  /// 跳过换行符
  void eatLfIfNeed(TokenIterator it) {
    loop(it, () {
      final k = getToken(it).kind;
      if (k != TokenKind.lf) {
        it.moveBack();
        return true;
      }
      return false;
    });
  }

  /// 跳过当前语句或移到下一行
  void eatLine(TokenIterator it) {
    return loop(it, () {
      final k = getToken(it).kind;
      return k == TokenKind.semi || k == TokenKind.lf;
    });
  }

  void loop(Iterator<TokenTree> it, bool Function() action) {
    while (it.moveNext()) {
      if (action()) return;
    }
  }
}

enum Key {
  let('let'),
  fn('fn'),
  struct('struct'),
  kEnum('enum'),
  kStatic('static'),
  kImpl('impl'),
  kComponent('com'),
  kRet('return'),
  kExtern('extern'),

  kFor('for'),
  kIf('if'),
  kElse('else'),
  kWhile('while'),
  kLoop('loop'),
  kBreak('break'),
  kContinue('continue'),
  ;

  final String key;
  const Key(this.key);

  static Key? from(String src) {
    return values.firstWhereOrNull((element) => element.key == src);
  }
}
