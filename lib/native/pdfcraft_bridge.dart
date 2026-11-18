import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_core_library.dart';

typedef _NativeTextBlocks = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.IntPtr,
);
typedef _DartTextBlocks = NativeCoreResult Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
);

/// PDFCraft operations. File bytes stay on the device.
final class PdfCraftBridge {
  PdfCraftBridge._(this._library)
    : _create = _library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_pdf_create',
      ),
      _inspect = _library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_pdf_inspect',
      ),
      _edit = _library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_pdf_edit',
      ),
      _memory = NativeCoreMemory(_library);
  final DartCoreOne _create;
  final DartCoreOne _inspect;
  final DartCoreTwo _edit;
  final NativeCoreMemory _memory;
  final ffi.DynamicLibrary _library;
  late final _DartTextBlocks _textBlocks = _library
      .lookupFunction<_NativeTextBlocks, _DartTextBlocks>('ac_pdf_text_blocks');

  late final DartCoreTwo _find = _library
      .lookupFunction<NativeCoreTwo, DartCoreTwo>('ac_pdf_find');
  late final DartCoreTwo _raster = _library
      .lookupFunction<NativeCoreTwo, DartCoreTwo>('ac_pdf_render');

  late final DartCoreTwo _ocr = _library
      .lookupFunction<NativeCoreTwo, DartCoreTwo>('ac_image_ocr');

  static PdfCraftBridge? tryOpen() {
    try {
      return PdfCraftBridge._(openNativeCore());
    } catch (_) {
      return null;
    }
  }

  static PdfCraftBridge openLibraryForTesting(String path) =>
      PdfCraftBridge._(openNativeCore(libraryPath: path));

  Uint8List create() {
    final p = _memory.allocate(Uint8List(0));
    try {
      return _memory.take(_create(p, 0));
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> _inspectWith(Uint8List bytes, DartCoreOne call) {
    final p = _memory.allocate(bytes);
    try {
      final value = jsonDecode(
        utf8.decode(_memory.take(call(p, bytes.length))),
      );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Некорректные данные PDFCraft');
      }
      return value;
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List bytes) =>
      _inspectWith(bytes, _inspect);

  Map<String, dynamic> textBlocks(Uint8List bytes, int page) {
    if (page < 0) throw RangeError.value(page, 'page');
    return _inspectWith(bytes, (input, len) => _textBlocks(input, len, page));
  }

  Map<String, dynamic> find(Uint8List bytes, Map<String, dynamic> request) =>
      jsonDecode(utf8.decode(_request(bytes, request, _find)))
          as Map<String, dynamic>;

  Uint8List edit(Uint8List bytes, Map<String, dynamic> request) =>
      _request(bytes, request, _edit);

  Uint8List raster(Uint8List bytes, Map<String, dynamic> request) =>
      _request(bytes, request, _raster);

  Uint8List recognizeImage(Uint8List png, Map<String, dynamic> options) =>
      _request(png, options, _ocr);

  Uint8List _request(
    Uint8List bytes,
    Map<String, dynamic> request,
    DartCoreTwo call,
  ) {
    final p = _memory.allocate(bytes);
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(request)));
    final q = _memory.allocate(payload);
    try {
      return _memory.take(call(p, bytes.length, q, payload.length));
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }
}
