import 'dart:async';
import 'dart:ffi';

import 'package:llvm_dart/ast/analysis_context.dart';
import 'package:llvm_dart/ast/buildin.dart';
import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/llvm_context.dart';
import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/llvm_core.dart';
import 'package:llvm_dart/llvm_dart.dart';
import 'package:llvm_dart/parsers/lexers/token_kind.dart';
import 'package:llvm_dart/parsers/lexers/token_stream.dart';
import 'package:llvm_dart/parsers/parser.dart';
import 'package:nop/nop.dart';
import 'package:test/test.dart';

// ignore: unused_import
import 'str.dart';

void main() {
  test('token', /* ffsfsfsd */ () {
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
    var srxc = '''
// extern fn printxx(y: int);

struct Gen {
  y: &int,
};

// fn prxx(y: u64) {
//   // let x = y + 10u64;
// };

fn main() int {
  // let hx = (10 + y().call((2 + 3).callIn())).call2()
  // let hxaa = (50 + y(10,y, (10 * (50 + 22)).call()))
  // test: expr
  // let hh = Gen {y: y(x,10,22, hhxx.dd())}
  //  let x = (10 + y((y *(*(30 + 66) / hall.call(yyy, xxxx, (y + x * 10)))).call())) * 30 / (40 + 50) * 111 / (10 + hh.fnxx(1,2) ) * 444
  // let z =1  * (*(1 + /* hello */ 20)).x()  - 1
  /// TODO: 
  // let y = 10.d + 20.d
  // let x: i64 = 11111111111
  // let hhx: i64 = 1
  // let z: i64 = (1 << 63 ) - 1
  // printxx(z)
  // Gen {y: 11, x: pinfs(y: 22)}
  // let unn = 10 * (10 * (-20 * (30 + yy.call() + Gen {y: 10, 2424}) + 50) + 50)
  // printxx(y: 110);
  // let y = -10.;
  // final yy = y;

  // let x = 12u8 + 22_u8;
  // let y = 10.000e+1_double;
  // let yusize = 111usize
  // let gg = Gen {y: &11}
  // final yyy = 10i16
  // let yyRef = &120;
  struct My {x: fn()}
  let my = My {x: hell}
  let y = my.x;
  y();
  let yy:fn() = hell;
  yy();
  my.x();
  printxx(11)
  0;
}

fn hell() {
}
''';

    return runZoned(
      () {
        final m = parseTopItem(src);
        print(m.globalTy.values.join('\n'));
        // return;
        llvm.initLLVM();
        final root = BuildContext.root();
        // BuildContext.mem2reg = true;
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

  test('analysis', () {
    final src = '''
extern fn printstr(str: string);
fn main() int {
  let y = "24242nihao"
  let hh = true;
  let xa = 102;

  if hh {
    printstr(&y);
  }
  0;
}
''';
    runZoned(
      () {
        final m = parseTopItem(src);
        print(m.globalTy.values.join('\n'));
        // return;
        final root = AnalysisContext.root();
        root.pushAllTy(m.globalTy);
        for (var fns in root.fns.values) {
          for (var fn in fns) {
            fn.analysis(root);
          }
        }
        {
          llvm.initLLVM();
          final root = BuildContext.root();
          // BuildContext.mem2reg = true;
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
        }
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

final srxc = '''
extern fn printxx(y: int);

fn main() int {
  let xx = 11;
  let yy = xx;
  let xa = &1221;
  let hhhxx = xa;
  fn second() {
    // let xhh = xx;
    // let xafa = yy;
    // printxx(yy);
    // printxx(*xa);
    // let yy = xa;
    // let haf = *xa;
    // printxx(haf);
    // let hh = *xa;
    // printxx(xafa);
    // let hhhe = xa;
    // let eq = xx;
    // printxx(eq);
    // let hhhv = *hhhe;
    // printxx(hhhv);
    // printxx(*xa);
    // let yyx = *hhhe;
    // printxx(yyx);
    // printxx(*hhhe);
    // *xa = 111;
    // let hyyx = *xa;
    // printxx(*xa);
    let a = xa;
    printxx(*a);
    // *xa = 111;
    // let ab = *xa;
    // printxx(ab);
    // let y = *xa;

    fn hhhxx() {
      let hhh = a;
      printxx(*hhh);
      printxx(8888888);
    }
    hhhxx();
  }
  // second();
  // printxx(*xa);
  // *xa = 5554;
  // second();
  fn hell() {
    let yyys = 1144441;
    // // xx = 223131;
    // // printxx(43434);
    // printxx(yyys);
    second();
    // printxx(*xa);

    fn hellInner() {
      let hhin = yyys;
      yyys = 5555;
      printxx(hhin);
      printxx(yyys);
    }

    hellInner();
  }
  // let hh = 1002;
  // // fn outer() {
  // //   second();
  // //   let o_hh = hh;
  // // }
  hell();
  inner(hell, &666); // hell: main scope
  // // // inner(outer);
  // *xa = 5555;
  inner(hell, &1144);
  // hell();
  0
}

// main::inner
// fn main::inner(f: fn()) {
//   // f: life time: main::inner
// }
//
//

fn inner(f: fn(), y: &int) {
  // f: life time: inner
  printxx(111);
  let yyx = 4343;
  printxx(yyx);
  f();
  printxx(*y);
}
''';
