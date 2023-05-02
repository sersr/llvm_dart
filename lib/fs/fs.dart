import 'package:file/file.dart';
import 'package:file/local.dart';

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
