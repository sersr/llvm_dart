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
    final src = '''
extern fn printf(str: string, ...) i32;

fn main() i32 {
  printf('hello world code %d \n', 55);
  0;
}
''';
    testRun(src);
    await runCode();
  });
}
