import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() async {
  test('test', () {
    final src = '''
extern fn printxx(y: i32);
extern fn printfp(x: f32);
extern fn print64(x: i64);
extern fn printf(str: string, ...) i32;
fn main() int {
  final yy = Some(15, 2);
  final xx = None();
  // final yxa = Hello();
  let other = Other(10, 11);
  let y = sizeOf(xx);
  printxx(y as i32);
  printxx(sizeOf(yy) as i32)
  let hxx = 33;
  printxx(sizeOf(hxx as i64) as i32)
  let yc = "hello %d x %f world\n";
  let pr = printf(yc,33, 664422.0);
  printf("ret %d\n", pr);
  match yy {
    Other(y,x) => printxx(y),
    Some(y,x) => {
      printxx(y as i32);
      printfp(y);
      printxx(x as i32);
    }
  }

  0;
}

extern fn gn(g: Gen) {
  printxx(g.x);
  printxx(g.y as i32);
  print64(g.y);
}

extern
struct Gen {
  x: i32,
  y: i64,
}

enum Option {
  Some(f32, i32),
  Other(i32, i32),
  None(i32,i32,i32),
  Hello(i32, i64,i32, i32),
}

fn hello() {
  printxx(44);
}
''';
    testRun(src, build: true);
  });

  test('test printf', () async {
    final src = r'''
extern fn printf(str: string, ...) i32;

fn main() i32 {
  // // let str  = "hello world \\\\ code\n";
  // // printf(str);
  // let yx = Some(555, Gen{y: 33,h: 5222, x: 5555});
  // let g = Gen{y: 122, x: 666, h: 4444};
  printG()
  // match yx {
  //   Some(y, g) => {
  //     printf("y: %d, g.y: %d g.x: %d, \
  //     g.h: %d\n", y, g.y, g.x, g.h);
  //   },
  //   None() => {
  //     printf("none\n");
  //   }
  // }

  final xy = ppx(33);
  printf("ppx: %d, x: %d, h: %d\n", xy.y, xy.x, xy.h);
  final xy = ppx(21);
  printf("ppx: %d, x: %d, h: %d\n", xy.y, xy.x, xy.h);

 return  0;
}

fn ppx(y: i32) Gen {
  if y < 22 {
  let y= Gen {1,2,3}
  return y;
  }else {
    let xx = Gen {55, 66,77};
    return xx;
  }
}

extern fn yy(g: &Gen) Gen {
  let gg = g;
  printf("gg: %d\n", gg.y);
  printf("g.y: %d, g.x: %lld, g.h: %d\n", g.y, g.x, g.h):
  g.y = 66644;
  printC(*g);
  let y =  Gen {3,4 ,5}
  // printC(y);
  y
}

extern fn printC(g: Gen) {
  let hh = g;
  printf("hell o %d\n", hh.h);
  printf("printC: g.y: %d, g.x: %d\
  , g.h: %d\n", g.y, g.x, g.h);
}
extern fn printG();

extern
struct Gen {
  y: i32,
  x: i64,
  h: i32,
}
// enum Option {
//   Some(i32,Gen),
//   None(),
// }
''';
    testRun(src, mem2reg: true);
    await runCode();
  });
}
