import 'dart:async';
import 'dart:ffi';

import 'package:llvm_dart/ast/buildin.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/llvm_context.dart';
import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/llvm_core.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:llvm_dart/parsers/parser.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

void main() {
  test('token', () {
    final s = '''
fn main() int {
  let x: string = 1
}

啊发发发
"helloss 你啊"
struct Gen<T> {
  name: string,
  value: int,
}

''';
    final cursor = Cursor(s);
    final tokens = <Token>[];
    while (true) {
      final token = cursor.advanceToken();
      tokens.add(token);
      print(token);
      if (token.kind == TokenKind.eof) {
        break;
      }
    }
    for (var t in tokens) {
      if (t.kind == TokenKind.eof) continue;
      if (t.kind != TokenKind.unknown) continue;
      print('unknown:${s.substring(t.start, t.end)}');
    }
  });

  test('token reader', () {
    final src = r'''

static hello = "world"
static hhh: string = "nihao"
com Indd {
  fn build() int
  fn build2(name: string) void
}

impl Indd for Gen {
  fn build() int {
    let y = 1001
  }

  fn build2(name: string, )  {}
}

fn main(vv: string,) int {
  let yx = 1 * (120 - 10)
  g.fxx(name: 1010)
  y += 102
  y >= 10
  let ss = ( 1 + 2) * 64
  let x: string = "10122"
  let ss = ( 1 + 2) * 64
  let y = 101
  if 10 < 10 {
    
  }

  loop {
    let lox = 101
    if x > 1001 {
      if y < 0001 {
        let yxx = 101010
      }
      break
      break ccs
    }
  }

  while x > 10 {
    let haha: string = "while test"
    if y > 10 {
      continue
    }
    break
  }

  fn innerFn() {
    let innerY = 5501
  }
  if y > 10 {
    y = x + 1
  } else if y <=x 11 {
    y = Gen {name: "hello"}
    Gen {name: 'davia'}
    g.fxx(name: 1010)
    g.fyx()
    fyy()
  } else if h > 0 {
  } else {
    y = foo("sfs")
    foo(name: "nihao")
  }
}

fn foo() {

}

struct Gen {
  name: string,
  index: int,
}

enum Lang {
  En(string),
  zh
  (
    string
    ),
  Else(),
  None,
}
''';
    // LevelMixin.padSize = 2;
    final m = parseTopItem(src);
    runZoned(() {
      print(m.globalVar.values.join('\n'));
      print(m.globalTy.values.join('\n'));
      final analys = BuildContext.root();

      analys.pushAllTy(m.globalTy);

      Log.w('-' * 60, showPath: false, showTag: false);
      print(analys.fns);
      print(analys.components);
      print(analys.impls);
      print(analys.structs);
      print(analys.enums);
    }, zoneValues: {'astSrc': src});
  });

  test('test name', () async {
    llvm.initLLVM();
    final context = BuildContext.root();

    final builder = context.builder;
    final C = context.llvmContext;
    final retTy = llvm.LLVMDoubleType();
    final fnty = llvm.LLVMFunctionType(retTy, <Pointer>[].toNative(), 0, 0);
    final fn = llvm.getOrInsertFunction('main'.toChar(), context.module, fnty);
    final bb = llvm.LLVMAppendBasicBlockInContext(C, fn, 'entry'.toChar());
    llvm.LLVMPositionBuilderAtEnd(builder, bb);

    final then = llvm.LLVMAppendBasicBlockInContext(C, fn, 'then'.toChar());
    final elseF = llvm.LLVMAppendBasicBlockInContext(C, fn, 'else'.toChar());
    final after = llvm.LLVMAppendBasicBlockInContext(C, fn, 'after'.toChar());

    final t = llvm.LLVMInt32Type();
    final t2 = llvm.LLVMInt32Type();
    final l = llvm.LLVMConstInt(t, 10, 32);
    final r = llvm.LLVMConstInt(t2, 101, 32);
    final con = llvm.LLVMConstICmp(LLVMIntPredicate.LLVMIntULT, l, r);
    llvm.LLVMBuildCondBr(builder, con, then, elseF);

    llvm.LLVMPositionBuilderAtEnd(builder, then);
    llvm.LLVMBuildBr(builder, after);
    llvm.LLVMPositionBuilderAtEnd(builder, elseF);
    llvm.LLVMBuildBr(builder, after);
    llvm.LLVMPositionBuilderAtEnd(builder, after);

    final dt = llvm.LLVMDoubleType();
    final lr = llvm.LLVMConstReal(dt, 0);

    llvm.LLVMBuildRet(builder, lr);
    // llvm.LLVMBuildRetVoid(builder);
    // llvmC.pushAllTy(m.globalTy);
    // for (var fn in llvmC.fns.values) {
    //   for (var f in fn) {
    //     print(f);
    //     f.build(llvmC);
    //   }
    // }
    llvm.writeOutput(context.kModule);
    llvm.destory(context.kModule);
  });

  /// cc ./base.c ./out.o -o main
  /// ./main
  test("control flow", () {
    final src = '''
fn printxx(y: int)int
fn printxxa(y: &int)int
fn strx(hh: int, g: &Gen)
extern fn stra()
fn getGen()Gen
fn ggg()

fn hhh() int {
  12
}

impl Gen {
  static fn new() Gen {
    Gen {15, 18, 55}
  }

  fn compl() i32 {
    let y = self.y
    y
  }
}

extern fn yy(y: int, g: Gen) {
  let gg = g
  let hss = gg.z
  gg.y = 102
  gg.x = 6556
  gg.z = 6772
  printxx(hss)
  printxx(y)
  hss = y
  printxxa(&hss)
  printxx(hss)
}
struct Gen {
  y: i32,
  x: i32,
  z: i32,
}

fn main() int {
  stra()
  return 0
}

''';
    final m = parseTopItem(src);
    return runZoned(
      () {
        print(m.globalTy.values.join('\n'));
        llvm.initLLVM();
        final root = BuildContext.root();
        root.pushAllTy(m.globalTy);
        root.pushFn(sizeOfFn.ident, sizeOfFn);

        for (var fns in root.fns.values) {
          for (var fn in fns) {
            fn.build(root);
          }
        }
        for (var impls in root.impls.values) {
          for (var impl in impls) {
            impl.build(root);
          }
        }
        llvm.LLVMDumpModule(root.module);
        llvm.writeOutput(root.kModule);
        root.dispose();
      },
      zoneValues: {'astSrc': src},
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        Zone.root.print(line.replaceAll('(package:llvm_dart/', '(./lib/'));
      }),
    );
  });
}

void forE(TokenTree tree, String src, {int padWidth = 0, bool isMain = false}) {
  final token = tree.token;
  for (var token in tree.child) {
    forE(token, src, padWidth: padWidth + 2);
  }

  final str = src.substring(token.start, token.end);

  print('${' ' * padWidth}$str  ->  $token');
}
