import 'package:file/local.dart';
import 'package:file/file.dart';

export 'package:file/file.dart';

const fs = LocalFileSystem();

Directory get currentDir {
  return fs.currentDirectory;
}
