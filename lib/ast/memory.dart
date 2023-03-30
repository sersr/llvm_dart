import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

class LLVMAllocator implements Allocator {
  LLVMAllocator();

  final _caches = <Pointer>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = malloc.allocate<T>(byteCount, alignment: alignment);
    _caches.add(p);
    return p;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    _caches.remove(pointer);
    malloc.free(pointer);
  }

  void releaseAll() {
    for (var p in _caches) {
      malloc.free(p);
    }
    _caches.clear();
  }
}

final _llvmMalloc = LLVMAllocator();

Pointer<Char> get unname {
  return ''.toChar();
}

LLVMAllocator get llvmMalloc {
  final z = Zone.current[#llvmZone];
  if (z is LLVMAllocator) {
    return z;
  }
  return _llvmMalloc;
}

T runLLVMZoned<T>(T Function() body, {LLVMAllocator? malloc}) {
  return runZoned(body, zoneValues: {#llvmZone: malloc ?? _llvmMalloc});
}

extension StringToChar on String {
  Pointer<Char> toChar({Allocator? malloc}) {
    malloc ??= llvmMalloc;
    final u = toNativeUtf8(allocator: malloc);
    return u.cast();
  }
}

extension ArrayExt<T extends NativeType> on List<Pointer<T>> {
  Pointer<Pointer<D>> toNative<D extends NativeType>() {
    final arr = llvmMalloc<Pointer>(length);
    for (var i = 0; i < length; i++) {
      arr[i] = this[i];
    }
    return arr.cast();
  }
}
