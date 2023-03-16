import 'package:llvm_dart/parsers/parser.dart';

void main() {
  final s = '''
fn main() int   {
  foo("ss", 101,)
  let x = 1
  let y = Gen{"string"}
  y.foo()
  0
}

fn foo(name: string key: double,) int {
  let y = 101
}
sfsfs 
static s = "xxx"


static yy = Gen{"fsfs", 102,}
static y =      "yyy",hello = 'world'
static s
= 01

struct Gen {
  name: string,
  value: double,
}

''';
  final parser = Parser(s);
  parser.parse();
  print(parser.globalVar.join('\n'));
  print(parser.globalStruct);
  print(parser.globalFunction);
}
