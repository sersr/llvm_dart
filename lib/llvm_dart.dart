// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';

import 'fs/fs.dart';
import 'llvm_core.dart';

const LLVMTrue = 1;
const LLVMFalse = 0;

extension LLVMBool on bool {
  int get llvmBool {
    return this ? LLVMTrue : LLVMFalse;
  }
}

LLVMCore get llvm => LLVMInstance.getInstance();

class LLVMInstance {
  LLVMInstance._();

  static LLVMCore? _bindings;

  static LLVMCore getInstance() {
    if (_bindings != null) return _bindings!;
    DynamicLibrary library;
    var dir = currentDir
        .childDirectory('llvm_lang')
        .childDirectory('install')
        .childDirectory('lib');

    var name = 'libllvm_wrapper.dylib';
    if (Platform.isWindows) {
      name = 'llvm_wrapper.dll';

      final bin = currentDir
          .childDirectory('llvm_lang')
          .childDirectory('install')
          .childDirectory('binx');

      final file = bin.childFile(name);
      if (file.existsSync()) {
        dir = bin;
      } else {
        dir = currentDir.childDirectory('dll');
      }
    } else if (Platform.isLinux) {
      name = 'libllvm_wrapper.so';
    }
    final p = dir.childFile(name);
    library = DynamicLibrary.open(p.path);
    return _bindings = LLVMCore(library);
  }
}
