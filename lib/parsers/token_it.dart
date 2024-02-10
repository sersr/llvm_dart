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
  CursorState(this._it, this.cursor);
  final BackIterator _it;

  final int cursor;

  void restore() {
    _it._restore(this);
  }
}

class StringCursorState extends CursorState {
  StringCursorState(super._it, super.cursor, this.stringCursor);
  final int stringCursor;
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

  StringCursorState? _cacheStringState;
  @override
  StringCursorState get cursor {
    if (_cacheStringState != null && _cursorState == _cursor) {
      return _cacheStringState!;
    }
    _cursorState = _cursor;
    return _cacheStringState = StringCursorState(this, _cursor, _stringCursor);
  }

  @override
  void _restore(StringCursorState cursor) {
    _cursor = cursor.cursor;
    _stringCursor = cursor.stringCursor;
    _cursorState = cursor.cursor;
    _cacheStringState = cursor;
  }

  @override
  bool moveBack() {
    if (_cursor <= -1) return false;
    final preCursor = _cursor - 1;
    if (preCursor > -1 && preCursor < length) {
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
  bool get isEmpty => _current.isEmpty;
  int _cursor = -1;

  @override
  T get current => _current[_cursor];

  /// [moveNext]确定了不会超出[length]
  bool get curentIsValid => _cursor > -1;

  var _cursorState = -1;
  CursorState? _cacheState;
  CursorState get cursor {
    if (_cacheState != null && _cursorState == _cursor) {
      return _cacheState!;
    }
    _cursorState = _cursor;
    return _cacheState = CursorState(this, _cursor);
  }

  void _restore(covariant CursorState cursor) {
    _cursor = cursor.cursor;
    _cursorState = cursor.cursor;
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
    return true;
  }
}

void loop<T>(Iterator<T> it, bool Function() action) {
  while (it.moveNext()) {
    if (action()) return;
  }
}
