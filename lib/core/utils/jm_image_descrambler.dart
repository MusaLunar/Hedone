import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// JMComic3 image descrambling utility matching JMComic3 `utils/Function.js`.
class JmImageDescrambler {
  static const int defaultScrambleId = 220980;

  /// Extracts the page filename stem without query string or extension.
  /// Example: `https://.../media/photos/1216570/00001.webp?t=123` -> `00001`.
  static String extractPageName(String imageUrl) {
    final cleanUrl = imageUrl.split('?').first.split('#').first;
    final match = RegExp(r'/([^/]+)\.[^./]+$').firstMatch(cleanUrl);
    if (match != null) {
      return match.group(1)!;
    }
    final lastSegment = cleanUrl.split('/').last;
    final dotIndex = lastSegment.lastIndexOf('.');
    return dotIndex > 0 ? lastSegment.substring(0, dotIndex) : lastSegment;
  }

  /// Calculates the vertical slice count `num` (`0` means no descrambling needed).
  static int calculateSliceCount(
    String chapterId,
    String imageUrl, {
    int scrambleId = defaultScrambleId,
  }) {
    final aid = int.tryParse(chapterId.trim()) ?? 0;
    final cleanUrl = imageUrl.split('?').first.toLowerCase();
    if (aid <= 0 || cleanUrl.endsWith('.gif') || aid < scrambleId) {
      return 0;
    }

    final pageName = extractPageName(imageUrl);
    if (pageName.isEmpty) {
      return 0;
    }

    final md5Hex = md5.convert(utf8.encode('$aid$pageName')).toString();
    final lastCharCode = md5Hex.codeUnitAt(md5Hex.length - 1);

    if (aid < 268850) {
      return 10;
    }

    final int mod;
    if (aid <= 421925) {
      mod = lastCharCode % 10;
    } else {
      mod = lastCharCode % 8;
    }
    return mod * 2 + 2;
  }

  /// Pure-Dart isolate-safe descrambler using `package:image`.
  /// Suitable for unit tests and background downloads without Flutter UI binding.
  static Uint8List descrambleBytesSync(Uint8List rawBytes, int numSlices) {
    if (numSlices <= 1) {
      return rawBytes;
    }
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return rawBytes;
    }

    final w = decoded.width;
    final h = decoded.height;
    if (w <= 0 || h <= 0 || numSlices > h) {
      return rawBytes;
    }

    final output = img.Image(width: w, height: h, numChannels: decoded.numChannels);
    final remainder = h % numSlices;
    final baseH = h ~/ numSlices;

    for (var i = 0; i < numSlices; i++) {
      var copyH = baseH;
      var py = baseH * i;
      final y = h - baseH * (i + 1) - remainder;
      if (i == 0) {
        copyH += remainder;
      } else {
        py += remainder;
      }
      img.compositeImage(
        output,
        decoded,
        dstX: 0,
        dstY: py,
        dstW: w,
        dstH: copyH,
        srcX: 0,
        srcY: y,
        srcW: w,
        srcH: copyH,
        blend: img.BlendMode.direct,
      );
    }

    return Uint8List.fromList(img.encodePng(output));
  }

  /// Runs [descrambleBytesSync] inside a background isolate.
  static Future<Uint8List> descrambleInIsolate(
    Uint8List rawBytes,
    int numSlices,
  ) {
    if (numSlices <= 1) {
      return Future.value(rawBytes);
    }
    return Isolate.run(() => descrambleBytesSync(rawBytes, numSlices));
  }

  /// Fast UI-engine descrambler using `ui.instantiateImageCodec` + `Canvas.drawImageRect`.
  static Future<Uint8List> descrambleWithUiCanvas(
    Uint8List rawBytes,
    int numSlices,
  ) async {
    if (numSlices <= 1) {
      return rawBytes;
    }

    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    final w = source.width;
    final h = source.height;
    if (w <= 0 || h <= 0 || numSlices > h) {
      source.dispose();
      return rawBytes;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final remainder = h % numSlices;
    final baseH = h ~/ numSlices;

    for (var i = 0; i < numSlices; i++) {
      var copyH = baseH;
      var py = baseH * i;
      final y = h - baseH * (i + 1) - remainder;
      if (i == 0) {
        copyH += remainder;
      } else {
        py += remainder;
      }
      final srcRect = ui.Rect.fromLTWH(0, y.toDouble(), w.toDouble(), copyH.toDouble());
      final dstRect = ui.Rect.fromLTWH(0, py.toDouble(), w.toDouble(), copyH.toDouble());
      canvas.drawImageRect(source, srcRect, dstRect, paint);
    }

    final picture = recorder.endRecording();
    final resultImage = await picture.toImage(w, h);
    final byteData = await resultImage.toByteData(format: ui.ImageByteFormat.png);

    source.dispose();
    picture.dispose();
    resultImage.dispose();

    if (byteData == null) {
      return rawBytes;
    }
    return byteData.buffer.asUint8List();
  }

  /// Returns cached descrambled file path if it already exists on disk.
  static Future<File> getCacheFile(String chapterId, String imageUrl) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'jm_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final pageName = extractPageName(imageUrl);
    return File(p.join(dir.path, '${chapterId}_$pageName.png'));
  }

  /// Clears cached descrambled JMComic images.
  static Future<int> clearCache() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'jm_images'));
    if (!await dir.exists()) return 0;
    var deletedBytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        deletedBytes += await entity.length();
      }
    }
    await dir.delete(recursive: true);
    return deletedBytes;
  }
}
