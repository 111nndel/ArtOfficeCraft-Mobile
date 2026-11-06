import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'document_worker.dart';
import 'grid_window.dart';

import 'dart:typed_data';

import 'wordcraft_bridge.dart';
import 'gridcraft_bridge.dart';
import 'deckcraft_bridge.dart';
import 'pdfcraft_bridge.dart';

enum NativeDocumentKind { word, grid, deck, pdf }

/// Injectable asynchronous boundary: widgets never parse files or call Rust FFI.
abstract interface class DocumentBackend {
  Future<Uint8List> create([String text = '']);
  Future<Map<String, dynamic>> inspect(Uint8List bytes);
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request);
}

final _ownedBytes = Expando<bool>('immutable document snapshot');
Uint8List immutableDocumentBytes(Uint8List bytes) {
  if (_ownedBytes[bytes] == true) return bytes;
  final owned = Uint8List.fromList(bytes).asUnmodifiableView();
  _ownedBytes[owned] = true;
  return owned;
}

/// An edit is published only after its resulting document can be inspected.
class DocumentSnapshot {
  DocumentSnapshot(Uint8List bytes, Map<String, dynamic> preview)
    : bytes = immutableDocumentBytes(bytes),
      preview = _freeze(preview) as Map<String, dynamic>;
  final Uint8List bytes;
  final Map<String, dynamic> preview;
}

Object? _freeze(Object? value, [int depth = 0]) {
  if (depth > 64) throw ArgumentError('Document data is nested too deeply');
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _freeze(v, depth + 1))),
    );
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map((v) => _freeze(v, depth + 1)));
  }
  if (value == null ||
      value is String ||
      value is bool ||
      value is num && value.isFinite) {
    return value;
  }
  throw ArgumentError('Document data must contain JSON values');
}

abstract interface class InspectedDocumentBackend {
  Future<DocumentSnapshot> editInspected(
    Uint8List bytes,
    Map<String, dynamic> request,
  );
}

abstract interface class DocumentBackendLifetime {
  Future<void> close();
}

abstract interface class DocumentImages {
  Future<Uint8List> image(Uint8List bytes, int slide, int media);
}

typedef PdfTextBlock = ({int id, String text});
typedef PdfTextPage = ({List<PdfTextBlock> blocks, bool limited});

abstract interface class PdfTextDocuments {
  Future<PdfTextPage> pdfTextBlocks(Uint8List bytes, int page);
}

typedef PdfFindHit = ({int page, List<double> rect});
typedef PdfFindBatch = ({
  List<PdfFindHit> hits,
  int next,
  bool incomplete,
  bool capped,
});

abstract interface class PdfSearchDocuments {
  Future<PdfFindBatch> pdfFind(
    Uint8List bytes,
    String query,
    int start,
    int limit,
  );
}

abstract interface class GridDocuments {
  Future<Map<String, dynamic>> gridView(
    Uint8List bytes,
    GridWindow window,
    String selected,
  );
  Future<DocumentSnapshot> editGridView(
    Uint8List bytes,
    Map<String, dynamic> edit,
    GridWindow window,
    String selected,
  );
}

typedef GridFilterChoice = ({String? value, bool checked});

abstract interface class GridFilterDocuments {
  Future<List<GridFilterChoice>> gridFilterValues(
    Uint8List bytes,
    int sheet,
    String range,
    String column,
  );
}

abstract interface class GridClipboardDocuments {
  Future<Map<String, dynamic>> copyGridRange(
    Uint8List bytes,
    Map<String, dynamic> request,
  );
  Future<DocumentSnapshot> pasteGridRange(
    Uint8List bytes,
    Uint8List source,
    Map<String, dynamic> request,
    GridWindow window,
    String selected,
  );
}

extension GridClipboardTransactions on DocumentBackend {
  Future<Map<String, dynamic>> copyGrid(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) {
    final backend = this;
    if (backend is! GridClipboardDocuments) {
      throw StateError('Grid clipboard backend unavailable');
    }
    return (backend as GridClipboardDocuments).copyGridRange(bytes, request);
  }

