import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'en.dart';

/// UI messages only. Document names/content and native command IDs are not keys.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  static const delegate = _StringsDelegate();
  static final _templates = (english.entries
      .where((e) => e.key.contains('{0}')).toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length)))
      .map((e) {
        final pieces = e.key.split(RegExp(r'\{\d+\}'));
        return (
          RegExp('^${pieces.map(RegExp.escape).join('(.*?)')}\$', dotAll: true),
          e.value,
        );
      })
      .toList();
  String translate(String source) {
    if (locale.languageCode != 'en') return source;
    final exact = english[source];
    if (exact != null) return exact;
    for (final template in _templates) {
      final match = template.$1.firstMatch(source);
      if (match != null) {
        return template.$2.replaceAllMapped(
          RegExp(r'\{(\d+)\}'),
          (m) => match.group(int.parse(m[1]!) + 1) ?? '',
        );
      }
    }
    return source;
  }
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => ['ru', 'en'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

String tr(BuildContext context, String source) =>
    Localizations.of<AppStrings>(context, AppStrings)?.translate(source) ??
    source;

/// Const-friendly UI text. Callers keep user-authored data in ordinary Text.
class UiText extends StatelessWidget {
  const UiText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.translate = true,
  });
  final String data;
  final bool translate;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) => Text(
    translate ? tr(context, data) : data,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}

class UiSelectableText extends StatelessWidget {
  const UiSelectableText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) =>
      SelectableText(tr(context, data), style: style);
}
