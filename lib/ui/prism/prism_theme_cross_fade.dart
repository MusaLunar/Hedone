import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Ported from FlClash / `prism_ui/lib/theme_cross_fade.dart`.
///
/// Switches [ThemeData] in a single frame and fades a GPU snapshot of the
/// previous frame out on top, avoiding expensive per-frame ThemeData lerping.
class PrismThemeCrossFade extends StatefulWidget {
  const PrismThemeCrossFade({
    super.key,
    this.duration = const Duration(milliseconds: 220),
    this.themeKey,
    required this.child,
  });

  final Duration duration;
  final Object? themeKey;
  final Widget child;

  @override
  State<PrismThemeCrossFade> createState() => _PrismThemeCrossFadeState();
}

class _PrismThemeCrossFadeState extends State<PrismThemeCrossFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_handleStatus);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  final GlobalKey _fadeKey = GlobalKey();
  ThemeData? _theme;
  ui.Image? _snapshot;
  Size? _snapshotSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final previous = _theme;
    _theme = theme;
    if (widget.themeKey == null && previous != null && previous != theme) {
      _capture();
    }
  }

  @override
  void didUpdateWidget(covariant PrismThemeCrossFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.themeKey != null && widget.themeKey != oldWidget.themeKey) {
      _capture();
    }
  }

  void _capture() {
    if (MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    switch (WidgetsBinding.instance.lifecycleState) {
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        return;
      case _:
    }
    final fade = _fadeKey.currentContext?.findRenderObject();
    if (fade is! _RenderPrismThemeCrossFade) {
      return;
    }
    final image = fade.capture(MediaQuery.devicePixelRatioOf(context));
    if (image == null) {
      return;
    }
    _snapshot?.dispose();
    _snapshot = image;
    _snapshotSize = fade.size;
    _controller.forward(from: 0);
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(_drop);
    }
  }

  void _drop() {
    _snapshot?.dispose();
    _snapshot = null;
    _snapshotSize = null;
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PrismThemeCrossFadeLayer(
      key: _fadeKey,
      snapshot: _snapshot,
      snapshotSize: _snapshotSize,
      progress: _curve,
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _PrismThemeCrossFadeLayer extends SingleChildRenderObjectWidget {
  const _PrismThemeCrossFadeLayer({
    super.key,
    required this.snapshot,
    required this.snapshotSize,
    required this.progress,
    super.child,
  });

  final ui.Image? snapshot;
  final Size? snapshotSize;
  final Animation<double> progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPrismThemeCrossFade(
        snapshot: snapshot,
        snapshotSize: snapshotSize,
        progress: progress,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPrismThemeCrossFade renderObject,
  ) {
    renderObject
      ..snapshot = snapshot
      ..snapshotSize = snapshotSize
      ..progress = progress;
  }
}

class _RenderPrismThemeCrossFade extends RenderProxyBox {
  _RenderPrismThemeCrossFade({
    ui.Image? snapshot,
    Size? snapshotSize,
    required Animation<double> progress,
  })  : _snapshot = snapshot,
        _snapshotSize = snapshotSize,
        _progress = progress;

  @override
  bool get isRepaintBoundary => true;

  ui.Image? _snapshot;

  set snapshot(ui.Image? value) {
    if (identical(value, _snapshot)) return;
    _snapshot = value;
    markNeedsPaint();
  }

  Size? _snapshotSize;

  set snapshotSize(Size? value) {
    _snapshotSize = value;
  }

  Animation<double> _progress;

  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  ui.Image? capture(double pixelRatio) {
    final currentLayer = layer;
    if (!attached ||
        !hasSize ||
        size.isEmpty ||
        debugNeedsPaint ||
        currentLayer is! OffsetLayer) {
      return null;
    }
    try {
      return currentLayer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final image = _snapshot;
    final weight = (1.0 - _progress.value).clamp(0.0, 1.0);
    if (image == null || weight <= 0 || _snapshotSize != size) {
      return;
    }
    final rect = offset & size;
    final fade = Color.fromRGBO(0, 0, 0, weight);
    // Premultiplied dstOut + plus avoids opacity bumps during cross-fade.
    context.canvas
      ..drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = fade,
      )
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = fade
          ..filterQuality = FilterQuality.low,
      );
  }
}
