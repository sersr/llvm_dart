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
    printxx(yy.z)
    self.hhhxxx();
  }
  fn hhhxxx() {
    printxx(6666);
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
  printxxa(&11)
}

fn ysys(g: Gen) {
  fn hh() {
    let yy = 10;
  }
}


fn haha(y: &int) {
  let yy = &y;
}

struct Gen {
  y: i32,
  x: i32,
  z: i32,
}
fn de() {
  printxx(101)
}

fn main() int {
  stra()
  struct MyG {
    x: fn (),
  }
  let yyx = MyG{fn zz() {
    printxx(444);
  }}
    // let hh = yyx.x;
  yyx.x();
  let y = 1;
  y += 2 + 111102 - 5550 / 11;
  return 0
}

''';

var xx = '''

struct Box<T> {
  count: int,
  
}

impl Box<T> {
  static fn new(v: T) Box<T> {

  }
}

// TODO: 实现匿名函数，变量捕捉
fn main() i32 {
  let y = 10;

  let head:Box<Gen> = new Gen {10, 11};


  fn anonymous() {
    printxx(y);
  }
}

// 生命周期检测由分析器完成

fn life(y: &int) &int {
  let x = &11;
  let yy = y;
  return x; // error: 生命周期超出范围
  return yy; // success: 生命周期匹配
  let max = life2(y, x);
  return max; // error: 短生命周期不可被返回
}

fn life2(y: &int, x: &int) &int {
  let yy = &110; // 生命周期只在当前函数范围内
  if * y < * x {
    x;
  }else {
    y;
  }
} // yy 清除

fn lifeBox(y: Box<int>) Box<int> {
  let x = new 11;
  let yy = y;
  return x; // success
  return yy; // success
}

''';
