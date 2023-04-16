import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('test', () {
    final src = '''
extern fn printxx(y: i32);
extern fn printfp(x: f32);
extern fn print64(x: i64);

fn main() int {
  final yy = Some(15, 2);
  final xx = None();
  // final yxa = Hello();
  let other = Other(10, 11);
  let y = sizeOf(xx);
  printxx(y as i32);
  printxx(sizeOf(yy) as i32)

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
}
