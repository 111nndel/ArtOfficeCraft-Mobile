import 'dart:convert';
import 'dart:typed_data';

import 'package:artofficecraft_mobile/native/document_backend.dart';
import 'package:artofficecraft_mobile/native/grid_selection.dart';
import 'package:artofficecraft_mobile/native/grid_window.dart';

/// JSON snapshots isolate UI transaction/history tests from native algorithms,
/// which are covered separately by Rust and Android round trips.
class FeaturesBackend implements DocumentBackend {
  FeaturesBackend(this.initial);
  final Map<String, dynamic> initial;
  bool failEdit = false, failInspect = false;
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic>? viewed;
  Uint8List encode(Map<String, dynamic> data) => Uint8List.fromList(
    utf8.encode(
      '${data.containsKey('pages') ? '%PDF-' : ''}${jsonEncode(data)}',
    ),
  );
  Map<String, dynamic> decode(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes).replaceFirst(RegExp(r'^%PDF-'), ''))
          as Map<String, dynamic>;
  @override
  Future<Uint8List> create([String text = '']) async => encode(initial);
  @override
  Future<Map<String, dynamic>> inspect(Uint8List bytes) async {
    if (failInspect) {
      failInspect = false;
      throw StateError('Inspection failed');
    }
    return viewed = decode(bytes);
  }

  @override
  Future<Uint8List> edit(Uint8List bytes, Map<String, dynamic> request) async {
    requests.add(Map.of(request));
    if (failEdit) throw StateError('Edit failed');
    final data = decode(bytes);
    switch (request['action']) {
      case 'replace_all':
      case 'replace_one':
        for (final block in data['blocks'] as List) {
          if (request['action'] == 'replace_one' &&
              block['block'] != request['block']) {
            continue;
          }
          final old = block['text'] as String;
          block['text'] = request['action'] == 'replace_all'
              ? old.replaceAll(
                  request['find'] as String,
                  request['replacement'] as String,
                )
              : old.replaceRange(
                  request['start'] as int,
                  request['end'] as int,
                  request['replacement'] as String,
                );
          block['runs'] = [
            {'text': block['text']},
          ];
        }
        data['paragraphs'] = (data['blocks'] as List)
            .map((b) => b['text'])
            .toList();
      case 'add_sheet':
        final sheets = data['sheets'] as List;
        sheets.add({
          'name': request['name'] ?? 'Sheet${sheets.length + 1}',
          'cells': <String, dynamic>{},
        });
        data['activeSheet'] = sheets.length - 1;
      case 'format_range':
      case 'clear_range':
        final range = GridSelection.parse(request['range'] as String)!;
        final cells = data['sheets'][request['sheet']]['cells'] as Map;
        for (var r = range.row; r <= range.endRow; r++) {
          for (var c = range.column; c <= range.endColumn; c++) {
            final key = '${gridColumnName(c)}${r + 1}';
            final cell = Map<String, dynamic>.from(cells[key] as Map? ?? {});
            if (request['action'] == 'clear_range') {
              cell['input'] = '';
              cell['display'] = '';
            } else {
              cell['style'] = {
                ...?cell['style'] as Map?,
                ...request['style'] as Map,
              };
            }
            cells[key] = cell;
          }
        }
      case 'move_slide':
        final slides = data['slides'] as List;
        slides.insert(
          request['to'] as int,
          slides.removeAt(request['slide'] as int),
        );
      case 'edit_text':
        final shapes = data['slides'][request['slide']]['shapes'] as List;
        shapes.firstWhere((s) => s['id'] == request['shape'])['text'] =
            request['text'];
      case 'rotate_cw':
        final page = data['pages'][request['page']] as Map;
        page['rotation'] = ((page['rotation'] as int) + 90) % 360;
        final w = page['width'];
        page['width'] = page['height'];
        page['height'] = w;
      case 'move_to':
        final pages = data['pages'] as List;
        pages.insert(
          request['to'] as int,
          pages.removeAt(request['page'] as int),
        );
      default:
        if (request['value'] != null) {
          data['sheets'][request['sheet']]['cells'][request['address']] = {
            'input': request['value'],
            'display': request['value'],
          };
        }
    }
    return encode(data);
  }
}
