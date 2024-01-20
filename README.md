***


使用 LLVM 作为后端，dart 为前端实现一个简易的编程语言。

通过 dart FFI 和 `ffi_gen` 调用 LLVM-C 接口；
在dart端处理词法分析、构建模块并生成 .o 目标文件然后使用`clang`完成链接，生成一个可执行文件。

llvm version: >= 16.0.6

在根文件夹下可以简单运行：
```sh
dart run bin/run.dart stack_com
```
stack_com.kc 在 `kc/bin` 文件夹下

测试 所有kc文件：

```sh
dart test test/test_all_test.dart 
```

在运行之前要做一些准备

## windows
需要安装Visual Studio, Window SDK, msys2

### 安装 msys2:
 - scoop install msys2 [scoop](https://scoop.sh/)
 - 官网下载 [msys2](https://www.msys2.org/)

### msys2 三种环境: clang64(推荐) mingw64 ucrt64

选择一个配置环境:  
打开cmd/pwsh
## pacman:
```sh
clang64
pacman -S mingw-w64-clang-x86_64-toolchain mingw-w64-clang-x86_64-llvm mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja mingw-w64-clang-x86_64-zstd mingw-w64-clang-x86_64-zlib
```

`clang64`toolchain默认包含`clang`,其他环境使用`gcc`,所以这里需要在`mingw64`环境下装一个`clang`:
```sh
pacman -S mingw-w64-x86_64-clang
```

## pacboy:
首先安装 [pactoys](https://www.msys2.org/docs/package-naming/):
```sh
pacman -S pactoys
```
使用`:p`省略前缀:

`clang64`:
```sh
pacboy -S toolchain:p llvm:p ninja:p cmake:p zlib:p zstd:p
pacman -S mingw-w64-x86_64-lldb
```
`lldb`调试使用，`mingw64`的`lldb`好像支持中文，比较好用

接着进入[llvm_lang](./llvm_lang/)目录:
```sh
cmake -S. -B build -G Ninja
ninja -C build install
cd ..
```
注意在执行`dart run bin/run.dart `时，确保和上面是同一个环境

## 调试
参数添加`-g`开启调试；
如果不是`clang64`环境，`lldb`好像有些问题，可以使用`gdb`

## Mac

直接使用brew安装
```zsh
brew install llvm
```
之后使用 vscode 打开 `llvm_lang`项目运行`install`完成安装。


