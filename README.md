***


使用 LLVM 作为后端，dart 为前端实现一个简易的编程语言。

通过 dart FFI 和 `ffi_gen` 调用 LLVM-C 接口；
在dart端处理词法分析、构建模块并生成 .o 目标文件然后使用`clang`完成链接，生成一个可执行文件。

llvm version: 16.0.6

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
需要安装Visual Studio, Window SDK, llvm

安装 llvm:

    scoop install llvm

### 使用预编译的 dll

下载 dll
```pwsh
curl https://github.com/sersr/llvm_lang/releases/download/0.1.0/llvm_wrapper.zip -o llvm_wrapper.zip
7z e .\llvm_wrapper.zip -odll
```
或手动解压并添加到PATH中
```pwsh
$env:path="$(Get-Location)\dll;$env:path"
```

### 编译
安装 `vcpkg`

    scoop install vcpkg

vcpkg 安装 `llvm`，LLVM官方windows默认不包括共享库
```pwsh
vcpkg install llvm[target-all]
```
在使用 cmake 中添加 `-DCMAKE_TOOLCHAIN_FILE=/path/to/scripts/buildsystems/vcpkg.cmake`  
推荐使用 vscode，在 settings.json 中添加
```json
    "cmake.configureArgs": [
        "-DCMAKE_TOOLCHAIN_FILE=/path/to/scripts/buildsystems/vcpkg.cmake",
         "-DCMAKE_INSTALL_PREFIX=./install"
    ],
```
安装 [cmake-tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cmake-tools)

打开`llvm_lang`项目，选择 Release，配置完成之后，生成目标选择`install`并运行，完成后会将所需的dll文件复制到`./install/bin`路径中，接着将这个添加到环境PATH路径中
```pwsh
$env:path=$(Get-Location)\install\bin;$env:path"
```

## Mac

直接使用brew安装
```zsh
brew install llvm
```
之后使用 vscode 打开 `llvm_lang`项目运行`install`完成安装。