  Future<DocumentSnapshot> pasteGrid(
    Uint8List bytes,
    Uint8List source,
    Map<String, dynamic> request,
    GridWindow window,
    String selected,
  ) {
    final backend = this;
    if (backend is! GridClipboardDocuments) {
      throw StateError('Grid clipboard backend unavailable');
    }
    return (backend as GridClipboardDocuments).pasteGridRange(
      bytes,
      source,
      request,
      window,
      selected,
    );
  }
}

extension GridTransactions on DocumentBackend {
  Future<Map<String, dynamic>> inspectGrid(
    Uint8List bytes,
    GridWindow window,
    String selected,
  ) async {
    final backend = this;
    if (backend is GridDocuments) {
      return (backend as GridDocuments).gridView(bytes, window, selected);
    }
    final parsed = await inspect(bytes);
    final sheets = parsed['sheets'] as List;
    return {
      ...parsed,
      'selection': (sheets[window.sheet]['cells'] as Map)[selected] ?? {},
    };
  }

  Future<DocumentSnapshot> editAndInspectGrid(
    Uint8List bytes,
    Map<String, dynamic> edit,
    GridWindow window,
    String selected,
  ) async {
    final backend = this;
    if (backend is GridDocuments) {
      return (backend as GridDocuments).editGridView(
        bytes,
        edit,
        window,
        selected,
      );
    }
    final next = await this.edit(bytes, edit);
    return DocumentSnapshot(next, await inspectGrid(next, window, selected));
  }
}

extension DocumentTransactions on DocumentBackend {
  Future<DocumentSnapshot> editAndInspect(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) async {
    final backend = this;
    if (backend is InspectedDocumentBackend) {
      return (backend as InspectedDocumentBackend).editInspected(
        bytes,
        request,
      );
    }
    final next = await edit(bytes, request);
    return DocumentSnapshot(next, await inspect(next));
  }
}

Future<void> closeDocumentBackend(DocumentBackend? backend) async {
  if (backend is DocumentBackendLifetime) {
    await (backend as DocumentBackendLifetime).close();
  }
}

