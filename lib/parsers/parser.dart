import 'dart:async';

import 'package:collection/collection.dart';

import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/stmt.dart';
import '../ast/tys.dart';
import 'lexers/token_kind.dart';
import 'lexers/token_stream.dart';
import 'token_it.dart';

Parser parseTopItem(String src) {
  final m = Parser(src);
  m.parse();
  return m;
}

class Parser {
  Parser(this.src);
  final String src;
  void parse() {
    final reader = TokenReader(src);
    final root = reader.parse(false);
    final it = root.child.tokenIt;
    loop(it, () {
      final token = getToken(it);
      if (token.kind == TokenKind.lf) return false;
      if (token.kind == TokenKind.semi) return false;

      // print('item:\n${getIdent(it).light}');
      if (token.kind == TokenKind.ident) {
        parseIdent(it, global: true);
      }
      return false;
    });
  }

  String getSrc(int s, int e) {
    return src.substring(s, e);
  }

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
        case Key.struct:
          ty = parseStruct(it);
        case Key.kEnum:
          ty = parseEnum(it);
        case Key.kStatic:
          final token = getToken(it);
          final stmt = parseStaticExpr(it);
          if (stmt != null) {
            globalVar[token] = stmt;
          }
        case Key.kComponent:
          ty = parseCom(it);
        case Key.kImpl:
          ty = parseImpl(it);
        case Key.kExtern:
          ty = parseExtern(it);
        case Key.kImport:
          final token = getToken(it);
          final stmt = parseImportStmt(it);
          if (stmt != null) {
            globalVar[token] = stmt;
          }
        case Key.kType:
          ty = parseType(it);
        default:
      }
      if (ty != null && global) {
        globalTy[token] = ty;
      }
    }
    return ty;
  }

  Ty? parseType(TokenIterator it) {
    eatLfIfNeed(it);
    final path = parsePathTy(it);
    if (path != null) {
      return CTypeTy(path);
    }
    return null;
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
    PathTy? com = parsePathTy(it);
    PathTy? label;
    PathTy? ty;
    if (it.moveNext()) {
      if (getKey(it) == Key.kFor) {
        eatLfIfNeed(it);
        if (!it.moveNext()) return null;
        final t = getToken(it);
        if (t.kind == TokenKind.colon) {
          eatLfIfNeed(it);
          if (!it.moveNext()) {
            label = parsePathTy(it);
          }
        }
      } else {
        it.moveBack();
        ty = com;
        com = null;
      }
    }

    eatLfIfNeed(it);
    ty ??= parsePathTy(it);

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

      if (ty == null) return null;

      return ImplTy(com, ty, label, fns, staticFns);
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
    bool isVar = false;
    loop(it, () {
      final token = getToken(it);
      final kind = token.kind;

      if (kind == TokenKind.ident) {
        final ident = getIdent(it);
        eatLfIfNeed(it);
        if (it.moveNext()) {
          assert(it.current.token.kind == TokenKind.colon);
          final ty = parsePathTy(it);
          if (ty != null) {
            final param = GenericParam(ident, ty);
            params.add(param);
          }
        }
      } else {
        if (getToken(it).kind.char == '.') {
          isVar = true;
          loop(it, () {
            if (getToken(it).kind.char == '.') {
              return false;
            }
            it.moveBack();
            return true;
          });
        }
        if (kind == TokenKind.closeParen || kind == TokenKind.closeBrace) {
          return true;
        }
      }
      return false;
    });

    PathTy? retTy;

    eatLfIfNeed(it);
    final state = it.cursor;
    if (it.moveNext()) {
      final key = getKey(it);
      if (key == null) {
        state.restore();
        retTy = parsePathTy(it);
      }
    }
    if (retTy == null) {
      state.restore();
    }

    retTy ??= PathTy.ty(BuiltInTy.kVoid);

    return FnDecl(ident, params, retTy, isVar);
  }

  Fn? parseFn(TokenIterator it) {
    var ident = Identifier.none;
    if (!it.moveNext()) {
      return null;
    }
    eatLfIfNeed(it);
    if (getToken(it).kind != TokenKind.openParen) {
      ident = getIdent(it);
      it.moveNext(); // '('
    }

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

  PathTy? parsePathTy(TokenIterator it) {
    eatLfIfNeed(it);

    final pointerKind = getAllKind(it);
    PathTy? ty;
    final state = it.cursor;

    // if (k == TokenKind.ident) {
    //       if (getKey(it) == Key.fn) {
    //         it.moveNext();
    //         final decl = parseFnDecl(it, Identifier.none);
    //         ty = PathTy.ty(FnTy(decl));
    //       } else {
    //         ty = PathTy(ident);
    //       }
    //     } else {
    //       ty = UnknownTy(ident);
    //     }
    if (it.moveNext()) {
      if (getKey(it) == Key.fn) {
        it.moveNext();
        final decl = parseFnDecl(it, Identifier.none);
        ty = PathTy.ty(FnTy(decl), pointerKind);
      } else if (getToken(it).kind == TokenKind.ident) {
        ty = PathTy(getIdent(it), parseGenericsInstance(it), pointerKind);
      }
    }
    if (ty == null) {
      state.restore();
    }
    return ty;
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
      if (k == TokenKind.semi) return false;
      if (k == TokenKind.closeBrace) return false;
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
    return Identifier.fromToken(it.current.token, src);
  }

  Stmt? parseStmt(TokenIterator it) {
    Stmt? stmt;

    final key = getKey(it);
    if (key == Key.fn) {
      final fn = parseFn(it);
      if (fn != null) {
        stmt = ExprStmt(FnExpr(fn));
      }
    } else if (key == Key.struct) {
      final struct = parseStruct(it);
      if (struct != null) {
        stmt = StructStmt(struct);
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
    stmt ??= parseLetStmt(it);
    stmt ??= parseIfStmt(it);
    stmt ??= parseLoopExpr(it);
    stmt ??= parseWhileExpr(it);
    stmt ??= parseMatchStmt(it);
    stmt ??= parseImportStmt(it);
    stmt ??= parseStmtBase(it);

    return stmt;
  }

  Stmt? parseImportStmt(TokenIterator it) {
    final key = getKey(it);
    if (key != Key.kImport) return null;
    eatLfIfNeed(it);
    final state = it.cursor;
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind == TokenKind.literal && t.literalKind == LiteralKind.kString) {
        final path = ImportPath(getIdent(it));
        eatLfIfNeed(it);
        if (it.moveNext() && getKey(it) == Key.kAs) {
          eatLfIfNeed(it);
          if (it.moveNext()) {
            if (getToken(it).kind == TokenKind.ident) {
              return ExprStmt(ImportExpr(path, name: getIdent(it)));
            }
          }
        } else {
          it.moveBack();
          return ExprStmt(ImportExpr(path));
        }
      }
    }
    state.restore();
    return null;
  }

  Stmt? parseMatchStmt(TokenIterator it) {
    final expr = parseMatchExpr(it);
    if (expr != null) {
      return ExprStmt(expr);
    }
    return null;
  }

  Expr? parseMatchExpr(TokenIterator it) {
    final isMatch = getKey(it) == Key.kMatch;
    if (!isMatch) return null;
    final expr = parseExpr(it);
    checkBlock(it);
    if (getToken(it).kind == TokenKind.openBrace) {
      final items = parseMatchItem(it);
      return MatchExpr(expr, items);
    }
    return null;
  }

  List<MatchItemExpr> parseMatchItem(TokenIterator it) {
    assert(it.current.token.kind == TokenKind.openBrace, getToken(it).kind.str);
    if (!it.moveNext()) return [];
    it = it.current.child.tokenIt;
    final items = <MatchItemExpr>[];
    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.ident) {
        it.moveBack();
        final expr = parseExpr(it);
        eatLfIfNeed(it);

        if (it.moveNext()) {
          if (getToken(it).kind == TokenKind.eq) {
            eatLfIfNeed(it);
            if (it.moveNext()) {
              eatLfIfNeed(it);
              if (getToken(it).kind == TokenKind.gt) {
                it.moveNext();
              }
            }
          }
        }

        eatLfIfNeed(it);
        if (getToken(it).kind == TokenKind.openBrace) {
          final block = parseBlock(it);
          items.add(MatchItemExpr(expr, block));
        } else {
          final stmt = parseStmt(it);
          if (stmt != null) {
            final block = Block([stmt], null);
            items.add(MatchItemExpr(expr, block));
          }
        }
      }
      return false;
    });
    return items;
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

  bool get onBrace {
    return Zone.current[#onBrace] == true;
  }

  Stmt? parseWhileExpr(TokenIterator it) {
    final isLoop = getKey(it) == Key.kWhile;
    if (!isLoop) return null;
    final ident = getIdent(it);
    eatLfIfNeed(it);

    final expr = runZoned(() => parseExpr(it), zoneValues: {#onBrace: true});

    checkBlock(it);
    if (isBlockStart(it)) {
      final block = parseBlock(it);
      final wExpr = WhileExpr(ident, expr, block);

      return ExprStmt(wExpr);
    }

    return null;
  }

  Stmt parseStmtBase(TokenIterator it) {
    if (getToken(it).kind == TokenKind.openBrace) {
      final block = parseBlock(it);
      return ExprStmt(BlockExpr(block));
    }
    it.moveBack();
    final state = it.cursor;
    var lhs = parseExpr(it, runOp: true);
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
          return ExprStmt(AssignOpExpr(key, lhs, rhs));
        } else {
          return ExprStmt(AssignExpr(lhs, rhs));
        }
        // } else if (e.kind != TokenKind.lf) {
        //   it.moveBack();
      } else {
        state.restore();
        lhs = parseExpr(it);
      }
    }

    return ExprStmt(lhs);
  }

  Stmt? parseIfStmt(TokenIterator it) {
    final expr = parseIfExpr(it);
    if (expr != null) return ExprStmt(expr);
    return null;
  }

  Expr? parseIfExpr(TokenIterator it) {
    final isIfExpr = getKey(it) == Key.kIf;
    if (!isIfExpr) return null;
    eatLfIfNeed(it);
    final ifBlock = parseIfBlock(it);

    List<IfExprBlock>? elseIfExprs = parseElseIfExpr(it);
    Block? kElse;

    eatLfIfNeed(it);

    final state = it.cursor;
    if (getToken(it).kind == TokenKind.closeBrace) {
      it.moveNext();
      eatLfIfNeed(it);
    }
    final hasElse = getKey(it) == Key.kElse;
    if (hasElse) {
      checkBlock(it);
      kElse = parseBlock(it);
    } else {
      state.restore();
    }

    return IfExpr(ifBlock, elseIfExprs, kElse);
  }

  IfExprBlock parseIfBlock(TokenIterator it) {
    final expr = runZoned(() => parseExpr(it), zoneValues: {#ifExpr: true});

    Block block;
    checkBlock(it);
    if (getToken(it).kind == TokenKind.openBrace) {
      block = parseBlock(it);
    } else {
      block = Block([], getIdent(it));
    }
    return IfExprBlock(expr, block);
  }

  bool hasIfBlock(TokenIterator it) {
    final isIfExpr = Zone.current[#ifExpr] == true;

    if (!isIfExpr) return true;
    final state = it.cursor;
    if (getToken(it).kind == TokenKind.openBrace) {
      if (it.moveNext()) /** `}` */ {
        if (it.moveNext()) {
          final k = getToken(it).kind;
          if (k == TokenKind.lf || k == TokenKind.ident) {
            state.restore();
            return false;
          }
        }
      }
    }
    state.restore();

    eatLfIfNeed(it);
    // 如果紧接着是关键字，不可无视
    if (it.moveNext()) {
      if (getKey(it) == null) {
        if (getToken(it).kind != TokenKind.openBrace) {
          loop(it, () {
            final t = getToken(it);
            if (t.kind == TokenKind.semi) return true;
            if (t.kind == TokenKind.openBrace) return true;
            if (getKey(it) != null) return true;
            return false;
          });
        }
      }
    }

    final result = getToken(it).kind == TokenKind.openBrace;
    state.restore();
    return result;
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
          final elf = parseIfBlock(it);
          final b = elseIf ??= [];
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
        if (getKey(it) != null) return true;
        return false;
      });
    }
  }

  /// let x: string = "10101"
  /// let y = 1111
  Stmt? parseLetStmt(TokenIterator it) {
    final key = getKey(it);
    final isLet = key == Key.let;
    final isFinal = key == Key.kFinal;
    final isStatic = key == Key.kStatic;
    if (!isLet && !isStatic && !isFinal) return null;
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
      ty = parsePathTy(it);

      eatLfIfNeed(it);

      it.moveNext();
      c = getToken(it);
    }

    if (c.kind == TokenKind.eq) {
      final r = parseExpr(it);
      if (isStatic) {
        return StaticStmt(ident, l, r, ty);
      }
      return LetStmt(isFinal, ident, l, r, ty);
    } else {
      return LetStmt(isFinal, ident, l, null, ty);
    }
  }

  List<PointerKind> getAllKind(TokenIterator it, {bool runOp = false}) {
    var pointerKind = <PointerKind>[];
    if (it.curentIsValid && !runOp) {
      final t = getToken(it).kind;
      final kind = PointerKind.from(t);
      if (kind != null) {
        pointerKind.add(kind);
      }
      eatLfIfNeed(it);
    }
    loop(it, () {
      final t = getToken(it).kind;
      final kind = PointerKind.from(t);
      if (kind != null) {
        pointerKind.add(kind);
        return false;
      }

      it.moveBack();
      return true;
    });
    return pointerKind;
  }

  List<PathTy> parseGenericsInstance(TokenIterator it) {
    final idents = <PathTy>[];
    final state = it.cursor;
    if (it.moveNext()) {
      final kind = getToken(it).kind;
      if (kind != TokenKind.lt) {
        it.moveBack();
        return idents;
      }
    }
    loop(it, () {
      if (getToken(it).kind == TokenKind.comma) return false;
      if (getToken(it).kind == TokenKind.gt) {
        return true;
      }

      it.moveBack();
      final ty = parsePathTy(it);
      if (ty != null) {
        idents.add(ty);
      } else {
        state.restore();
        idents.clear();
        return true;
      }

      eatLfIfNeed(it);
      return false;
    });

    return idents;
  }

  Expr parseExpr(TokenIterator it,
      {bool runOp = false, bool runOpInner = false}) {
    eatLfIfNeed(it);
    final pointerKind = getAllKind(it, runOp: runOp);

    if (it.moveNext()) {
      final t = getToken(it);
      Expr? lhs;
      if (t.kind == TokenKind.openParen) {
        lhs = parseExpr(it, runOpInner: runOp);
      } else if (t.kind == TokenKind.literal) {
        final lit = t.literalKind!;
        final lkd = LitKind.from(lit);

        if (lkd != null) {
          final ty = BuiltInTy.lit(lkd);
          lhs = LiteralExpr(getIdent(it), ty);
        }
      }

      lhs ??= parseIfExpr(it);
      lhs ??= parseMatchExpr(it);

      var isNew = false;
      if (getKey(it) == Key.kNew) {
        isNew = true;
        it.moveNext();
        eatLfIfNeed(it);
      }

      if (lhs == null) {
        if (t.kind == TokenKind.ident) {
          final ident = getIdent(it);
          final key = getKey(it);
          if (key?.isBool == true) {
            final ty = BuiltInTy.lit(LitKind.kBool);
            lhs = LiteralExpr(getIdent(it), ty);
          } else if (key == Key.kBreak) {
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
          } else if (key == Key.fn) {
            final state = it.cursor;

            final fn = parseFn(it);
            if (fn != null) {
              return FnExpr(fn);
            } else {
              state.restore();
            }
          }
          eatLfIfNeed(it);

          if (!onBrace) {
            final cursor = it.cursor;
            final generics = parseGenericsInstance(it);
            if (it.moveNext()) {
              final t = getToken(it);
              if (t.kind == TokenKind.openBrace) {
                if (hasIfBlock(it)) {
                  final struct = parseStructExpr(it, ident, generics);
                  if (struct.fields.any((e) => e.expr.hasUnknownExpr)) {
                    cursor.restore();
                  } else {
                    lhs = struct;
                    struct.isNew = isNew;
                  }
                } else {
                  cursor.restore();
                }
              } else {
                cursor.restore();
              }
            }
          }
          if (lhs == null) {
            final generics = parseGenericsInstance(it);
            lhs = VariableIdentExpr(ident, generics);
          }
        }
      }
      if (lhs != null) {
        eatLfIfNeed(it);

        Expr lhsss = lhs;
        loop(it, () {
          final t = getToken(it);
          if (t.kind == TokenKind.dot) {
            lhsss = parseMethodCallExpr(it, [], lhsss);
            return false;
          } else if (t.kind == TokenKind.openParen) {
            lhsss = parseCallExpr(it, lhsss)..isNew = isNew;
            return false;
          }
          it.moveBack();
          return true;
        });
        lhs = lhsss;

        final state = it.cursor;
        if (it.moveNext()) {
          if (getKey(it) == Key.kAs) {
            final asExpr = parsePathTy(it);
            if (asExpr != null) {
              lhs = AsExpr(lhs, asExpr);
            }
          }
        }

        if (lhs is! AsExpr) {
          state.restore();
        }

        lhs = RefExpr(lhs, pointerKind);
        eatLfIfNeed(it);
        // 遇到`)`结束本次表达式解析
        if (it.moveNext()) {
          if (getToken(it).kind == TokenKind.closeParen) {
            return lhs;
          } else {
            it.moveBack();
          }
        }
        if (!runOp) {
          final op = parseOpExpr(it, lhs, runOpInner);
          if (op != null) {
            lhs = op;
          }
        }
        return lhs;
      }
    }
    return UnknownExpr(getIdent(it), '');
  }

  Expr? parseOpExpr(TokenIterator it, Expr lhs, bool runOpInner) {
    final ops = <OpKind>[];
    final exprs = <Expr>[];
    exprs.add(lhs);
    var eIt = exprs.tokenIt;

    Expr? combine() {
      Expr? cache;
      while (eIt.moveNext()) {
        final first = eIt.current;
        final ccache = cache;
        if (ccache == null) {
          cache = first;
          continue;
        }
        final index = exprs.indexOf(first);
        final opIndex = index - 1;
        final op1 = ops[opIndex];
        if (eIt.moveNext()) {
          final op2 = ops[opIndex + 1];
          if (op1.level >= op2.level) {
            cache = OpExpr(op1, ccache, first);
            eIt.moveBack();
          } else {
            eIt.moveBack(); // back
            eIt.moveBack(); // back first
            final expr = combine();
            cache = OpExpr(op1, ccache, expr!);
          }
        } else {
          cache = OpExpr(op1, ccache, first);
          break;
        }
      }
      return cache;
    }

    loop(it, () {
      // `/n` 意味着结束
      it.moveBack();

      final op = resolveOp(it);
      if (op != null) {
        final expr = parseExpr(it, runOp: true);
        ops.add(op);
        exprs.add(expr);
        if (runOpInner) {
          eatLfIfNeed(it);
          // 在一个运算解析中，结束循环并移到下一个token
          if (getToken(it).kind == TokenKind.closeParen) {
            it.moveNext();
            return true;
          }
        } else {
          // 如果上面移动到下一个token，这里就会解析错误
          if (getToken(it).kind == TokenKind.closeParen) {
            eIt = exprs.tokenIt;
            final expr = combine()!;
            ops.clear();
            exprs.clear();
            exprs.add(expr);
            // it.moveNext();
          }
        }
        return false;
      }
      return true;
    });

    if (exprs.length > 2) {
      eIt = exprs.tokenIt;
      return combine() ?? lhs;
    } else if (exprs.length == 2) {
      return OpExpr(ops.first, exprs.first, exprs.last);
    }
    return exprs.last;
  }

  FnCallExpr parseCallExpr(TokenIterator it, Expr expr) {
    return FnCallExpr(expr, parseFieldExpr(it));
  }

  List<FieldExpr> parseFieldExpr(TokenIterator it) {
    final fields = <FieldExpr>[];

    assert(getToken(it).kind == TokenKind.openParen, '${getIdent(it)}');
    eatLfIfNeed(it);
    if (it.moveNext()) {
      // eat `)`
      final t = getToken(it);
      if (t.kind == TokenKind.closeParen) {
        it.moveNext();
        return fields;
      } else {
        it.moveBack();
      }
    }
    loop(it, () {
      final t = getToken(it);

      if (t.kind == TokenKind.comma) return false;
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.semi) {
        return true;
      }

      // // eat `)`
      // if (fields.isEmpty && t.kind == TokenKind.closeParen) {
      //   return true;
      // }
      if (t.kind == TokenKind.ident) {
        eatLfIfNeed(it);
        final name = getIdent(it);

        final state = it.cursor;
        if (it.moveNext()) {
          if (getToken(it).kind == TokenKind.colon) {
            final expr = parseExpr(it);
            final f = FieldExpr(expr, name);
            fields.add(f);
            if (getToken(it).kind == TokenKind.closeParen) {
              return true;
            }
            return false;
          }
        }
        state.restore();
      }

      it.moveBack();
      final expr = parseExpr(it);
      final f = FieldExpr(expr, null);
      fields.add(f);
      if (getToken(it).kind == TokenKind.closeParen) {
        return true;
      }

      return false;
    });

    return fields;
  }

  Expr parseMethodCallExpr(
      TokenIterator it, List<PointerKind> kind, Expr structExpr) {
    eatLfIfNeed(it);
    it.moveNext(); // .

    final fnOrFieldName = getIdent(it);
    eatLfIfNeed(it);
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind != TokenKind.openParen) {
        final expr = StructDotFieldExpr(structExpr, kind, fnOrFieldName);
        it.moveBack();
        return expr;
      }
    } else {
      final expr = StructDotFieldExpr(structExpr, kind, fnOrFieldName);
      return expr;
    }

    // check Syntax
    return MethodCallExpr(fnOrFieldName, structExpr, parseFieldExpr(it));
  }

  /// { }: 由于这个token会回解析到`child`中
  /// 和[parseCallExpr]有点区别
  StructExpr parseStructExpr(
      TokenIterator it, Identifier ident, List<PathTy> generics) {
    final fields = <FieldExpr>[];
    it.moveNext(); // `}`
    final pIt = it;
    it = it.current.child.tokenIt;

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.semi) {
        final e = UnknownExpr(getIdent(it), 'is not struct expr');
        fields.add(FieldExpr(e, ident));
        return true;
      }
      if (t.kind == TokenKind.closeBrace) {
        return true;
      }

      if (t.kind == TokenKind.comma) return false;

      void parseCommon() {
        it.moveBack();
        final expr = parseExpr(it);
        final f = FieldExpr(expr, null);
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
            final f = FieldExpr(expr, ident);
            fields.add(f);
          } else {
            state.restore();
            parseCommon();
          }
          return false;
        }
      }

      parseCommon();
      return false;
    });

    final t = getToken(pIt);
    // 一定要有 `}`
    if (t.kind == TokenKind.closeBrace) {
      // test
    }

    return StructExpr(ident, fields, generics);
  }

  OpKind? resolveOp(TokenIterator it) {
    final current = it.current;
    var chars = current.token.kind.char;
    OpKind? lastOp;
    loop(it, () {
      final t = getToken(it);
      if (t.kind.char.isEmpty) {
        it.moveBack();
        return true;
      }
      final text = chars + t.kind.char;
      final newOp = OpKind.from(text);
      if (newOp != null || text == '=') {
        lastOp = newOp;
        chars = text;
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

    return lastOp ?? OpKind.from(chars);
  }

  List<FieldDef> parseGenerics(TokenIterator it) {
    final generics = <FieldDef>[];
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind != TokenKind.lt) {
        it.moveBack();
        return generics;
      }
    }
    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.gt) return true;
      if (t.kind == TokenKind.ident) {
        final ident = getIdent(it);
        eatLfIfNeed(it);
        if (it.moveNext()) {
          if (getToken(it).kind == TokenKind.colon) {
            final ty = parsePathTy(it);
            if (ty != null) {
              it.moveNext(); // `>`
              generics.add(FieldDef(ident, ty));
            }
          } else {
            generics.add(FieldDef(ident, PathTy(ident, [])));
          }
        }
      }
      if (getToken(it).kind == TokenKind.gt) {
        return true;
      }
      return false;
    });

    return generics;
  }

  StructTy? parseStruct(TokenIterator it) {
    eatLfIfNeed(it);

    if (!it.moveNext()) return null;
    final ident = getIdent(it);

    eatLfIfNeed(it);

    final types = parseGenerics(it);

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

        final ty = parsePathTy(it) ?? UnknownTy(ident);
        fields.add(FieldDef(name, ty));
      }
      return false;
    });

    return StructTy(ident, fields, types);
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
    final types = parseGenerics(it);
    eatLfIfNeed(it);

    it.moveNext(); // (
    if (getToken(it).kind != TokenKind.openParen) {
      return EnumItem(ident, [], types);
    }

    final fields = <FieldDef>[];

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.closeParen) return true;
      final state = it.cursor;
      it.moveBack();
      final ty = parsePathTy(it);
      if (ty != null) {
        final f = FieldDef(Identifier.none, ty);
        fields.add(f);
      } else {
        state.restore();
      }

      return false;
    });

    return EnumItem(ident, fields, types);
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
  kFinal('final'),
  kNew('new'),

  kFalse('false'),
  kTrue('true'),

  kFor('for'),
  kIf('if'),
  kElse('else'),
  kWhile('while'),
  kLoop('loop'),
  kBreak('break'),
  kContinue('continue'),
  kMatch('match'),
  kAs('as'),
  kImport('import'),
  kType('type'),
  ;

  bool get isBool {
    return this == kFalse || this == kTrue;
  }

  final String key;
  const Key(this.key);

  static Key? from(String src) {
    return values.firstWhereOrNull((element) => element.key == src);
  }
}
