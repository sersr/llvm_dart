part of 'ast.dart';

class RawIdent with EquatableMixin {
  RawIdent(this.start, this.end, this.fileName, this.name);
  final int start;
  final int end;
  final String fileName;
  final String name;

  @override
  late final props = [start, end, fileName, name];
}

class Offset {
  const Offset(this.row, this.column);

  static const zero = Offset(0, 0);

  bool get isValid => column > 0 && row > 0;
  final int column;
  final int row;

  String get pathStyle {
    return '$row:$column';
  }

  @override
  String toString() {
    return '{row: $row, column: $column}';
  }
}

extension StringIdentExt on String {
  Identifier get ident {
    return Identifier.builtIn(this);
  }
}

class Identifier with EquatableMixin {
  Identifier.fromToken(Token token, this.data, this.fileName)
      : start = token.start,
        end = token.end,
        lineStart = token.lineStart,
        lineEnd = token.lineEnd,
        lineNumber = token.lineNumber,
        builtInValue = '',
        isStr = false,
        name = '';
  Identifier.tokens(Token start, Token end, this.data, this.fileName)
      : start = start.start,
        end = end.end,
        lineStart = start.lineStart,
        lineEnd = end.lineEnd,
        lineNumber = start.lineNumber,
        builtInValue = '',
        isStr = false,
        name = '';

  Identifier.builtIn(this.builtInValue)
      : name = '',
        start = 0,
        lineStart = -1,
        lineEnd = -1,
        isStr = false,
        lineNumber = 0,
        end = 0,
        fileName = '',
        data = '';
  Identifier.str(
      Token tokenStart, Token tokenEnd, this.builtInValue, this.fileName)
      : start = tokenStart.start,
        end = tokenEnd.end,
        lineStart = tokenStart.lineStart,
        lineEnd = tokenEnd.lineEnd,
        isStr = true,
        lineNumber = tokenStart.lineNumber,
        data = '',
        name = '';

  final String name;
  final int start;
  final int lineStart;
  final int lineEnd;
  final int lineNumber;
  final int end;
  final String builtInValue;
  final bool isStr;
  final String fileName;

  @protected
  final String data;

  bool inSameFile(Identifier other) {
    return data == other.data && fileName == other.fileName;
  }

  bool get isValid => end != 0;

  RawIdent get toRawIdent {
    return RawIdent(start, end, fileName, name);
  }

  Offset? _offset;

  Offset get offset {
    if (_offset != null) return _offset!;
    if (!isValid) return Offset.zero;

    return _offset = Offset(lineNumber, start - lineStart + 1);
  }

  static final Identifier none = Identifier.builtIn('');
  static final Identifier self = Identifier.builtIn('self');
  // ignore: non_constant_identifier_names
  static final Identifier Self = Identifier.builtIn('Self');

  /// 在parser下要求更多字段相等
  static bool get identicalEq {
    return Zone.current[#data] == true;
  }

  static R run<R>(R Function() body, {ZoneSpecification? zoneSpecification}) {
    return runZoned(body,
        zoneValues: {#data: true}, zoneSpecification: zoneSpecification);
  }

  @override
  List<Object?> get props {
    if (identicalEq) {
      return [fileName, data, start, end, name];
    }
    return [src];
  }

  String? _src;
  String get src {
    if (_src != null) return _src!;
    if (identical(this, none)) {
      return '';
    }
    if (builtInValue.isNotEmpty || isStr) {
      return builtInValue;
    }

    if (lineStart == -1) {
      return '';
    }
    return _src = data.substring(start, end);
  }

  String get path => '$src ($fileName:${offset.pathStyle})';
  String get basePath => '$fileName:${offset.pathStyle}';

  /// 指示当前的位置
  String get light {
    if (lineStart == -1) {
      return '';
    }

    final line = data.substring(lineStart, lineEnd);
    final space = ' ' * (start - lineStart);
    // lineEnd 没有包括换行符
    final arrow = '^' * (math.min(end, lineEnd + 1) - start);
    return '\x1B[39m$fileName:${offset.pathStyle}:\x1B[0m\n$line\n$space\x1B[31m$arrow\x1B[0m';
  }

  static String lightSrc(String src, int start, int end) {
    var lineStart = start;
    if (start > 0) {
      lineStart = src.substring(0, start).lastIndexOf('\n');
      if (lineStart != -1) {
        lineStart += 1;
      } else {
        lineStart = 0;
      }
    }
    var lineEnd = src.substring(start).indexOf('\n');
    if (lineEnd == -1) {
      lineEnd = end;
    } else {
      lineEnd += start;
    }

    if (lineStart != -1) {
      final vs = src.substring(lineStart, lineEnd);
      final s = ' ' * (start - lineStart);
      final v = '^' * (end - start);
      return '$vs\n$s$v';
    }
    return src.substring(start, end);
  }

  @override
  String toString() {
    if (builtInValue.isNotEmpty) {
      return '[$builtInValue]';
    }
    if (identical(this, none) || lineStart == -1) {
      return '';
    }

    return data.substring(start, end);
  }
}
