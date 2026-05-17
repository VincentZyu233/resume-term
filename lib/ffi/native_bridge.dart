import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class NativeBridge {
  late final DynamicLibrary _lib;

  late final int Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    int,
    int,
  ) _spawn;

  late final int Function(Pointer<Utf8>, Pointer<Uint8>, int) _write;

  late final int Function(Pointer<Utf8>, Pointer<Uint8>, int) _read;

  late final int Function(Pointer<Utf8>) _available;

  late final int Function(Pointer<Utf8>, int, int) _resize;

  late final int Function(Pointer<Utf8>) _close;

  NativeBridge._(this._lib) {
    _spawn = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Uint16, Uint16),
        int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int)>('rterm_spawn');

    _write = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Uint32),
        int Function(Pointer<Utf8>, Pointer<Uint8>, int)>('rterm_write');

    _read = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Uint32),
        int Function(Pointer<Utf8>, Pointer<Uint8>, int)>('rterm_read');

    _available = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('rterm_available');

    _resize = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint16, Uint16),
        int Function(Pointer<Utf8>, int, int)>('rterm_resize');

    _close = _lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('rterm_close');
  }

  static NativeBridge? _instance;
  static NativeBridge get instance {
    _instance ??= _load();
    return _instance!;
  }

  static NativeBridge _load() {
    DynamicLibrary lib;
    if (Platform.isWindows) {
      lib = DynamicLibrary.open('resume_term_core.dll');
    } else if (Platform.isLinux) {
      lib = DynamicLibrary.open('libresume_term_core.so');
    } else {
      throw UnsupportedError('resume-term only supports Windows and Linux');
    }
    return NativeBridge._(lib);
  }

  int spawn(
    String id,
    String shell, {
    String? executable,
    String? workingDir,
    int cols = 80,
    int rows = 24,
  }) {
    final idPtr = id.toNativeUtf8();
    final shellPtr = shell.toNativeUtf8();
    final exePtr = executable?.toNativeUtf8();
    final wdPtr = workingDir?.toNativeUtf8();
    try {
      return _spawn(idPtr, shellPtr, exePtr ?? nullptr, wdPtr ?? nullptr, cols, rows);
    } finally {
      calloc.free(idPtr);
      calloc.free(shellPtr);
      if (exePtr != null) calloc.free(exePtr);
      if (wdPtr != null) calloc.free(wdPtr);
    }
  }

  int write(String id, Uint8List data) {
    final idPtr = id.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    dataPtr.asTypedList(data.length).setAll(0, data);
    try {
      return _write(idPtr, dataPtr, data.length);
    } finally {
      calloc.free(idPtr);
      calloc.free(dataPtr);
    }
  }

  int read(String id, Uint8List buf) {
    final idPtr = id.toNativeUtf8();
    final bufPtr = calloc<Uint8>(buf.length);
    try {
      final n = _read(idPtr, bufPtr, buf.length);
      if (n > 0) {
        buf.setAll(0, bufPtr.asTypedList(n));
      }
      return n;
    } finally {
      calloc.free(idPtr);
      calloc.free(bufPtr);
    }
  }

  int available(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      return _available(idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  int resize(String id, int cols, int rows) {
    final idPtr = id.toNativeUtf8();
    try {
      return _resize(idPtr, cols, rows);
    } finally {
      calloc.free(idPtr);
    }
  }

  int close(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      return _close(idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }
}
