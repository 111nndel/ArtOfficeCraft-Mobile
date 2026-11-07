import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import 'editor_tools.dart';

EditorTool pageJumpTool({
  required String label,
  required String fieldLabel,
  required int current,
  required int count,
  required ValueChanged<int>? onJump,
}) => EditorTool(
  label,
  Icons.pin_outlined,
  builder: (_) => _PageJump(
    label: label,
    fieldLabel: fieldLabel,
    current: current,
    count: count,
    onJump: onJump,
  ),
);

class _PageJump extends StatefulWidget {
  const _PageJump({
    required this.label,
    required this.fieldLabel,
    required this.current,
    required this.count,
    required this.onJump,
  });

  final String label, fieldLabel;
  final int current, count;
  final ValueChanged<int>? onJump;

  @override
  State<_PageJump> createState() => _PageJumpState();
}

class _PageJumpState extends State<_PageJump> {
  late final input = TextEditingController(text: '${widget.current + 1}');
  bool invalid = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void jump() {
    final target = int.tryParse(input.text.trim());
    if (target == null || target < 1 || target > widget.count) {
      setState(() => invalid = true);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onJump?.call(target - 1);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('reader-jump-number'),
        controller: input,
        enabled: widget.onJump != null,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: tr(context, widget.fieldLabel),
          helperText: '1–${widget.count}',
          errorText: invalid
              ? tr(context, 'Введите число от 1 до ${widget.count}')
              : null,
        ),
        onChanged: (_) {
          if (invalid) setState(() => invalid = false);
        },
        onSubmitted: (_) => jump(),
      ),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: widget.onJump == null ? null : jump,
        child: UiText(widget.label),
      ),
    ],
  );
}

enum ReadingMode {
  horizontal,
  vertical,
  continuous;

  Axis? get swipeAxis => switch (this) {
    horizontal => Axis.horizontal,
    vertical => Axis.vertical,
    continuous => null,
  };

  String get label => switch (this) {
    horizontal => 'По одной, горизонтально',
    vertical => 'По одной, вертикально',
    continuous => 'Непрерывно вниз',
  };

  IconData get icon => switch (this) {
    horizontal => Icons.swipe_left_alt,
    vertical => Icons.swipe_up_alt,
    continuous => Icons.view_stream_outlined,
  };
}

class ReadingModePreference extends ValueNotifier<ReadingMode> {
  ReadingModePreference(this.format) : super(ReadingMode.horizontal);

  final String format;
  static const _channel = MethodChannel('artofficecraft/reading');
  bool _chosen = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final name = await _channel.invokeMethod<String>('read', {
        'format': format,
      });
      if (_chosen || _disposed) return;
      for (final mode in ReadingMode.values) {
        if (mode.name == name) value = mode;
      }
    } catch (_) {
      // The reader can still use its default when storage is unavailable.
    }
  }

  void choose(ReadingMode mode) {
    _chosen = true;
    value = mode;
    unawaited(_write(mode));
  }

  Future<void> _write(ReadingMode mode) async {
    try {
      await _channel.invokeMethod<void>('write', {
        'format': format,
        'mode': mode.name,
      });
    } catch (_) {
      // The selected mode remains available for this reader session.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

EditorTool readingModeTool(ReadingModePreference preference) => EditorTool(
  'Режим чтения',
  Icons.chrome_reader_mode_outlined,
  builder: (_) => Column(
    children: [
      for (final mode in ReadingMode.values)
        ListTile(
          minTileHeight: 56,
          leading: Icon(mode.icon),
          title: UiText(mode.label),
          selected: preference.value == mode,
          trailing: preference.value == mode ? const Icon(Icons.check) : null,
          onTap: () => preference.choose(mode),
        ),
    ],
  ),
);

bool canTurnAtEdge(
  TransformationController transform,
  Rect content,
  Size viewport,
  Axis? axis,
  int delta,
) {
  if (axis == null) return false;
  final page = MatrixUtils.transformRect(transform.value, content);
  const tolerance = 8.0;
  if (axis == Axis.horizontal) {
    return delta > 0
        ? page.right <= viewport.width + tolerance
        : page.left >= -tolerance;
  }
  return delta > 0
      ? page.bottom <= viewport.height + tolerance
      : page.top >= -tolerance;
}

/// Observes a single-finger swipe without competing with pinch and pan.
class PageTurnGesture extends StatefulWidget {
  const PageTurnGesture({
    super.key,
    required this.axis,
    required this.canTurn,
    required this.onTurn,
    required this.child,
  });

  final Axis? axis;
  final bool Function(int delta) canTurn;
  final ValueChanged<int> onTurn;
  final Widget child;

  @override
  State<PageTurnGesture> createState() => _PageTurnGestureState();
}

class _PageTurnGestureState extends State<PageTurnGesture> {
  final _pointers = <int>{};
  Offset? _start;
  Axis? _axis;
  bool _previous = false;
  bool _next = false;

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || event.kind != PointerDeviceKind.touch) {
      _start = null;
      return;
    }
    _axis = widget.axis;
    _start = _axis == null ? null : event.localPosition;
    _previous = widget.canTurn(-1);
    _next = widget.canTurn(1);
  }

  void _up(PointerUpEvent event) {
    final start = _start;
    _start = null;
    final single = _pointers.length == 1;
    _pointers.remove(event.pointer);
    if (!single || start == null || _axis != widget.axis) return;
    final offset = event.localPosition - start;
    final distance = _axis == Axis.horizontal ? offset.dx : offset.dy;
    final cross = _axis == Axis.horizontal ? offset.dy : offset.dx;
    if (distance.abs() < 54 || distance.abs() < cross.abs() * 1.25) return;
    if (distance < 0 && _next) widget.onTurn(1);
    if (distance > 0 && _previous) widget.onTurn(-1);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: (event) {
      _start = null;
      _pointers.remove(event.pointer);
    },
    child: widget.child,
  );
}

