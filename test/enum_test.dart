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
  // let str  = "hello world \\\\ code\n";
  // printf(str);
  let yx = Some(555, Gen{y: 33,h: 5222, x: 5555});
  let g = Gen{y: 122, x: 666, h: 4444};
  printG(g)
  match yx {
    Some(y, g) => {
      printf("y: %d, g.y: %d g.x: %d, \
      g.h: %d\n", y, g.y, g.x, g.h);
    },
    None() => {
      printf("none\n");
    }
  }
  0;
}

extern fn printC(g: Gen) {
  printf("printC: g.y: %d, g.x: %d\
  , g.h: %d\n", g.y, g.x, g.h);
}
extern fn printG(g: Gen);

struct Gen {
  y: i32,
  x: i64,
  h: i32,
}
enum Option {
  Some(i32,Gen),
  None(),
}
''';
    testRun(src);
    await runCode();
  });
}
