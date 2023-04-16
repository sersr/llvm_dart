import 'package:llvm_dart/run.dart';
import 'package:test/test.dart';

void main() {
  test('test', () {
    final src = '''
extern fn printxx(y: i32);
extern fn printfp(x: f32);

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

enum Option {
  Some(f32, i32),
  Other(i32, i32),
  None(i32,i32,i32),
  Hello(i32, i64,i32, i32),
}
''';
    testRun(src, build: true);
  });
}
