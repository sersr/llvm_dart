import 'package:llvm_dart/fs/fs.dart';

void main() {
  final core = currentDir.childDirectory('lib').childFile('llvm_core.dart');

  final reg = RegExp('(LLVM[A-Za-z0-9]*?)\\(');
  final def = currentDir.childFile('llvm_wrapper.def');
  def.createSync(recursive: true);

  final list = <String>[];

  final data = core.readAsStringSync();

  final mlist = reg.allMatches(data);
  for (var item in mlist) {
    final src = item[1] as String;
    list.add(src);
  }

  final buffer = StringBuffer();
  buffer.write('''LIBRARY llvm_wrapper
EXPORTS
  ''');

  buffer.writeAll(list.toSet(), '\n  ');

  def.writeAsString(buffer.toString());
}
