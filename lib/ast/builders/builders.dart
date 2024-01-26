import 'package:collection/collection.dart';

import '../../llvm_core.dart';
import '../../llvm_dart.dart';
import '../ast.dart';
import '../expr.dart';
import '../llvm/build_context_mixin.dart';
import '../llvm/variables.dart';
import '../memory.dart';
import '../stmt.dart';

part 'as_builder.dart';
part 'if_builder.dart';
part 'match_builder.dart';

List<F> alignParam<F>(List<F> src, int Function(F) test) {
  final sortFields = <F>[];
  final fieldMap = <int, F>{};

  for (var i = 0; i < src.length; i++) {
    final p = src[i];
    final index = test(p);
    if (index != -1) {
      fieldMap[index] = p;
    } else {
      sortFields.add(p);
    }
  }

  var index = 0;
  for (var i = 0; i < sortFields.length; i++) {
    final p = sortFields[i];
    while (true) {
      if (fieldMap.containsKey(index)) {
        index++;
        continue;
      }
      fieldMap[index] = p;
      break;
    }
  }

  sortFields.clear();
  final keys = fieldMap.keys.toList()..sort();
  for (var k in keys) {
    final v = fieldMap[k];
    if (v != null) {
      sortFields.add(v);
    }
  }

  return sortFields;
}
