import 'dart:ffi';

import 'package:llvm_dart/ast/context.dart';
import 'package:llvm_dart/ast/llvm_context.dart';
import 'package:llvm_dart/ast/memory.dart';
import 'package:llvm_dart/llvm_core.dart';
import 'package:llvm_dart/llvm_dart.dart';
import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

// ignore: unused_import
import 'str.dart';

void main() {
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

fn main() int {
  let y = 101
  let x = 55;
  loop {
    let lox = 101
    if x > 1001 {
      if y < 0001 {
        let yxx = 101010
      }
      break
    }
  }
  let rrry = 4433;

  loop {
    if x > 110 {
      break;
    }
    continue;
  }
  while x > 10 {
    let haha: string = "while test"
    if y > 10 {
      continue
    }
    break
  }

  0
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
    testRun(src);
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

  test('test src', () {
    testRun(src);
  });

  /// cc ./base.c ./out.o -o main
  /// ./main
  test("control flow", () {
    var src = '''
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

    testRun(src);
  });

  test('analysis', () {
    var mem2reg = true;
    var build = true;

    final src = r'''
extern fn printstr(str: string);
extern fn printxx(y: int);
fn main() int {
  // let y = '1\"\\'
  // let hh = true;
  // let yy = &y;
  // let yyy = &yy;
  // let yyyy = &yyy;
  // let hyyy = *yyyy;
  // let xa = 102;

  // if hh {
  //   printstr(y);
  //   printstr(*yy);
  //   printstr(**yyy);
  //   printstr(***yyyy);
  //   printstr(**hyyy);
  //   let xx = 1044;
  //   hhx(&&xx);
  //   let xyy = &xx;
  //   let xy = *xyy;
  //   printxx(xx);
  //   printxx(*xyy);
  // } xa += 1
  // {
  //   let yy = 11312;
  // }
  0
  }

// fn hhx(y: &&int) {
//   let yy = *y;
//   printxx(*yy);
//   *yy = 55555;
//   printxx(*yy);
//   printxx(**y);
//   // let nxyy = *yy;
//   // let xx  = **y;
//   // printxx(*yy);
//   // printxx(**y);
// }
''';
    testRun(src, mem2reg: mem2reg, build: build);
  });

  test('impl', () {
    final src = '''
extern fn printxx(y: int);
extern fn printstr(y: string);
struct Gen {
  y: int,
  h: int,
}

impl Gen {
  fn hello() {
    let hh = (*self).y;
    printxx(hh);
  }
}

fn main() int {
  let g = Gen {10, 11};
  g.hello();
  0;
}
''';
    testRun(src);
  });

  test('fn', () {
    final src = '''
extern fn printxx(y: int);

fn main() int {
  let xa = 44343;
  let yya = 4422;
  let xya = &444;
  let xxya = &xya;
  fn hha() {
    // let xxa = xa;
    let hh = xya;
    let hhx = *hh;
    printxx(*hh);
    printxx(**xxya);
  }

  fn sec() {
    let yy = yya;
    hha();
    printxx(yy);
  }
  hhxa(sec);
  0;
}

fn hhxa(f: fn()) {
  f();
}
''';
    testRun(src);
  });
}
