import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/network/app_http_client.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/jm_image_descrambler.dart';
import '../../domain/models/comic_item.dart';
import '../../domain/models/comic_source.dart';
import '../../domain/models/download_task.dart';
import '../ehentai/eh_api_service.dart';
import '../ehentai/eh_repository.dart';
import '../jmcomic/jm_repository.dart';

/// Multi-threaded offline comic downloader for JMComic & E-Hentai.
/// Automatically descrambles JMComic slices in background isolates before saving.
class DownloadService extends ChangeNotifier {
  DownloadService({
    required LocalStore store,
    required AppHttpClient httpClient,
    required JmRepository jmRepo,
    required EhRepository ehRepo,
    required EhApiService ehApi,
  }) : _store = store,
       _http = httpClient,
       _jmRepo = jmRepo,
       _ehRepo = ehRepo,
       _ehApi = ehApi;

  final LocalStore _store;
  final AppHttpClient _http;
  final JmRepository _jmRepo;
  final EhRepository _ehRepo;
  final EhApiService _ehApi;

  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _runningIds = {};

  Future<Directory> _taskDirectory(
    ComicSource source,
    String comicId,
    String chapterId,
  ) async {
    final docDir = await getApplicationDocumentsDirectory();
    final safeComic = comicId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeChapter = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dir = Directory(
      p.join(docDir.path, 'hedone_downloads', '${source.name}_${safeComic}_$safeChapter'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> enqueueJmChapter({
    required ComicSummary summary,
    required ComicChapter chapter,
  }) async {
    final taskId = '${ComicSource.jmcomic.name}:${summary.id}:${chapter.id}';
    final existing = _store.findDownloadTask(taskId);
    if (existing != null && existing.status == DownloadStatus.completed) {
      return;
    }

    final payload = await _jmRepo.fetchChapterPages(chapter.id);
    final dir = await _taskDirectory(ComicSource.jmcomic, summary.id, chapter.id);

    final pages = payload.pages.map((pg) {
      final padded = pg.pageNumber.toString().padLeft(4, '0');
      final url = pg.imageUrl ?? '';
      final ext = url.toLowerCase().contains('.gif') ? 'gif' : 'png';
      return DownloadPageAsset(
        pageNumber: pg.pageNumber,
        imageUrl: url,
        localPath: p.join(dir.path, '$padded.$ext'),
      );
    }).toList();

    final task = DownloadTask(
      id: taskId,
      source: ComicSource.jmcomic,
      summary: summary,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      scrambleId: payload.scrambleId,
      status: DownloadStatus.queued,
      downloadedCount: 0,
      totalCount: pages.length,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      pages: pages,
    );

    await _store.upsertDownloadTask(task);
    unawaited(_runTask(taskId));
  }

  Future<void> enqueueEhGallery({
    required ComicDetail detail,
  }) async {
    final summary = detail.summary;
    final taskId = '${ComicSource.ehentai.name}:${summary.id}:${summary.id}';
    final existing = _store.findDownloadTask(taskId);
    if (existing != null && existing.status == DownloadStatus.completed) {
      return;
    }

    final dir = await _taskDirectory(ComicSource.ehentai, summary.id, summary.id);
    final total = summary.pageCount ?? detail.previews.length;
    final previewMap = <int, EhPreviewItem>{
      for (final item in detail.previews) item.pageNumber: item,
    };

    final pages = List.generate(total, (i) {
      final num = i + 1;
      final padded = num.toString().padLeft(4, '0');
      final preview = previewMap[num];
      return DownloadPageAsset(
        pageNumber: num,
        ehPageToken: preview?.pageToken,
        ehPageUrl: preview?.pageUrl,
        localPath: p.join(dir.path, '$padded.jpg'),
      );
    });

    final task = DownloadTask(
      id: taskId,
      source: ComicSource.ehentai,
      summary: summary,
      chapterId: summary.id,
      chapterTitle: summary.title,
      scrambleId: 0,
      status: DownloadStatus.queued,
      downloadedCount: 0,
      totalCount: pages.length,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      pages: pages,
    );

    await _store.upsertDownloadTask(task);
    unawaited(_runTask(taskId));
  }

  Future<void> pauseTask(String taskId) async {
    _cancelTokens[taskId]?.cancel('Paused by user');
    _cancelTokens.remove(taskId);
    _runningIds.remove(taskId);
    final task = _store.findDownloadTask(taskId);
    if (task != null && task.status != DownloadStatus.completed) {
      await _store.upsertDownloadTask(
        task.copyWith(status: DownloadStatus.paused),
      );
    }
  }

  Future<void> resumeTask(String taskId) async {
    unawaited(_runTask(taskId));
  }

  Future<void> deleteTask(String taskId) async {
    await pauseTask(taskId);
    final task = _store.findDownloadTask(taskId);
    if (task != null && task.pages.isNotEmpty) {
      final parent = Directory(p.dirname(task.pages.first.localPath));
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    }
    await _store.removeDownloadTask(taskId);
  }

  Future<void> _runTask(String taskId) async {
    if (_runningIds.contains(taskId)) return;
    var task = _store.findDownloadTask(taskId);
    if (task == null || task.pages.isEmpty) return;

    _runningIds.add(taskId);
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    task = task.copyWith(status: DownloadStatus.downloading, clearError: true);
    await _store.upsertDownloadTask(task);

    try {
      final mutablePages = List<DownloadPageAsset>.from(task.pages);
      final previewTokenCache = <int, String>{
        for (final pItem in mutablePages)
          if (pItem.ehPageToken != null && pItem.ehPageToken!.isNotEmpty)
            pItem.pageNumber: pItem.ehPageToken!,
      };
      String? showKey;

      if (task.source == ComicSource.ehentai) {
        await _runEhDownloads(
          task: task,
          pages: mutablePages,
          previewTokenCache: previewTokenCache,
          showKey: showKey,
          cancelToken: cancelToken,
        );
      } else {
        await _runJmDownloads(
          task: task,
          pages: mutablePages,
          cancelToken: cancelToken,
        );
      }

      if (cancelToken.isCancelled) return;
      final latest = _store.findDownloadTask(taskId);
      if (latest == null) return;
      final completedCount = latest.pages.where((e) => e.completed).length;
      final allDone = completedCount == latest.totalCount && latest.totalCount > 0;
      await _store.upsertDownloadTask(
        latest.copyWith(
          downloadedCount: completedCount,
          status: allDone ? DownloadStatus.completed : DownloadStatus.failed,
          errorMessage: allDone ? null : '部分页面下载失败，请重试',
        ),
      );
    } catch (e) {
      if (!cancelToken.isCancelled) {
        final latest = _store.findDownloadTask(taskId);
        if (latest != null) {
          await _store.upsertDownloadTask(
            latest.copyWith(
              status: DownloadStatus.failed,
              errorMessage: e.toString(),
            ),
          );
        }
      }
    } finally {
      _runningIds.remove(taskId);
      _cancelTokens.remove(taskId);
    }
  }

  Future<void> _runJmDownloads({
    required DownloadTask task,
    required List<DownloadPageAsset> pages,
    required CancelToken cancelToken,
  }) async {
    var cursor = 0;
    const workerCount = 3;

    Future<void> worker() async {
      while (!cancelToken.isCancelled) {
        final idx = cursor++;
        if (idx >= pages.length) break;
        final page = pages[idx];
        if (page.completed && await File(page.localPath).exists()) {
          continue;
        }
        final url = page.imageUrl ?? '';
        if (url.isEmpty) continue;

        final resp = await _http.getWithRetry<List<int>>(
          url,
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.bytes),
        );
        var bytes = Uint8List.fromList(resp.data ?? const []);
        final sliceCount = JmImageDescrambler.calculateSliceCount(
          task.chapterId,
          url,
          scrambleId: task.scrambleId,
        );
        if (sliceCount > 1) {
          bytes = await JmImageDescrambler.descrambleInIsolate(bytes, sliceCount);
        }
        await File(page.localPath).writeAsBytes(bytes, flush: true);
        pages[idx] = page.copyWith(completed: true);

        final done = pages.where((e) => e.completed).length;
        await _store.upsertDownloadTask(
          task.copyWith(
            status: DownloadStatus.downloading,
            downloadedCount: done,
            pages: List<DownloadPageAsset>.from(pages),
          ),
        );
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  Future<void> _runEhDownloads({
    required DownloadTask task,
    required List<DownloadPageAsset> pages,
    required Map<int, String> previewTokenCache,
    required String? showKey,
    required CancelToken cancelToken,
  }) async {
    final loadedPreviewPages = <int>{};
    final perPreviewPage = previewTokenCache.length >= 20
        ? (previewTokenCache.length >= 40 ? 40 : 20)
        : 20;

    for (var i = 0; i < pages.length; i++) {
      if (cancelToken.isCancelled) break;
      final page = pages[i];
      if (page.completed && await File(page.localPath).exists()) {
        continue;
      }

      var pToken = previewTokenCache[page.pageNumber];
      if (pToken == null || pToken.isEmpty) {
        final previewPageIndex = (page.pageNumber - 1) ~/ perPreviewPage;
        if (!loadedPreviewPages.contains(previewPageIndex)) {
          loadedPreviewPages.add(previewPageIndex);
          final fetched = await _ehRepo.fetchPreviewPage(
            gid: task.summary.id,
            token: task.summary.token,
            previewPage: previewPageIndex,
          );
          for (final item in fetched) {
            previewTokenCache[item.pageNumber] = item.pageToken;
          }
          pToken = previewTokenCache[page.pageNumber];
        }
      }

      if (pToken == null || pToken.isEmpty) {
        throw StateError('无法获取第 ${page.pageNumber} 页令牌');
      }

      final resolved = await _ehRepo.resolvePageImage(
        gid: task.summary.id,
        galleryToken: task.summary.token,
        pageToken: pToken,
        pageNumber: page.pageNumber,
        showKey: showKey,
      );
      if (resolved.showKey != null && resolved.showKey!.isNotEmpty) {
        showKey = resolved.showKey;
      }
      if (resolved.is509) {
        throw StateError('E-Hentai 图片配额已满 (509)');
      }

      final resp = await _http.getWithRetry<List<int>>(
        resolved.imageUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          headers: _ehApi.buildHeaders(useExHentai: _ehRepo.isExHentai),
        ),
      );
      final bytes = Uint8List.fromList(resp.data ?? const []);
      if (bytes.isEmpty) {
        throw StateError('第 ${page.pageNumber} 页下载为空');
      }
      await File(page.localPath).writeAsBytes(bytes, flush: true);
      pages[i] = page.copyWith(
        imageUrl: resolved.imageUrl,
        ehPageToken: pToken,
        completed: true,
      );

      final done = pages.where((e) => e.completed).length;
      await _store.upsertDownloadTask(
        task.copyWith(
          status: DownloadStatus.downloading,
          downloadedCount: done,
          pages: List<DownloadPageAsset>.from(pages),
        ),
      );
    }
  }
}
