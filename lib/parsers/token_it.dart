import 'package:llvm_dart/parsers/lexers/token_stream.dart';

extension TokenItExt<T> on List<T> {
  BackIterator<T> get tokenIt {
    return BackIterator(this);
  }
}

class CursorState {
  CursorState(this._it, this.cursor);
  final BackIterator _it;

  final int cursor;

  void restore() {
    _it._cursor = cursor;
  }
}

typedef TokenIterator = BackIterator<TokenTree>;

class BackIterator<T> extends Iterator<T> {
  BackIterator(List<T> tree) : _current = List.of(tree);
  final List<T> _current;
  int get length => _current.length;
  int _cursor = -1;

  @override
  T get current => _current[_cursor];

  bool get curentIsValid => _cursor > -1 && _cursor < length;

  CursorState get cursor => CursorState(this, _cursor);

  bool moveBack() {
    if (_cursor <= -1) return false;
    _cursor -= 1;
    if (_cursor <= -1) return false;
    return true;
  }

  @override
  bool moveNext() {
    if (_cursor >= length - 1) return false;
    _cursor += 1;
    // Log.i('current: ${Identifier.fromToken(current.token)}',
    //     position: 1, showPath: false);
    return true;
  }
}

void loop<T>(Iterator<T> it, bool Function() action) {
  while (it.moveNext()) {
    if (action()) return;
  }
}
