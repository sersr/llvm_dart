import 'dart:ffi';

import 'package:file/file.dart';
import 'package:file/local.dart';

import '../ast/memory.dart';

export 'package:file/file.dart';

const fs = LocalFileSystem();

Directory get currentDir {
  return fs.currentDirectory;
}

Directory get testSDir {
  return fs.currentDirectory.childDirectory('test');
}

Directory get testSrcDir {
  return testSDir.childDirectory('src');
}

Directory get buildDir {
  return currentDir.childDirectory('build');
}

Pointer<Char> buildFileChar(String name) {
  return buildDir.childFile(name).path.toChar();
}

String getSufPath(String path, {String? dir}) {
  dir ??= currentDir.path;

  if (path.contains(dir)) {
    var length = dir.length;

    // / | \
    if (path.length > dir.length) {
      length += 1;
    }

    path = path.replaceRange(0, length, '');
  }

  return path;
}
