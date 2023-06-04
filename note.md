
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
