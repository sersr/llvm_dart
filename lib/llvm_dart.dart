// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'package:file/local.dart';
import 'package:llvm_dart/llvm_core.dart';

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
    var dir = LocalFileSystem().currentDirectory;
    assert(() {
      dir = dir.parent.childDirectory('llvm_lang');
      dir = dir.childDirectory('install/lib');
      return true;
    }());
    var name = 'libllvm_wrapper.dylib';
    if (Platform.isWindows) {
      name = 'libllvm_wrapper.dll';
    } else if (Platform.isLinux) {
      name = 'libllvm_wrapper.so';
    }
    final p = dir.childFile(name);
    library = DynamicLibrary.open(p.path);
    return _bindings = LLVMCore(library);
  }
}
