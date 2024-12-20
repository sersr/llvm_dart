import 'dart:async';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';

import '../ast/ast.dart';
import '../ast/expr.dart';
import '../ast/stmt.dart';
import '../ast/tys.dart';
import 'lexers/token_kind.dart';
import 'lexers/token_stream.dart';
import 'str.dart';
import 'token_it.dart';

class Parser {
  Parser(this.src, this.fileName) {
    _parse();
  }
  final String src;
  final String fileName;

  void _parse() {
    Identifier.run(() {
      final reader = TokenReader(src);
      final root = reader.parse(false);

      _start = Identifier.fromToken(root.token, src, fileName);
      final it = root.child.tokenIt;
      loop(it, () {
        final token = getToken(it);
        if (token.kind == TokenKind.lf) return false;
        if (token.kind == TokenKind.semi) return false;

        if (token.kind == TokenKind.ident) {
          parseIdent(it, global: true);
        }
        return false;
      });

      _end = it.current.end != null ? getEndIdent(it) : getIdent(it);
    });
  }

  final stmts = <Stmt>[];

  late Identifier _start;
  late Identifier _end;

  Block get block {
    return Block(stmts.map((e) => e.clone()).toList(), null, _start, _end,
        inc: false);
  }

  Ty? parseIdent(TokenIterator it, {bool global = true}) {
    final token = getToken(it);
    assert(token.kind == TokenKind.ident);

    final key = getKey(it);
    Ty? ty;

    Stmt? stmt;
    if (key != null) {
      switch (key) {
        case Key.fn:
          ty = parseFn(it);
        case Key.struct:
          ty = parseStruct(it);
        case Key.kEnum:
          ty = parseEnum(it);
        case Key.kStatic:
          stmt = parseStaticExpr(it);
        case Key.kComponent:
          ty = parseCom(it);
        case Key.kImpl:
          ty = parseImpl(it);
        case Key.kExtern:
          ty = parseExtern(it);
        case Key.kImport:
          stmt = parseImportStmt(it);
        case Key.kType:
          ty = parseType(it);
        default:
      }

      if (global) {
        if (ty != null) {
          stmt = TyStmt(ty);
        }
      }
      if (stmt != null) stmts.add(stmt);
    }
    return ty;
  }

  TypeAliasTy? parseType(TokenIterator it) {
    eatLfIfNeed(it);
    it.moveNext();
    final ident = getIdent(it);
    final generics = parseGenerics(it);
    eatLfIfNeed(it);
    PathTy? base;

    if (it.moveNext()) {
      if (getToken(it).kind == TokenKind.eq) {
        base = parsePathTy(it);
      } else {
        it.moveBack();
      }
    }

    if (base == null) return null;

    return TypeAliasTy(ident, generics, base);
  }

  Stmt? parseTypeStamt(TokenIterator it) {
    if (getKey(it) == Key.kType) {
      final ty = parseType(it);
      if (ty != null) return TyStmt(ty);
    }
    return null;
  }

  Ty? parseExtern(TokenIterator it) {
    if (it.moveNext()) {
      eatLfIfNeed(it, back: false);
      final t = getToken(it);
      if (t.kind == TokenKind.openBrace) {
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
    final types = parseGenerics(it);

    PathTy? com = parsePathTy(it);
    PathTy? label;
    PathTy? ty;

    eatLfIfNeed(it);
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind == TokenKind.colon) {
        eatLfIfNeed(it);
        label = parsePathTy(it);
      } else {
        it.moveBack();
      }
    }
    if (it.moveNext()) {
      if (getKey(it) != Key.kFor) {
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
      final aliasTys = <TyStmt>[];
      final orderList = <TyStmt>[];

      it = it.current.child.tokenIt;
      loop(it, () {
        final t = getToken(it);
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
              orderList.add(TyStmt(fn));
            }
          } else if (key == Key.kType) {
            var alias = parseType(it);
            if (alias != null) {
              final stmt = TyStmt(alias);
              aliasTys.add(stmt);
              orderList.add(stmt);
            }
          }
        }
        return false;
      });

      if (ty == null) return null;

