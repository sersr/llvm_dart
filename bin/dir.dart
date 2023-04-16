import 'package:file/local.dart';
import 'package:llvm_dart/fs/fs.dart';

export 'package:file/local.dart';

const fs = LocalFileSystem();

Directory get currentDir => fs.currentDirectory;
