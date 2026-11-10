/// Read-only paragraph snapshot. No document parsing or platform services.
typedef WordFindMatch = ({int block, int start, int end, bool editable});
typedef WordHeading = ({int position, int level, String text});

class WordDocumentIndex {
  WordDocumentIndex(Iterable<Map> source)
    : blocks = List.unmodifiable(
        source.map(Map<String, dynamic>.unmodifiable),
      ) {
    final headings = <WordHeading>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      _positions[block['block'] as int] = i;
      final level = block['outlineLevel'];
      final text = block['text']?.toString() ?? '';
      if (level is int && level >= 0 && level < 9 && text.trim().isNotEmpty) {
        headings.add((position: i, level: level, text: text));
      }
    }
    this.headings = List.unmodifiable(headings);
  }

  final List<Map<String, dynamic>> blocks;
  final _positions = <int, int>{};
  late final List<WordHeading> headings;
  int? positionOf(int block) => _positions[block];
  (String, int?, String?)? _findKey;
  List<WordFindMatch> _matches = const [];

  /// Exact, case-sensitive, non-overlapping UTF-16 matches, as before. Cursor
  /// motion/panel rebuilds reuse results; any query, draft or snapshot change
  /// invalidates them. The result remains bounded to 10,000 matches.
  List<WordFindMatch> find(String query, {int? draftBlock, String? draft}) {
    final key = (query, draftBlock, draft);
    if (_findKey == key) return _matches;
    final found = <WordFindMatch>[];
    if (query.isNotEmpty) {
      for (final block in blocks) {
        final id = block['block'] as int;
        final text = draftBlock == id && draft != null
            ? draft
            : block['text']?.toString() ?? '';
        var at = 0;
        while ((at = text.indexOf(query, at)) >= 0) {
          found.add((
            block: id,
            start: at,
            end: at + query.length,
            editable: block['editable'] == true,
          ));
          if (found.length == 10000) break;
          at += query.length;
        }
        if (found.length == 10000) break;
      }
    }
    _findKey = key;
    return _matches = List.unmodifiable(found);
  }
}
