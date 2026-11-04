import 'package:flutter/material.dart';

/// A bounded paragraph draft. Typing changes spans locally; Rust runs on commit.
class WordInlineController extends TextEditingController {
  List<TextStyle> _styles = [];
  String _previous = '';

  static Color? textColor(dynamic value) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
  }

  static TextStyle runStyle(Map run) => TextStyle(
    color: textColor(run['color']),
    fontWeight: run['bold'] == true ? FontWeight.bold : FontWeight.normal,
    fontStyle: run['italic'] == true ? FontStyle.italic : FontStyle.normal,
    decoration: run['underline'] == true
        ? TextDecoration.underline
        : TextDecoration.none,
    fontSize: ((run['size'] as num?)?.toDouble() ?? 12) * 1.33,
  );

  void load(Map<String, dynamic> block, {TextSelection? selection}) {
    final content = block['text']?.toString() ?? '';
    _styles = [
      for (final run in block['runs'] as List? ?? [])
        for (var i = 0; i < (run['text']?.toString() ?? '').length; i++)
          runStyle(run as Map),
    ];
    if (_styles.length > content.length) {
      _styles = _styles.sublist(0, content.length);
    }
    while (_styles.length < content.length) {
      _styles.add(const TextStyle());
    }
    _previous = content;
    value = TextEditingValue(
      text: content,
      selection: selection != null && selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(0, content.length),
              extentOffset: selection.extentOffset.clamp(0, content.length),
            )
          : TextSelection.collapsed(offset: content.length),
    );
  }

  void _syncStyles() {
    if (_previous == text) return;
    var prefix = 0;
    while (prefix < _previous.length &&
        prefix < text.length &&
        _previous.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix > 0 &&
        prefix < text.length &&
        text.codeUnitAt(prefix) >= 0xDC00 &&
        text.codeUnitAt(prefix) <= 0xDFFF) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < _previous.length - prefix &&
        suffix < text.length - prefix &&
        _previous.codeUnitAt(_previous.length - 1 - suffix) ==
            text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    if (suffix > 0 &&
        text.codeUnitAt(text.length - suffix) >= 0xDC00 &&
        text.codeUnitAt(text.length - suffix) <= 0xDFFF) {
      suffix--;
    }
    final inherited = _styles.isEmpty
        ? const TextStyle()
        : _styles[prefix.clamp(0, _styles.length - 1)];
    _styles = [
      ..._styles.take(prefix),
      ...List.filled(text.length - prefix - suffix, inherited),
      ..._styles.skip(_previous.length - suffix),
    ];
    _previous = text;
  }

  bool propertyAtSelection(String key) {
    _syncStyles();
    final offset = selection.isValid ? selection.start : 0;
    final style = _styles.isEmpty
        ? const TextStyle()
        : _styles[offset.clamp(0, _styles.length - 1)];
    return switch (key) {
      'bold' => style.fontWeight == FontWeight.bold,
      'italic' => style.fontStyle == FontStyle.italic,
      'underline' => style.decoration == TextDecoration.underline,
      _ => false,
    };
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    _syncStyles();
    final children = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      var end = start + 1;
      final composing =
          withComposing &&
          value.composing.isValid &&
          start >= value.composing.start &&
          start < value.composing.end;
      while (end < text.length &&
          _styles[end] == _styles[start] &&
          composing ==
              (withComposing &&
                  value.composing.isValid &&
                  end >= value.composing.start &&
                  end < value.composing.end)) {
        end++;
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: composing
              ? _styles[start].copyWith(decoration: TextDecoration.underline)
              : _styles[start],
        ),
      );
      start = end;
    }
    return TextSpan(style: style, children: children);
  }
}
