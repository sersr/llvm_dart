import 'package:collection/collection.dart';

import '../../abi/abi_fn.dart';
import '../../llvm_dart.dart';
import '../analysis_context.dart';
import '../ast.dart';
import '../expr.dart';
import '../llvm/build_context_mixin.dart';
import '../llvm/variables.dart';
import '../memory.dart';
import '../stmt.dart';
import '../tys.dart';

part 'as_builder.dart';
part 'call_builder.dart';
part 'if_builder.dart';
part 'match_builder.dart';

List<FieldExpr> alignParam(List<FieldExpr> params, List<FieldDef> fields) {
  return alignList(params, (s) => fields.indexWhere((t) => s.ident == t.ident));
}

List<S> alignList<S>(List<S> src, int Function(S) test) {
  final sortFields = <S>[];
  final fieldMap = <int, S>{};

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
    for (;;) {
      if (!fieldMap.containsKey(index)) {
        break;
      }

      index++;
    }

    fieldMap[index] = p;
  }

  sortFields.clear();
  final keys = fieldMap.keys.toList()..sort();
  for (var k in keys) {
    if (fieldMap[k] case S v) {
      sortFields.add(v);
    }
  }

  return sortFields;
}