      return ImplTy(types, com, ty, label, fns, staticFns, aliasTys, orderList);
    }

    return null;
  }

  ComponentTy? parseCom(TokenIterator it) {
    eatLfIfNeed(it);
    if (!it.moveNext()) return null;
    final ident = getIdent(it);

    final types = parseGenerics(it);

    eatLfIfNeed(it);

    checkBlock(it);

    if (getToken(it).kind == TokenKind.openBrace) {
      final fns = <FnDecl>[];
      it = it.current.child.tokenIt;
      loop(it, () {
        final t = getToken(it);
        if (t.kind == TokenKind.ident) {
          final key = getKey(it);
          if (key == Key.fn) {
            it.moveNext();
            final ident = getIdent(it);
            final fn = parseFnDecl(it, ident);
            fns.add(fn);
          }
        }
        return false;
      });

      return ComponentTy(ident, fns, types);
    }

    return null;
  }

  (List<FieldDef>, bool) _params(TokenIterator it) {
    final params = <FieldDef>[];
    var isVar = false;
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
            final param = FieldDef(ident, ty);
            params.add(param);
          }
        }
      } else {
        if (getToken(it).kind == TokenKind.dot) {
          isVar = true;
          loop(it, () {
            if (getToken(it).kind == TokenKind.dot) {
              return false;
            }
            it.moveBack();
            return true;
          });
        }
      }
      return false;
    });

    return (params, isVar);
  }

  FnDecl parseFnDecl(TokenIterator it, Identifier ident) {
    List<GenericDef> generics = const [];
    if (getToken(it).kind == TokenKind.lt) {
      it.moveBack();
      generics = parseGenerics(it);
      if (getToken(it).kind == TokenKind.gt) {
        it.moveNext();
      }
    }

    final (params, isVar) = _params(it.current.child.tokenIt);

    final state = it.cursor;
    final retTy = parsePathTy(it);

    if (retTy == null) {
      state.restore();
    }

    return FnDecl(ident, params, generics, retTy, isVar);
  }

  Ty? parseFnOrFnDecl(TokenIterator it) {
    final fn = parseFn(it);
    if (fn case Fn(block: null, baseFnDecl: var fnDecl)) {
      return fnDecl;
    }

    return fn;
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

    final fnDecl = parseFnDecl(it, ident);

    final state = it.cursor;

    if (it.moveNext()) {
      final key = getKey(it);
      if (key == null) {
        checkBlock(it);

        if (getToken(it).kind == TokenKind.openBrace) {
          final block = parseBlock(it);
          return Fn(fnDecl, block);
        } else {
          state.restore();
        }
      } else {
        state.restore();
      }
    }
    return Fn(fnDecl, null);
  }

  PathTy? parsePathTy(TokenIterator it) {
    eatLfIfNeed(it);

    final pointerKind = getAllKind(it);
    PathTy? ty;
    eatLfIfNeed(it);

    final state = it.cursor;
    if (it.moveNext()) {
      eatLfIfNeed(it, back: false);
      final kind = getToken(it).kind;
      var key = getKey(it);
      var isDyn = false;
      if (key == Key.dyn) {
        isDyn = true;
        it.moveNext();
        eatLfIfNeed(it, back: false);
        key = getKey(it);
      }
      if (key == Key.fn) {
        it.moveNext();
        var decl = parseFnDecl(it, Identifier.none);
        if (isDyn) {
          decl = decl.toDyn();
        }
        ty = PathFnDeclTy(decl, pointerKind);
      } else if (kind == TokenKind.ident) {
        ty = PathTy(getIdent(it), parseGenericsInstance(it), pointerKind);
      } else if (kind == TokenKind.openBracket) {
        ty = parseArrayPathTy(it, pointerKind);
      } else if (kind == TokenKind.literal) {
        ty = PathTy(getIdent(it), const []);
      }
    }

    if (ty == null) {
      state.restore();
    }
    return ty;
  }

  SlicePathTy? parseArrayPathTy(TokenIterator it, List<PointerKind> kind) {
    it = it.current.child.tokenIt;
    final elementTy = parsePathTy(it);

    if (elementTy == null) return null;
    if (it.moveNext()) {
      final size = parsePathTy(it);
      if (size != null) return ArrayPathTy(elementTy, kind, size);
    }

    return SlicePathTy(elementTy, kind);
  }

  bool isBlockStart(TokenIterator it) {
    return getToken(it).kind == TokenKind.openBrace;
  }

  Block parseBlock(TokenIterator it) {
    assert(it.current.token.kind == TokenKind.openBrace, getToken(it).kind.str);
    final stmts = <Stmt>[];

    final start = getIdent(it);
    final end = getEndIdent(it);
    final nIt = it.current.child.tokenIt;
    it.moveNext();
    it = nIt;
    loop(it, () {
      final t = getToken(it);
      final k = t.kind;
      if (k == TokenKind.lf) return false;
      if (k == TokenKind.semi) return false;

      final stmt = parseStmt(it);
      if (stmt != null) {
        stmts.add(stmt);
      }
      return false;
    });

    return Block(stmts, null, start, end);
  }

  Key? getKey(TokenIterator it) {
    return Key.from(getIdent(it).src);
  }

  String getStr(TokenIterator it, {Token? token}) {
    if (!it.curentIsValid) return '';
    token ??= it.current.token;
    return src.substring(token.start, token.end);
  }

  Token getToken(TokenIterator it) {
    return it.current.token;
  }

  Identifier getIdent(TokenIterator it) {
    return Identifier.fromToken(it.current.token, src, fileName);
  }

  Identifier getEndIdent(TokenIterator it) {
    return Identifier.fromToken(it.current.end!, src, fileName);
  }

  Stmt? parseStmt(TokenIterator it) {
    Stmt? stmt;

    final key = getKey(it);
    if (key == Key.fn) {
      final fn = parseFn(it);
      if (fn != null) {
        stmt = TyStmt(fn);
      }
    } else if (key == Key.struct) {
      final struct = parseStruct(it);
      if (struct != null) {
        stmt = TyStmt(struct);
      }
    } else if (key == Key.kRet) {
      final ident = getIdent(it);
      Expr? expr;
      if (it.moveNext()) {
        final t = getToken(it);
        if (t.kind != TokenKind.lf && t.kind != TokenKind.semi) {
          it.moveBack();
          expr = parseExpr(it);
        } else {
          it.moveBack();
        }
      }
      stmt = RetStmt(expr, ident);
    }

    stmt ??= parseLetSwapStmt(it) ??
        parseLetStmt(it) ??
        parseIfStmt(it) ??
        parseLoopExpr(it) ??
        parseWhileExpr(it) ??
        parseMatchStmt(it) ??
        parseImportStmt(it) ??
        parseTypeStamt(it) ??
        parseStmtBase(it);

    return stmt;
  }

  LetSwapStmt? parseLetSwapStmt(TokenIterator it) {
    final isLet = getKey(it) == Key.let;
    if (!isLet) return null;
    final state = it.cursor;
    final leftExprs = <Expr>[];
    final rightExprs = <Expr>[];

    for (;;) {
      final expr = parseExpr(it);
      if (expr is! UnknownExpr) {
        leftExprs.add(expr);
      }

      if (!it.moveNext() || !isKind(it, TokenKind.comma)) {
        break;
      }
    }

    if (!isKind(it, TokenKind.eq)) {
      state.restore();
      return null;
    }

    for (;;) {
      final expr = parseExpr(it);
      if (expr is! UnknownExpr) {
        rightExprs.add(expr);
      }

      if (!it.moveNext() || !isKind(it, TokenKind.comma)) {
        break;
      }
    }

    if (leftExprs.length <= 1 ||
        rightExprs.length <= 1 ||
        leftExprs.length != rightExprs.length) {
      state.restore();
      return null;
    }

    return LetSwapStmt(leftExprs, rightExprs);
  }

  bool isKind(TokenIterator it, TokenKind kind) {
    eatLfIfNeed(it, back: false);

    final result = getToken(it).kind == kind;

    if (result && it.moveNext()) {
      if (getToken(it).kind == TokenKind.lf) {
        eatLfIfNeed(it);
      } else {
        it.moveBack();
      }
    }

    return result;
  }

  ArrayInitExpr? parseArrayInitExpr(TokenIterator it) {
    final isArrayKind = getToken(it).kind == TokenKind.openBracket;
    if (!isArrayKind) return null;
    final identStart = getIdent(it);
    final identEnd = getEndIdent(it);
    it = it.current.child.tokenIt;
    if (it.isEmpty) return null;

    final expr = parseExpr(it);
    if (it.moveNext()) {
      eatLfIfNeed(it);
      final token = getToken(it);
      if (token.kind == TokenKind.semi) {
        eatLfIfNeed(it);
        if (it.moveNext()) {
          final size = int.tryParse(getIdent(it).src);
          if (size != null) {
            return ArrayInitExpr(expr, size, identStart, identEnd);
          }
        }
      }
    }

    return null;
  }

  ArrayExpr? parseArrayExpr(TokenIterator it) {
    final isArrayKind = getToken(it).kind == TokenKind.openBracket;
    if (!isArrayKind) return null;
    final identStart = getIdent(it);
    final identEnd = getEndIdent(it);
    it = it.current.child.tokenIt;
    final exprs = <Expr>[];
    loop(it, () {
      final t = getToken(it);
      if (t.kind != TokenKind.comma) {
        it.moveBack();
      }
      final expr = parseExpr(it);
      exprs.add(expr);

      return false;
    });

    return ArrayExpr(exprs, identStart, identEnd);
  }

  Stmt? parseImportStmt(TokenIterator it) {
    final key = getKey(it);
    if (key != Key.kImport) return null;
    eatLfIfNeed(it);
    final state = it.cursor;
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind == TokenKind.literal && t.literalKind == LiteralKind.kStr) {
        final path = ImportPath(getIdent(it));
        eatLfIfNeed(it);
        if (it.moveNext() && getKey(it) == Key.kAs) {
          eatLfIfNeed(it);
          if (it.moveNext()) {
            if (getToken(it).kind == TokenKind.ident) {
              return ImportStmt(path, name: getIdent(it));
            }
          }
        } else {
          it.moveBack();
          return ImportStmt(path);
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
    // if (!it.moveNext()) return [];
    it = it.current.child.tokenIt;
    final items = <MatchItemExpr>[];

    bool isArrow() {
      if (it.moveNext()) {
        if (getToken(it).kind == TokenKind.eq) {
          if (it.moveNext()) {
            if (getToken(it).kind == TokenKind.gt) {
              it.moveNext();
              return true;
            }
          }
        }
      }
      return false;
    }

    void jump() {
      if (it.moveNext()) {
        final kind = getToken(it).kind;
        if (kind != TokenKind.comma || kind != TokenKind.lf) {
          it.moveBack();
        }
      }
    }

    void common(Expr expr, OpKind? op) {
      eatLfIfNeed(it);
      isArrow();
      if (getToken(it).kind == TokenKind.openBrace) {
        final block = parseBlock(it);
        items.add(MatchItemExpr(expr, block, op));
        jump();
      } else {
        final start = getIdent(it);
        final stmt = parseStmt(it);
        if (stmt != null) {
          final block = Block([stmt], null, start, getIdent(it));
          items.add(MatchItemExpr(expr, block, op));
          jump();
        }
      }
    }

    loop(it, () {
      final t = getToken(it);

      if (t.kind == TokenKind.ident) {
        it.moveBack();
        final expr = parseExpr(it);
        eatLfIfNeed(it);
        common(expr, null);
      } else {
        eatLfIfNeed(it);
        OpKind? op;
        op = resolveOp(it);
        eatLfIfNeed(it);
        final expr = parseExpr(it);
        if (op != null || !expr.hasUnknownExpr) {
          eatLfIfNeed(it);
          common(expr, op);
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

  Stmt? parseWhileExpr(TokenIterator it) {
    final isLoop = getKey(it) == Key.kWhile;
    if (!isLoop) return null;
    final ident = getIdent(it);
    eatLfIfNeed(it);

    final expr = runBraceParseExpr(it);

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
        final opIdent = getIdent(it);
        final rhs = parseExpr(it);
        if (key != null) {
          return ExprStmt(AssignOpExpr(key, opIdent, lhs, rhs));
        } else {
          return ExprStmt(AssignExpr(lhs, rhs));
        }
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
    it.moveBack();

    List<IfExprBlock>? elseIfExprs = parseElseIfExpr(it);
    IfExprBlock? kElse;

    eatLfIfNeed(it);

    final state = it.cursor;

    final hasElse = getKey(it) == Key.kElse;
    if (hasElse) {
      checkBlock(it);
      kElse = IfExprBlock(null, parseBlock(it));
    } else {
      state.restore();
    }

    return IfExpr([ifBlock, ...?elseIfExprs, if (kElse != null) kElse]);
  }

  IfExprBlock parseIfBlock(TokenIterator it) {
    final expr = runBraceParseExpr(it);
    it.moveNext();

    Block block;
    checkBlock(it);
    if (getToken(it).kind == TokenKind.openBrace) {
      block = parseBlock(it);
    } else {
      final stmt = parseStmt(it);

      block = Block([if (stmt != null) stmt], getIdent(it), Identifier.none,
          Identifier.none);
    }
    return IfExprBlock(expr, block);
  }

  Expr runBraceParseExpr(TokenIterator it) {
    return runZoned(() => parseExpr(it), zoneValues: {#brace: true});
  }

  /// ???
  bool canParseStructExpr(TokenIterator it) {
    var onOtherExpr = Zone.current[#brace] == true;

    if (!onOtherExpr) return true;
    final state = it.cursor;
    var result = false;

    eatLfIfNeed(it);
    // 如果紧接着是关键字，不可无视
    loop(it, () {
      final t = getToken(it);

      if (t.kind == TokenKind.openBrace) {
        result = true;
        return true;
      }

      if (getKey(it) != null) {
        result = false;
        return true;
      }

      return false;
    });

    state.restore();
    return result;
  }

  List<IfExprBlock>? parseElseIfExpr(TokenIterator it) {
    List<IfExprBlock>? elseIf;
    loop(it, () {
      final key = getKey(it);
      final t = getToken(it);

      if (t.kind == TokenKind.lf) {
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
          it.moveBack();
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
    var isConst = key == Key.kConst;
    if (!isLet && !isStatic && !isFinal && !isConst) return null;
    if (isStatic) {
      if (it.moveNext()) {
        if (getKey(it) != Key.kConst) {
          it.moveBack();
        }
      }
    }
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
        return StaticStmt(l, r, ty, isConst);
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

    var success = false;

    loop(it, () {
      if (getToken(it).kind == TokenKind.comma) return false;
      if (getToken(it).kind == TokenKind.gt) {
        success = true;
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

    if (!success) {
      state.restore();
      return const [];
    }

    return idents;
  }

  Expr? parseUnaryExpr(TokenIterator it) {
    eatLfIfNeed(it);
    final state = it.cursor;

    final kind = getToken(it).kind;
    final uOp = UnaryKind.from(kind.char);
    if (uOp != null) {
      final ident = getIdent(it);
      return UnaryExpr(uOp, parseExpr(it), ident);
    } else {
      final pointer = PointerKind.from(kind);
      if (pointer != null) {
        final ident = getIdent(it);
        return RefExpr(parseExpr(it), ident, pointer);
      }
    }

    state.restore();
    return null;
  }

  Expr? parseBaseExpr(TokenIterator it) {
    Expr? expr;

    final t = getToken(it);
    if (t.kind == TokenKind.openParen) {
      expr = parseExpr(it.current.child.tokenIt);
    } else if (t.kind == TokenKind.literal) {
      final lit = t.literalKind!;

      Identifier? ident;
      if (lit == LiteralKind.kStr) {
        final tokens = <Token>[];
        loop(it, () {
          final t = getToken(it);
          if (t.kind == TokenKind.lf) return false;
          if (t.kind == TokenKind.literal) {
            final lit = t.literalKind!;
            if (lit == LiteralKind.kStr) {
              tokens.add(t);
              return false;
            }
          }
          it.moveBack();
          return true;
        });

        final buffer = StringBuffer();
        buffer.write(parseStr(getStr(it, token: t)));
        var tokenEnd = t;

        if (tokens.isNotEmpty) {
          tokenEnd = tokens.last;
          for (var token in tokens) {
            buffer.write(parseStr(getStr(it, token: token)));
          }
        }

        ident = Identifier.str(t, tokenEnd, buffer.toString(), fileName);
      }
      expr = LiteralExpr(ident ?? getIdent(it), lit.ty);
    }

    expr ??= parseArrayInitExpr(it);
    expr ??= parseArrayExpr(it);
    expr ??= parseIfExpr(it);
    expr ??= parseMatchExpr(it);
    expr ??= parserStructOrVariableExpr(it);

    return expr;
  }

  Expr parseArrayOpExpr(TokenIterator it, Expr ptr) {
    assert(getToken(it).kind == TokenKind.openBracket);
    final ident = getIdent(it);
    final expr = parseExpr(it.current.child.tokenIt);

    return ArrayOpExpr(ident, ptr, expr);
  }

  /// 解析关键字
  Expr? parseKeyExpr(TokenIterator it) {
    final t = getToken(it);
    if (t.kind == TokenKind.ident) {
      final ident = getIdent(it);
      final key = getKey(it);
      if (key == Key.kBreak || key == Key.kContinue) {
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
        return key == Key.kBreak
            ? BreakExpr(ident, label)
            : ContinueExpr(ident);
      } else if (key == Key.fn) {
        final state = it.cursor;

        final fn = parseFn(it);
        if (fn != null) {
          return FnExpr(fn);
        } else {
          state.restore();
        }
      }
    }
    return null;
  }

  Expr? parserStructOrVariableExpr(TokenIterator it) {
    final t = getToken(it);
    if (t.kind != TokenKind.ident) return null;
    final ident = getIdent(it);
    final key = getKey(it);
    if (key?.isBool == true) {
      final ty = LiteralKind.kBool.ty;
      return LiteralExpr(ident, ty);
    }

    eatLfIfNeed(it);
    final generics = parseGenericsInstance(it);
    Expr expr = VariableIdentExpr(ident, generics);

    final cursor = it.cursor;
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind == TokenKind.openBrace && canParseStructExpr(it)) {
        final struct = parseStructExpr(it, expr);

        if (struct.params case [..., FieldExpr(expr: UnknownExpr())]) {
          cursor.restore();
        } else {
          expr = struct;
        }
      } else {
        cursor.restore();
      }
    }

    return expr;
  }

  Expr parseExpr(TokenIterator it,
      {bool runOp = false, bool isStructExpr = false}) {
    if (!it.moveNext()) {
      return UnknownExpr(it.curentIsValid ? getIdent(it) : Identifier.none, '');
    }

    var baseExpr = parseKeyExpr(it);
    if (baseExpr != null) return baseExpr;

    baseExpr = parseUnaryExpr(it) ?? parseBaseExpr(it);
    if (baseExpr == null) {
      final ident = getIdent(it);
      if (!isStructExpr) {
        Log.e('${ident.light} ${ident.offset}', onlyDebug: false);
      }
      return UnknownExpr(ident, '');
    }

    /// 处理后缀

    eatLfIfNeed(it);
    Expr fnCalls = baseExpr;

    // Function.call().call().call()
    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.dot) {
        fnCalls = parseMethodCallExpr(it, fnCalls);
        return false;
      } else if (t.kind == TokenKind.openParen) {
        fnCalls = parseCallExpr(it, fnCalls);
        return false;
      } else if (t.kind == TokenKind.openBracket) {
        fnCalls = parseArrayOpExpr(it, fnCalls);
        return false;
      }
      it.moveBack();
      return true;
    });
    baseExpr = fnCalls;

    final state = it.cursor;
    if (it.moveNext()) {
      if (getKey(it) == Key.kAs) {
        final asExpr = parsePathTy(it);
        if (asExpr != null) {
          baseExpr = AsExpr(baseExpr, asExpr);
        }
      }
    }

    if (baseExpr is! AsExpr) {
      state.restore();
    }

    eatLfIfNeed(it);

    if (!runOp) {
      final op = parseOpExpr(it, baseExpr);
      if (op != null) {
        baseExpr = op;
      }
    }
    return baseExpr;
  }

  Expr? parseOpExpr(TokenIterator it, Expr lhs) {
    final ops = <(Identifier, OpKind)>[];
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
        final (ident1, op1) = ops[opIndex];
        if (eIt.moveNext()) {
          final (_, op2) = ops[opIndex + 1];
          if (op1.level >= op2.level) {
            cache = OpExpr(op1, ccache, first, ident1);
            eIt.moveBack();
          } else {
            eIt.moveBack(); // back
            eIt.moveBack(); // back first
            final expr = combine();
            cache = OpExpr(op1, ccache, expr!, ident1);
          }
        } else {
          cache = OpExpr(op1, ccache, first, ident1);
          break;
        }
      }
      return cache;
    }

    loop(it, () {
      final op = resolveOp(it);
      if (op != null) {
        final opIdent = getIdent(it);
        final expr = parseExpr(it, runOp: true);
        ops.add(((opIdent, op)));
        exprs.add(expr);
        return false;
      }
      it.moveBack();
      return true;
    });

    if (exprs.length > 2) {
      eIt = exprs.tokenIt;
      return combine() ?? lhs;
    } else if (exprs.length == 2) {
      return OpExpr(ops.first.$2, exprs.first, exprs.last, ops.first.$1);
    }
    return exprs.last;
  }

  FnCallExpr parseCallExpr(TokenIterator it, Expr expr) {
    return FnCallExpr(expr, parseFieldExpr(it));
  }

  List<FieldExpr> parseFieldExpr(TokenIterator it) {
    final fields = <FieldExpr>[];

    assert(getToken(it).kind == TokenKind.openParen, '${getIdent(it)}');
    it = it.current.child.tokenIt;

    eatLfIfNeed(it);

    loop(it, () {
      final t = getToken(it);

      if (t.kind == TokenKind.comma) return false;
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.semi) {
        return true;
      }

      if (t.kind == TokenKind.ident) {
        eatLfIfNeed(it);
        final name = getIdent(it);

        final state = it.cursor;
        if (it.moveNext()) {
          if (getToken(it).kind == TokenKind.colon) {
            final expr = parseExpr(it);
            final f = FieldExpr(expr, name);
            fields.add(f);
            return false;
          }
        }

        state.restore();
      }

      it.moveBack();
      final expr = parseExpr(it);
      final f = FieldExpr(expr, null);
      fields.add(f);

      return false;
    });

    return fields;
  }

  Expr parseMethodCallExpr(TokenIterator it, Expr structExpr) {
    eatLfIfNeed(it);
    it.moveNext(); // .

    final fnOrFieldName = getIdent(it);
    eatLfIfNeed(it);
    if (it.moveNext()) {
      final t = getToken(it);
      if (t.kind != TokenKind.openParen) {
        final expr = StructDotFieldExpr(structExpr, fnOrFieldName);
        it.moveBack();
        return expr;
      }
    } else {
      final expr = StructDotFieldExpr(structExpr, fnOrFieldName);
      return expr;
    }

    // check Syntax
    return MethodCallExpr(fnOrFieldName, structExpr, parseFieldExpr(it));
  }

  /// { }: 由于这个token会回解析到`child`中
  /// 和[parseCallExpr]有点区别
  StructExpr parseStructExpr(TokenIterator it, Expr expr) {
    final fields = <FieldExpr>[];
    it = it.current.child.tokenIt;

    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      if (t.kind == TokenKind.semi) {
        final e = UnknownExpr(getIdent(it), 'is not struct expr');
        fields.add(FieldExpr(e, e.ident));
        return true;
      }

      if (t.kind == TokenKind.comma) return false;

      bool parseCommon() {
        it.moveBack();
        final expr = parseExpr(it, isStructExpr: true);
        final f = FieldExpr(expr, null);
        fields.add(f);
        return expr.hasUnknownExpr;
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
            return parseCommon();
          }
          return false;
        }
      }

      return parseCommon();
    });

    return StructExpr(expr, fields);
  }

  OpKind? resolveOp(TokenIterator it) {
    var chars = '';
    if (getToken(it).kind != TokenKind.lf) {
      chars = getIdent(it).src;
    }
    OpKind? lastOp;
    final state = it.cursor;
    loop(it, () {
      final t = getToken(it);
      if (t.kind.char.isEmpty) {
        it.moveBack();
        return true;
      }
      final text = chars + getIdent(it).src;
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

    // // 处理未知操作符
    // loop(it, () {
    //   final t = getToken(it).kind;
    //   final op = OpKind.from(t.char);
    //   if (op != null) return false;
    //   it.moveBack();
    //   return true;
    // });

    final op = lastOp ?? OpKind.from(chars);
    if (op == null) {
      state.restore();
    }
    return op;
  }

  List<GenericDef> parseGenerics(TokenIterator it) {
    final generics = <GenericDef>[];
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
            final list = parsePathTyList(it);
            generics.add(GenericDef(ident, list));
          } else {
            generics.add(GenericDef(ident, const []));
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

  List<PathTy> parsePathTyList(TokenIterator it) {
    final list = <PathTy>[];

    for (;;) {
      final ty = parsePathTy(it);
      if (ty == null) break;
      list.add(ty);

      if (!it.moveNext()) break;
      eatLfIfNeed(it, back: false);

      final k = getToken(it).kind;
      if (k == TokenKind.comma || k == TokenKind.gt) break;
      assert(k == TokenKind.plus);
    }

    return list;
  }

  StructTy? parseStruct(TokenIterator it) {
    eatLfIfNeed(it);

    if (!it.moveNext()) return null;
    final ident = getIdent(it);

    eatLfIfNeed(it);

    final types = parseGenerics(it);

    eatLfIfNeed(it);

    var fields = <FieldDef>[];
    it.moveNext(); // {
    if (getToken(it).kind == TokenKind.openBrace) {
      it = it.current.child.tokenIt;
      fields = parseFieldDefList(it);
    }

    return StructTy(ident, fields, types);
  }

  EnumTy? parseEnum(TokenIterator it) {
    eatLfIfNeed(it);

    if (!it.moveNext()) return null;
    if (getToken(it).kind != TokenKind.ident) return null;
    final ident = getIdent(it);

    final types = parseGenerics(it);

    it.moveNext();

    it = it.current.child.tokenIt;

    final variants = <EnumItem>[];
    loop(it, () {
      final t = getToken(it);
      if (t.kind == TokenKind.lf) return false;
      // e.g. Some
      if (t.kind == TokenKind.ident) {
        final item = parseEnumItem(it);
        variants.add(item);
      }
      return false;
    });

    return EnumTy(ident, variants, types);
  }

  EnumItem parseEnumItem(TokenIterator it) {
    final ident = getIdent(it);

    final types = parseGenerics(it);
    eatLfIfNeed(it);
    it.moveNext(); // (
    final t = getToken(it);

    if (t.kind != TokenKind.openParen && t.kind != TokenKind.openBrace) {
      return EnumItem(ident, [], types);
    }

    it = it.current.child.tokenIt;

    return EnumItem(ident, parseFieldDefList(it), types);
  }

  List<FieldDef> parseFieldDefList(TokenIterator it) {
    final fields = <FieldDef>[];

    loop(it, () {
      final k = getToken(it).kind;
      if (k == TokenKind.ident) {
        final name = getIdent(it);

        final state = it.cursor;
        it.moveBack();
        final nameOrTy = parsePathTy(it);

        if (nameOrTy != null) {
          final hasNext = it.moveNext();
          eatLfIfNeed(it, back: false);
          if (!hasNext || getToken(it).kind != TokenKind.colon) {
            fields.add(FieldDef(Identifier.none, nameOrTy));
            return false;
          }

          state.restore();
        }

        it.moveNext();

        final ty = parsePathTy(it) ?? UnknownTy(getIdent(it));
        fields.add(FieldDef(name, ty));
        return false;
      }

      return false;
    });

    return fields;
  }

  /// 跳过中间的换行符
  void eatLfIfNeed(TokenIterator it, {bool back = true}) {
    if (it.curentIsValid && getToken(it).kind != TokenKind.lf) return;
    loop(it, () {
      final k = getToken(it).kind;
      if (k != TokenKind.lf) {
        if (back) it.moveBack();
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
  dyn('dyn'),
  struct('struct'),
  kEnum('enum'),
  kStatic('static'),
  kConst('const'),
  kImpl('impl'),
  kComponent('com'),
  kRet('return'),
  kExtern('extern'),
  kFinal('final'),

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
