import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_core_library.dart';

/// GridCraft native engine. Synchronous FFI used by the background DocumentBackend isolate.
/// No data leaves the phone; saving occurs only into a user-chosen new file.
final class GridCraftBridge {
  GridCraftBridge._(ffi.DynamicLibrary library)
    : _create = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_xlsx_create',
      ),
      _inspect = library.lookupFunction<NativeCoreOne, DartCoreOne>(
        'ac_xlsx_inspect',
      ),
      _edit = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_xlsx_set_cell',
      ),
      _window = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_xlsx_inspect_window',
      ),
      _copy = library.lookupFunction<NativeCoreTwo, DartCoreTwo>(
        'ac_xlsx_copy_range',
      ),
      _paste = library.lookupFunction<NativeCoreThree, DartCoreThree>(
        'ac_xlsx_paste_range',
      ),
      _memory = NativeCoreMemory(library);
  final DartCoreOne _create;
  final DartCoreOne _inspect;
  final DartCoreTwo _edit;
  final DartCoreTwo _window;
  final DartCoreTwo _copy;
  final DartCoreThree _paste;
  final NativeCoreMemory _memory;

  static GridCraftBridge? tryOpen() {
    try {
      return GridCraftBridge._(openNativeCore());
    } catch (_) {
      return null;
    }
  }

  static GridCraftBridge openLibraryForTesting(String path) =>
      GridCraftBridge._(openNativeCore(libraryPath: path));

  Uint8List create() {
    final p = _memory.allocate(Uint8List(0));
    try {
      return _memory.take(_create(p, 0));
    } finally {
      _memory.release(p);
    }
  }

  Map<String, dynamic> inspect(Uint8List workbook) {
    final p = _memory.allocate(workbook);
    try {
      final out = jsonDecode(
        utf8.decode(_memory.take(_inspect(p, workbook.length))),
      );
      if (out is! Map<String, dynamic>) {
        throw const FormatException('Некорректный ответ');
      }
      return out;
    } finally {
      _memory.release(p);
    }
  }

  Uint8List editCell(
    Uint8List workbook,
    int sheet,
    String address,
    String value,
  ) {
    return edit(workbook, {'sheet': sheet, 'address': address, 'value': value});
  }

  /// Returns null when both native reader slots are occupied. Callers can use
  /// inspectWindow in that case; opening never evicts another worker's model.
  int? openReader(Uint8List workbook) =>
      inspectWindow(workbook, {'reader': 'open'})['session'] as int?;

  Map<String, dynamic> readWindow(int session, Map<String, dynamic> view) =>
      inspectWindow(Uint8List(0), {
        'reader': 'view',
        'session': session,
        'view': view,
      });

  void closeReader(int session) {
    inspectWindow(Uint8List(0), {'reader': 'close', 'session': session});
  }

  Map<String, dynamic> inspectWindow(
    Uint8List workbook,
    Map<String, dynamic> view,
  ) {
    final p = _memory.allocate(workbook);
    final request = Uint8List.fromList(utf8.encode(jsonEncode(view)));
    final q = _memory.allocate(request);
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(
            _memory.take(_window(p, workbook.length, q, request.length)),
          ),
        ) as Map,
      );
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }

  Map<String, dynamic> copyRange(
    Uint8List workbook,
    Map<String, dynamic> changes,
  ) {
    final p = _memory.allocate(workbook),
        request = Uint8List.fromList(utf8.encode(jsonEncode(changes)));
    final q = _memory.allocate(request);
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(
            _memory.take(_copy(p, workbook.length, q, request.length)),
          ),
        ) as Map,
      );
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }

  Uint8List pasteRange(
    Uint8List workbook,
    Uint8List source,
    Map<String, dynamic> changes,
  ) {
    final p = _memory.allocate(workbook), q = _memory.allocate(source);
    final request = Uint8List.fromList(utf8.encode(jsonEncode(changes))),
        r = _memory.allocate(request);
    try {
      return _memory.take(
        _paste(p, workbook.length, q, source.length, r, request.length),
      );
    } finally {
      _memory.release(r);
      _memory.release(q);
      _memory.release(p);
    }
  }

  Uint8List edit(Uint8List workbook, Map<String, dynamic> changes) {
    final p = _memory.allocate(workbook);
    final request = Uint8List.fromList(utf8.encode(jsonEncode(changes)));
    final q = _memory.allocate(request);
    try {
      return _memory.take(_edit(p, workbook.length, q, request.length));
    } finally {
      _memory.release(q);
      _memory.release(p);
    }
  }
}