final class NativeDocumentBackend
    implements
        DocumentBackend,
        InspectedDocumentBackend,
        DocumentBackendLifetime,
        DocumentImages,
        PdfTextDocuments,
        PdfSearchDocuments,
        GridDocuments,
        GridFilterDocuments,
        GridClipboardDocuments {
  NativeDocumentBackend(this.kind, {this.libraryPath});
  final NativeDocumentKind kind;
  final String? libraryPath;
  late final DocumentWorker _worker = DocumentWorker(
    _documentWorkerMain,
    configuration: {'kind': kind.name, 'library': libraryPath},
  );
  bool _started = false, _closed = false;
  Uint8List? _sentBytes;
  int _documentToken = 0;
  int inputTransfers = 0;
  int get workerStarts => _started ? _worker.starts : 0;

  static DocumentBackend? tryOpen(NativeDocumentKind kind) {
    if (!Platform.isAndroid) return null;
    try {
      ffi.DynamicLibrary.open('libartoffice_core.so');
      return NativeDocumentBackend(kind);
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _call(
    String operation,
    Uint8List? bytes,
    Map<String, dynamic> request, {
    Uint8List? source,
  }) {
    if (_closed) return Future.error(StateError('Document backend is closed'));
    // Snapshot mutable buffers and containers before the startup await. Strings
    // remain immutable; UTF-8/JSON encoding and all Rust calls stay in the worker.
    final frozenRequest = _freeze(request);
    TransferableTypedData? transfer;
    if (bytes != null &&
        (!identical(bytes, _sentBytes) || _ownedBytes[bytes] != true)) {
      transfer = TransferableTypedData.fromList([bytes]);
      _sentBytes = bytes;
      _documentToken++;
      inputTransfers++;
    }
    final payload = {
      'bytes': transfer,
      'document': bytes == null ? null : _documentToken,
      'request': frozenRequest,
      if (source != null) 'source': TransferableTypedData.fromList([source]),
    };
    _started = true;
    return _worker.request(operation, payload);
  }

  Uint8List _bytes(Object? value) {
    final bytes = (value as TransferableTypedData)
        .materialize()
        .asUint8List()
        .asUnmodifiableView();
    _ownedBytes[bytes] = true;
    return bytes;
  }

  @override
  Future<Uint8List> create([String text = '']) async =>
      _bytes(await _call('create', null, {'text': text}));
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async =>
      _freeze(await _call('inspect', bytes, {})) as Map<String, dynamic>;
  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async =>
      _bytes(await _call('edit', bytes, request));
  @override
  Future<DocumentSnapshot> editInspected(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) async {
    final result = await _call('editInspect', bytes, request) as Map;
    return DocumentSnapshot(
      _bytes(result['bytes']),
      Map<String, dynamic>.from(result['preview'] as Map),
    );
  }

  @override
  Future<Uint8List> image(Uint8List bytes, int slide, int media) async =>
      _bytes(await _call('image', bytes, {'slide': slide, 'media': media}));
  @override
  Future<PdfTextPage> pdfTextBlocks(Uint8List bytes, int page) async {
    final result = await _call('pdfTextBlocks', bytes, {'page': page}) as Map;
    return (
      blocks: [
        for (final item in result['blocks'] as List)
          (id: item['id'] as int, text: item['text'] as String),
      ],
      limited: result['limited'] == true,
    );
  }

  @override
  Future<PdfFindBatch> pdfFind(
    Uint8List bytes,
    String query,
    int start,
    int limit,
  ) async {
    final result = await _call('pdfFind', bytes, {
      'query': query,
      'start': start,
      'limit': limit,
    }) as Map;
    return (
      hits: [
        for (final item in result['hits'] as List)
          (
            page: item['page'] as int,
            rect: [for (final n in item['rect'] as List) (n as num).toDouble()],
          ),
      ],
      next: result['next'] as int,
      incomplete: result['incomplete'] == true,
      capped: result['capped'] == true,
    );
  }

  @override
  Future<Map<String, dynamic>> gridView(
    Uint8List bytes,
    GridWindow window,
    String selected,
  ) async =>
      _freeze(await _call('gridInspect', bytes, window.request(selected)))
          as Map<String, dynamic>;
  @override
  Future<List<GridFilterChoice>> gridFilterValues(
    Uint8List bytes,
    int sheet,
    String range,
    String column,
  ) async {
    final result = await _call('gridInspect', bytes, {
      'filterValues': {'sheet': sheet, 'range': range, 'column': column},
    }) as Map;
    return [
      for (final item in result['items'] as List)
        (value: item['value'] as String?, checked: item['checked'] as bool),
    ];
  }

  @override
  Future<DocumentSnapshot> editGridView(
    Uint8List bytes,
    Map<String, dynamic> edit,
    GridWindow window,
    String selected,
  ) async {
    final result = await _call('gridEditInspect', bytes, {
      'edit': edit,
      'view': window.request(selected),
    }) as Map;
    return DocumentSnapshot(
      _bytes(result['bytes']),
      Map<String, dynamic>.from(result['preview'] as Map),
    );
  }

  @override
  Future<Map<String, dynamic>> copyGridRange(
    Uint8List bytes,
    Map<String, dynamic> request,
  ) async =>
      _freeze(await _call('gridCopy', bytes, request)) as Map<String, dynamic>;
  @override
  Future<DocumentSnapshot> pasteGridRange(
    Uint8List bytes,
    Uint8List source,
    Map<String, dynamic> request,
    GridWindow window,
    String selected,
  ) async {
    final result = await _call('gridPasteInspect', bytes, {
      'edit': request,
      'view': window.request(selected),
    }, source: source) as Map;
    return DocumentSnapshot(
      _bytes(result['bytes']),
      Map<String, dynamic>.from(result['preview'] as Map),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_started) await _worker.close();
    _sentBytes = null;
  }
}

void _documentWorkerMain((SendPort, Map<String, Object?>) bootstrap) {
  final kind = NativeDocumentKind.values.byName(bootstrap.$2['kind'] as String);
  final engine = _NativeEngine(kind, bootstrap.$2['library'] as String?);
  Uint8List? currentBytes;
  int? currentToken;
  serveDocumentWorker(bootstrap.$1, (operation, raw) {
    final payload = raw as Map;
    final transfer = payload['bytes'] as TransferableTypedData?;
    final token = payload['document'] as int?;
    if (transfer != null) {
      currentBytes = transfer.materialize().asUint8List();
      currentToken = token;
    }
    if (token != null && (token != currentToken || currentBytes == null)) {
      throw StateError('Missing worker input snapshot');
    }
    final bytes = token == null ? null : currentBytes;
    final request = Map<String, dynamic>.from(payload['request'] as Map);
    if (operation == 'gridPasteInspect') {
      final source = (payload['source'] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final next = engine.pasteGrid(
        bytes!,
        source,
        Map<String, dynamic>.from(request['edit'] as Map),
      );
      final preview = engine.call(
        'gridInspect',
        next,
        Map<String, dynamic>.from(request['view'] as Map),
      );
      return {
        'bytes': TransferableTypedData.fromList([next]),
        'preview': preview,
      };
    }
    if (operation == 'editInspect' || operation == 'gridEditInspect') {
      final grid = operation == 'gridEditInspect';
      final next = engine.call(
        'edit',
        bytes,
        grid ? Map<String, dynamic>.from(request['edit'] as Map) : request,
      ) as Uint8List;
      final preview = engine.call(
        grid ? 'gridInspect' : 'inspect',
        next,
        grid ? Map<String, dynamic>.from(request['view'] as Map) : const {},
      );
      return {
        'bytes': TransferableTypedData.fromList([next]),
        'preview': preview,
      };
    }
    final result = engine.call(operation, bytes, request);
    return result is Uint8List
        ? TransferableTypedData.fromList([result])
        : result;
  });
}

class _NativeEngine {
  _NativeEngine(this.kind, this.library);
  final NativeDocumentKind kind;
  final String? library;
  Object? _bridge;
  Object _open() => switch (kind) {
    NativeDocumentKind.word =>
      library == null
          ? WordCraftBridge.tryOpen()!
          : WordCraftBridge.openLibraryForTesting(library!),
    NativeDocumentKind.grid =>
      library == null
          ? GridCraftBridge.tryOpen()!
          : GridCraftBridge.openLibraryForTesting(library!),
    NativeDocumentKind.deck =>
      library == null
          ? DeckCraftBridge.tryOpen()!
          : DeckCraftBridge.openLibraryForTesting(library!),
    NativeDocumentKind.pdf =>
      library == null
          ? PdfCraftBridge.tryOpen()!
          : PdfCraftBridge.openLibraryForTesting(library!),
  };
  Uint8List pasteGrid(
    Uint8List bytes,
    Uint8List source,
    Map<String, dynamic> request,
  ) {
    if (kind != NativeDocumentKind.grid) {
      throw StateError('Not a workbook backend');
    }
    return ((_bridge ??= _open()) as GridCraftBridge).pasteRange(
      bytes,
      source,
      request,
    );
  }

  Object call(
    String operation,
    Uint8List? bytes,
    Map<String, dynamic> request,
  ) {
    final bridge = _bridge ??= _open();
    switch (kind) {
      case NativeDocumentKind.word:
        final engine = bridge as WordCraftBridge;
        if (operation == 'create') {
          return engine.create(request['text'] as String? ?? '');
        }
        if (operation == 'inspect') return engine.inspect(bytes!);
        if (request['action'] == 'append') {
          return engine.appendParagraph(bytes!, request['text'] as String);
        }
        return engine.edit(bytes!, request);
      case NativeDocumentKind.grid:
        final engine = bridge as GridCraftBridge;
        if (operation == 'create') return engine.create();
        if (operation == 'inspect') return engine.inspect(bytes!);
        if (operation == 'gridCopy') return engine.copyRange(bytes!, request);
        if (operation == 'gridInspect') {
          return engine.inspectWindow(bytes!, request);
        }
        return engine.edit(bytes!, request);
      case NativeDocumentKind.deck:
        final engine = bridge as DeckCraftBridge;
        if (operation == 'create') return engine.create();
        if (operation == 'inspect') return engine.inspect(bytes!);
        if (operation == 'image') {
          return engine.image(
            bytes!,
            request['slide'] as int,
            request['media'] as int,
          );
        }
        return engine.edit(bytes!, request);
      case NativeDocumentKind.pdf:
        final engine = bridge as PdfCraftBridge;
        if (operation == 'create') return engine.create();
        if (operation == 'inspect') return engine.inspect(bytes!);
        if (operation == 'pdfFind') return engine.find(bytes!, request);
        if (operation == 'pdfTextBlocks') {
          return engine.textBlocks(bytes!, request['page'] as int);
        }
        return engine.edit(bytes!, request);
    }
  }
}
