# llvm_dart

使用 LLVM 作为后端，dart 为前端实现一个简易的编程语言。

llvm version: 16.0.6


## 使用步骤

- cd llvm_lang
- cmake --build  ./build --config Debug --target install
- cd ..

运行在 `kc/bin` 目录下的文件, 在根文件夹下：
- dart run bin/run.dart stack_com
