import 'package:llvm_dart/parsers/lexers/token_stream.dart';

extension TokenItExt on List<TokenTree> {
  TokenIterator get tokenIt {
    return TokenIterator(this);
  }
}

class CursorState {
  CursorState(this._it, this.cursor);
  final TokenIterator _it;

  final int cursor;

  void restore() {
    _it._cursor = cursor;
  }
}

class TokenIterator extends Iterator<TokenTree> {
  TokenIterator(List<TokenTree> tree) : _current = List.of(tree);
  final List<TokenTree> _current;
  int get length => _current.length;
  int _cursor = -1;

  @override
  TokenTree get current => _current[_cursor];

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
