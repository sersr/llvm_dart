import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'fs/fs.dart';

Future<void> runCmd(List<String> cmd, {Directory? dir}) async {
  dir ??= buildDir;
  final p = dir.path;

  final process =
      await Process.start('sh', ['-c', cmd.join(' ')], workingDirectory: p);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  await process.exitCode;
}

Future<String> runStr(List<String> cmd, {Directory? dir}) async {
  dir ??= buildDir;
  final p = dir.path;
  final completer = Completer<String>();

  final process = await Process.start('sh', ['-c', cmd.join(' ')],
      workingDirectory: p, runInShell: true);
  String last = '';
  process.stdout.listen((event) {
    last = utf8.decode(event);
  });

  process.exitCode.then((code) {
    if (!completer.isCompleted) {
      if (code == 0) {
        completer.complete(last.trim());
      } else {
        completer.complete('');
      }
    }
  });

  return completer.future;
}
