var src = '''
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
  fn selfM(y: int) {
    let yy = self
    let ss = (*self)
    printxx(ss.z)
  }
}

extern fn yy(y: int, g: Gen) {
  let gg = g
  let hss = gg.z
  let haxs = y + (123  + 1313) * 22;
  &g;
  gg.y = 102
  gg.x = 6556
  gg.z = 6772
  gg.selfM(22)
  printxx(hss)
  printxx(y)
  hss = y
  printxx(hss)
  &hss;
  printxxa(&hss)
  let hhx = &hss
  printxx(*hhx)
  printxxa(hhx)
}

fn ysys(g: Gen) {

}


fn haha(y: &int) {
  let yy = &y;
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
