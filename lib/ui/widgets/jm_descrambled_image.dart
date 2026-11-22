import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/app_http_client.dart';
import '../../core/utils/jm_image_descrambler.dart';
import '../../domain/models/comic_item.dart';

/// Lightweight async semaphore bounding concurrent image downloads so grid
/// screens do not burst dozens of simultaneous TLS handshakes on startup.
class _ImageDownloadPool {
  static const int _maxConcurrent = 4;
  static int _active = 0;
  static final Queue<Completer<void>> _waiters = Queue();

  static Future<T> run<T>(
    Future<T> Function() task, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: 'Cancelled before acquiring download slot',
      );
    }

    if (_active >= _maxConcurrent) {
      final completer = Completer<void>();
      _waiters.addLast(completer);
      await completer.future;
    } else {
      _active++;
    }

    try {
      if (cancelToken?.isCancelled == true) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: 'Cancelled while waiting for download slot',
        );
      }
      return await task();
    } finally {
      if (_waiters.isNotEmpty) {
        final next = _waiters.removeFirst();
        next.complete();
      } else {
        _active--;
      }
    }
  }
}

/// Bounded LRU memory cache for network image bytes so scrolling lists & readers stay smooth
/// while respecting custom proxy / TLS / Cookie headers from [AppHttpClient].
class _ImageMemoryCache {
  static const int _maxEntries = 120;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  static Uint8List? get(String key) {
    final val = _cache.remove(key);
    if (val != null) {
      _cache[key] = val;
    }
    return val;
  }

  static void put(String key, Uint8List bytes) {
    if (bytes.length > 8 * 1024 * 1024) return;
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void remove(String key) => _cache.remove(key);

  static void clear() => _cache.clear();
}

void clearHedoneImageMemoryCache() => _ImageMemoryCache.clear();

/// Proxy- and header-aware network/file image widget used for covers and E-Hentai pages.
class HedoneImage extends StatefulWidget {
  const HedoneImage({
    super.key,
    required this.url,
    required this.httpClient,
    this.localFilePath,
    this.headers,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorBuilder,
  });

  final String url;
  final AppHttpClient httpClient;
  final String? localFilePath;
  final Map<String, String>? headers;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget Function(BuildContext, Object, VoidCallback retry)? errorBuilder;

  @override
  State<HedoneImage> createState() => _HedoneImageState();
}

class _HedoneImageState extends State<HedoneImage> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HedoneImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.localFilePath != widget.localFilePath) {
      _load();
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    final localPath = widget.localFilePath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        if (!mounted) return;
        final fileBytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _bytes = fileBytes;
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    if (widget.url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '图片地址为空';
      });
      return;
    }

    if (!forceRefresh) {
      final cached = _ImageMemoryCache.get(widget.url);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _bytes = cached;
          _loading = false;
          _error = null;
        });
        return;
      }
    } else {
      _ImageMemoryCache.remove(widget.url);
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final resp = await _ImageDownloadPool.run(
        () => widget.httpClient.getWithRetry<List<int>>(
          widget.url,
          cancelToken: _cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            headers: widget.headers,
          ),
        ),
        cancelToken: _cancelToken,
      );
      final bytes = Uint8List.fromList(resp.data ?? const []);
      if (bytes.isEmpty) {
        throw const FormatException('图片数据为空');
      }
      _ImageMemoryCache.put(widget.url, bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (_cancelToken?.isCancelled == true || !mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    }
    if (_error != null || _bytes == null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error ?? '加载失败', () => _load(forceRefresh: true));
      }
      return InkWell(
        onTap: () => _load(forceRefresh: true),
        child: Container(
          width: widget.width,
          height: widget.height,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Icon(
            Icons.broken_image_outlined,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (context, err, _) {
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, err, () => _load(forceRefresh: true));
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
        );
      },
    );
  }
}

/// Renders a JMComic page image, automatically descrambling sliced chapters and caching PNGs.
class JmDescrambledImage extends StatefulWidget {
  const JmDescrambledImage({
    super.key,
    required this.chapterId,
    required this.imageUrl,
    required this.httpClient,
    this.scrambleId = JmImageDescrambler.defaultScrambleId,
    this.localFilePath,
    this.fit = BoxFit.contain,
    this.onErrorRetry,
  });

  final String chapterId;
  final String imageUrl;
  final AppHttpClient httpClient;
  final int scrambleId;
  final String? localFilePath;
  final BoxFit fit;
  final VoidCallback? onErrorRetry;

  @override
  State<JmDescrambledImage> createState() => _JmDescrambledImageState();
}

