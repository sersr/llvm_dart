import 'package:llvm_dart/fs/fs.dart';

void main() {
  final lib = currentDir.childDirectory('lib');
  final entries = lib.listSync(recursive: true);
  final reg = RegExp('llvm\\.(.*?)\\(');
  final def = currentDir.childFile('llvm_wrapper.def');
  def.createSync(recursive: true);

  final list = <String>[];
  for (var entry in entries) {
    if (entry case File(basename: var name)) {
      if (name == 'llvm_core.dart') continue;
      final data = entry.readAsStringSync();

      final mlist = reg.allMatches(data);
      for (var item in mlist) {
        final src = item[1] as String;
        list.add(src);
      }
    }

    final buffer = StringBuffer();
    buffer.write('''LIBRARY llvm_wrapper
EXPORTS
  ''');

    buffer.writeAll(list.toSet(), '\n  ');

    def.writeAsString(buffer.toString());
  }
}
