import 'lexers/token_stream.dart';

extension TokenItExt<T> on List<T> {
  BackIterator<T> get tokenIt {
    return BackIterator(this);
  }
}

extension TokenItStringExt on List<String> {
  BackIteratorString get tokenIt {
    return BackIteratorString(this);
  }
}

class CursorState {
  CursorState(this._it, this._cursor, this._stringCursor);
  final BackIterator _it;
  final int? _stringCursor;

  final int _cursor;

  int get cursor => _stringCursor ?? _cursor;

  void restore() {
    _it._restore(this);
  }
}

typedef TokenIterator = BackIterator<TokenTree>;

class BackIteratorString extends BackIterator<String> {
  BackIteratorString(super.tree);

  int get stringCursor => _stringCursor;
  int get stringCursorEnd {
    if (curentIsValid) {
      return _stringCursor + current.length;
    }
    return _stringCursor;
  }

  int _stringCursor = -1;

  @override
  CursorState get cursor {
    if (_cacheState != null && _cursorState == _cursor) {
      return _cacheState!;
    }
    _cursorState = _cursor;
    return _cacheState = CursorState(this, _cursor, _stringCursor);
  }

  @override
  void _restore(CursorState cursor) {
    _cursor = cursor._cursor;
    _stringCursor = cursor._stringCursor!;
    _cursorState = cursor._cursor;
    _cacheState = cursor;
  }

  @override
  bool moveBack() {
    if (_cursor <= -1) return false;
    final preCursor = _cursor - 1;
    if (preCursor > 0) {
      _stringCursor -= _current[preCursor].length;
    } else {
      _stringCursor -= 1;
    }
    _cursor -= 1;
    if (_cursor <= -1) return false;
    return true;
  }

  @override
  bool moveNext() {
    if (_cursor >= length - 1) return false;
    if (curentIsValid) {
      _stringCursor += current.length;
    } else {
      _stringCursor += 1;
    }
    _cursor += 1;
    return true;
  }
}

class BackIterator<T> implements Iterator<T> {
  BackIterator(List<T> tree) : _current = List.of(tree);
  final List<T> _current;
  int get length => _current.length;
  int _cursor = -1;

  @override
  T get current => _current[_cursor];

  bool get curentIsValid => _cursor > -1 && _cursor < length;

  var _cursorState = -1;
  CursorState? _cacheState;
  CursorState get cursor {
    if (_cacheState != null && _cursorState == _cursor) {
      return _cacheState!;
    }
    _cursorState = _cursor;
    return _cacheState = CursorState(this, _cursor, null);
  }

  void _restore(CursorState cursor) {
    _cursor = cursor._cursor;
    _cursorState = cursor._cursor;
    _cacheState = cursor;
  }

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
