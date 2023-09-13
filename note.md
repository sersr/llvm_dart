
#

## note

1. 堆栈上的指针不可逃离作用域

    ```rust
      fn function() &i32 {
        let y = 10;
        let y_ref = &y;

        return y_ref; // error
      } // y drop

      fn main() {
        let y_ref = function();
      }
    ```

2. 数组下标访问

// todo

3. 自动管理堆的生命周期

原型：

  ```rust

    fn malloc(size: usize);
    fn free(ptr: *void);


    // 实际是一个指针
    type HeapPointer<T> = *HeapCount<T>;

    struct HeapCount<T> {
      count: usize,
      start: usize,
      data: T,
    }

    impl HeapCount<T> {

      /// 具体实现应该没有 [data] 实例
      /// 由编译器实现
      static fn init(data: T) HeapPointer<T> {
        let size = sizeOf(T);

        let pointer = malloc(size) as HeapPointer<T>;

        /// data 为初始化列表；
        /// 由 LLVM IR 实现赋值过程
        *pointer = HeapCount {count: 1, data: data};
        return pointer;
      }

      static fn from(data: T) HeapPointer<T> {
        let size = sizeOf(T);

        let pointer = malloc(size) as HeapPointer<T>;

        /// data 为初始化列表；
        /// 由 LLVM IR 实现赋值过程
        *pointer = HeapCount {count: 1, data: data};
        return pointer;
      }
      
      
      fn addStack() {
        count += 1;
      }

      fn removeStack() {
        count -=1;
        if(count <= 0) {
          free(&data);
        }
      }
    }

    struct Base {
      y: i32,
    }

    struct Data {
      base: HeapPointer<Base>,
      x: i32, 
    }

    impl Data {
      fn rr() &i32 {
        &self.x;
      }
    }

    fn test_heap() HeapPointer<Base> {
      let data = new Base{ y: 100 };

      if condition {
        let newData = new Base {y: 200};
        /// call newData.addStack
        return newData;
        /// call data.removeStack
        /// call newData.removeStack
      }

      /// call data.addStack
      return data;
      /// call data.removeStack
    }

     fn test_anonymous_heap() fn() {
      let data = new Base{ y: 100 };
      
      /// 自动捕获 `data`，并且跟踪生命周期
      fn anonymous() {
        /// ...
        data;
        /// ...
      }

      /// call data.addStack!
      return anonymous;
      /// call data.removeStack
    }

    fn test_inner_heap() Data {
      let base = new Base { y: 100 };

      /// noop
      let data = Data { base: base, x: 200 };

      let baseX = &base.x;
      if true {

        let base2 = base;
        /// noop
        return data;
      }

      /// noop
      let data2 = Data { base: base, x: 200 };

      /// noop
      return data2;
    }


    fn main() i32 {
      let heapData = test_heap();


      /// heapFn struct like: struct {fnPointer: fn(data: HeapPointer<Base>) -> void, data: HeapPointer<Base> }
      let heapFn = test_anonymous_heap();

      /// like: heapFn.fnPointer(heapFn.data);
      heapFn();
      0;
      /// call heapData.removeStack
      /// heapFn.data.removeStack
    }

  ```

增加 `count` 字段对函数栈进行计数，将堆和函数栈紧密结合起来，在函数返回之前调用相应函数，当 `count <= 0` 时，释放资源；

函数返回，返回匿名函数都会增加次数

实现方法：

- 第一种：在 Block `{}` 的上下文中处理相关函数调用；生命周期规则细化到每个`Block`，不在只是函数体的顶层 `{}`处理；
- 第二种：跟踪每个变量的生命周期，判断生命周期末尾的方式：
    
    - 默认计数 - 1，若 `count <= 0` 释放资源
    - 被其他对象拷贝时，计数 + 1，如果原来变量之后不在被使用可不计数
    - 以值的方式返回，不做处理