class _JmDescrambledImageState extends State<JmDescrambledImage> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  CancelToken? _cancelToken;

  String get _cacheKey =>
      'jm:${widget.chapterId}:${widget.scrambleId}:${widget.imageUrl}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JmDescrambledImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.chapterId != widget.chapterId ||
        oldWidget.localFilePath != widget.localFilePath) {
      _load();
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    final localPath = widget.localFilePath;
    if (localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    if (!forceRefresh) {
      final mem = _ImageMemoryCache.get(_cacheKey);
      if (mem != null) {
        if (!mounted) return;
        setState(() {
          _bytes = mem;
          _loading = false;
          _error = null;
        });
        return;
      }
    } else {
      _ImageMemoryCache.remove(_cacheKey);
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final sliceCount = JmImageDescrambler.calculateSliceCount(
        widget.chapterId,
        widget.imageUrl,
        scrambleId: widget.scrambleId,
      );

      File? diskFile;
      try {
        diskFile = await JmImageDescrambler.getCacheFile(
          widget.chapterId,
          widget.imageUrl,
        );
        if (forceRefresh && await diskFile.exists()) {
          await diskFile.delete();
        } else if (await diskFile.exists()) {
          final cachedBytes = await diskFile.readAsBytes();
          if (cachedBytes.isNotEmpty) {
            _ImageMemoryCache.put(_cacheKey, cachedBytes);
            if (!mounted) return;
            setState(() {
              _bytes = cachedBytes;
              _loading = false;
              _error = null;
            });
            return;
          }
        }
      } catch (_) {
        diskFile = null;
      }

      final resp = await _ImageDownloadPool.run(
        () => widget.httpClient.getWithRetry<List<int>>(
          widget.imageUrl,
          cancelToken: _cancelToken,
          options: Options(responseType: ResponseType.bytes),
        ),
        cancelToken: _cancelToken,
      );
      var bytes = Uint8List.fromList(resp.data ?? const []);
      if (bytes.isEmpty) {
        throw const FormatException('图片下载为空');
      }

      if (sliceCount > 1) {
        bytes = await JmImageDescrambler.descrambleWithUiCanvas(bytes, sliceCount);
      }

      if (diskFile != null) {
        try {
          await diskFile.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }

      _ImageMemoryCache.put(_cacheKey, bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (_cancelToken?.isCancelled == true || !mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return Container(
        constraints: const BoxConstraints(minHeight: 260),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (_error != null || _bytes == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 240),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 40, color: cs.error),
            const SizedBox(height: 8),
            Text(
              '图片加载失败',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                widget.onErrorRetry?.call();
                _load(forceRefresh: true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}

/// Renders an E-Hentai preview thumbnail, supporting both standalone thumbs and CSS sprite sheets.
class EhPreviewThumbWidget extends StatefulWidget {
  const EhPreviewThumbWidget({
    super.key,
    required this.preview,
    required this.httpClient,
  });

  final EhPreviewItem preview;
  final AppHttpClient httpClient;

  @override
  State<EhPreviewThumbWidget> createState() => _EhPreviewThumbWidgetState();
}

class _EhPreviewThumbWidgetState extends State<EhPreviewThumbWidget> {
  ui.Image? _spriteImage;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.preview.isSprite && widget.preview.width > 0) {
      _loadSprite();
    }
  }

  @override
  void didUpdateWidget(covariant EhPreviewThumbWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.thumbUrl != widget.preview.thumbUrl) {
      _spriteImage?.dispose();
      _spriteImage = null;
      _failed = false;
      if (widget.preview.isSprite && widget.preview.width > 0) {
        _loadSprite();
      }
    }
  }

  @override
  void dispose() {
    _spriteImage?.dispose();
    super.dispose();
  }

  Future<void> _loadSprite() async {
    final url = widget.preview.thumbUrl;
    if (url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      var bytes = _ImageMemoryCache.get(url);
      if (bytes == null) {
        final resp = await _ImageDownloadPool.run(
          () => widget.httpClient.getWithRetry<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes),
          ),
        );
        bytes = Uint8List.fromList(resp.data ?? const []);
        if (bytes.isNotEmpty) {
          _ImageMemoryCache.put(url, bytes);
        }
      }
      if (bytes.isEmpty) throw const FormatException('Empty sprite');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _spriteImage = frame.image;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!widget.preview.isSprite || widget.preview.width <= 0) {
      return HedoneImage(
        url: widget.preview.thumbUrl,
        httpClient: widget.httpClient,
        fit: BoxFit.cover,
      );
    }

    if (_failed) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
      );
    }
    if (_spriteImage == null) {
      return Container(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return CustomPaint(
      painter: _SpriteThumbPainter(
        image: _spriteImage!,
        srcRect: ui.Rect.fromLTWH(
          widget.preview.xOffset.toDouble(),
          widget.preview.yOffset.toDouble(),
          widget.preview.width.toDouble(),
          widget.preview.height.toDouble(),
        ),
      ),
    );
  }
}

class _SpriteThumbPainter extends CustomPainter {
  const _SpriteThumbPainter({
    required this.image,
    required this.srcRect,
  });

  final ui.Image image;
  final ui.Rect srcRect;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _SpriteThumbPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}