/// One pannable document canvas with only visible page widgets mounted.
class ContinuousPages extends StatefulWidget {
  const ContinuousPages({
    super.key,
    required this.sizes,
    required this.page,
    required this.onPageChanged,
    required this.pageBuilder,
    this.enabled = true,
    this.reveal,
  });

  final List<Size> sizes;
  final int page;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder pageBuilder;
  final bool enabled;
  final ({int page, double fraction})? reveal;

  @override
  State<ContinuousPages> createState() => ContinuousPagesState();
}

class ContinuousPagesState extends State<ContinuousPages> {
  final transform = TransformationController();
  final _tops = <double>[];
  final _heights = <double>[];
  List<Size>? _measured;
  Size _viewport = Size.zero;
  bool _jumpQueued = false;
  bool _noticeQueued = false;
  int? _reportedPage;
  static const _margin = 8.0;
  static const _gap = 12.0;
  double get _documentHeight => math.max(
    _tops.last + _heights.last + _margin,
    _tops.last - _margin + _viewport.height,
  );

  @override
  void initState() {
    super.initState();
    transform.addListener(_positionChanged);
  }

  @override
  void didUpdateWidget(covariant ContinuousPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.page != oldWidget.page && widget.page != _reportedPage) ||
        (widget.reveal != null && widget.reveal != oldWidget.reveal)) {
      _queueJump();
    }
    if (widget.enabled && !oldWidget.enabled) _positionChanged();
  }

  void _queueJump() {
    if (_jumpQueued) return;
    _jumpQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpQueued = false;
      if (!mounted) return;
      final reveal = widget.reveal;
      fitWidth(fraction: reveal?.page == widget.page ? reveal!.fraction : 0);
    });
  }

  void fitWidth({double fraction = 0}) {
    if (_tops.isEmpty) return;
    final page = widget.page.clamp(0, _tops.length - 1);
    _reportedPage = page;
    final top = _tops[page] - _margin;
    final offset = (fraction * _heights[page] - _viewport.height / 4).clamp(
      0.0,
      math.max(0.0, _documentHeight - _viewport.height - top),
    );
    transform.value = Matrix4.identity()
      ..setTranslationRaw(0, -top - offset, 0);
  }

  int _pageAt(double y) {
    var first = 0;
    var last = _tops.length;
    while (first < last) {
      final middle = (first + last) ~/ 2;
      if (_tops[middle] <= y) {
        first = middle + 1;
      } else {
        last = middle;
      }
    }
    return math.max(0, first - 1);
  }

  void _positionChanged() {
    if (!widget.enabled || _tops.isEmpty || _jumpQueued || _noticeQueued) {
      return;
    }
    _noticeQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _noticeQueued = false;
      if (!mounted || !widget.enabled || _jumpQueued) return;
      final page = _pageAt(transform.toScene(const Offset(0, _margin + 1)).dy);
      if (page == widget.page) return;
      _reportedPage = page;
      widget.onPageChanged(page);
    });
  }

  void _measure(Size viewport) {
    if (identical(_measured, widget.sizes) &&
        _viewport.width == viewport.width) {
      _viewport = viewport;
      return;
    }
    _measured = widget.sizes;
    _viewport = viewport;
    _tops.clear();
    _heights.clear();
    var top = _margin;
    final width = math.max(1.0, viewport.width - _margin * 2);
    for (final size in widget.sizes) {
      final aspect = (size.height / size.width).clamp(.01, 90.0);
      final height = math.max(16.0, width * aspect);
      _tops.add(top);
      _heights.add(height);
      top += height + _gap;
    }
    _queueJump();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      _measure(box.biggest);
      if (_tops.isEmpty) return const SizedBox.shrink();
      final height = _documentHeight;
      return ColoredBox(
        color: const Color(0xffdce1e8),
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: InteractiveViewer.builder(
            key: const Key('continuous-pages'),
            transformationController: transform,
            minScale: 1,
            maxScale: 5,
            alignment: Alignment.topLeft,
            builder: (context, viewport) {
              final target = widget.page.clamp(0, _tops.length - 1);
              final top = _jumpQueued
                  ? _tops[target] - _margin
                  : transform.toScene(Offset.zero).dy;
              final bottom = _jumpQueued
                  ? top + _viewport.height
                  : transform.toScene(Offset(0, _viewport.height)).dy;
              final first = _pageAt(top);
              final last = _pageAt(bottom);
              return SizedBox(
                width: _viewport.width,
                height: height,
                child: Stack(
                  children: [
                    for (var i = first; i <= last; i++)
                      Positioned(
                        key: ValueKey(i),
                        left: _margin,
                        right: _margin,
                        top: _tops[i],
                        height: _heights[i],
                        child: widget.pageBuilder(context, i),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
