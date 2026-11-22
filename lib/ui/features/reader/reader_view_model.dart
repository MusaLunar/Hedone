import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/app_dependencies.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/reader_models.dart';

class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel({
    required this.deps,
    required this.summary,
    this.detail,
    this.initialChapter,
    this.initialPageIndex = 0,
    this.offlineTask,
  }) : _mode = deps.store.defaultReaderMode,
       _currentPageIndex = initialPageIndex;

  final AppDependencies deps;
  final ComicSummary summary;
  final ComicDetail? detail;
  final ComicChapter? initialChapter;
  final int initialPageIndex;
  final DownloadTask? offlineTask;

  ReaderMode _mode;
  ComicChapter? _currentChapter;
  List<ComicPageData> _pages = [];
  int _currentPageIndex;
  bool _isLoadingChapter = true;
  String? _error;

  String? _ehShowKey;
  final Map<int, String> _ehTokenMap = {};
  final Set<int> _loadedPreviewPages = {0};
  final Set<int> _resolvingIndices = {};
  int _ehPerPreviewPage = 20;

  ReaderMode get mode => _mode;
  ComicChapter? get currentChapter => _currentChapter;
  List<ComicPageData> get pages => _pages;
  int get currentPageIndex => _currentPageIndex;
  bool get isLoadingChapter => _isLoadingChapter;
  String? get error => _error;

  List<ComicChapter> get chapters => detail?.chapters ?? const [];

  bool get hasPrevChapter {
    if (summary.source != ComicSource.jmcomic || chapters.length <= 1) {
      return false;
    }
    final idx = chapters.indexWhere((c) => c.id == _currentChapter?.id);
    return idx > 0;
  }

  bool get hasNextChapter {
    if (summary.source != ComicSource.jmcomic || chapters.length <= 1) {
      return false;
    }
    final idx = chapters.indexWhere((c) => c.id == _currentChapter?.id);
    return idx >= 0 && idx < chapters.length - 1;
  }

  Future<void> init() async {
    _currentChapter = initialChapter ??
        (chapters.isNotEmpty
            ? chapters.first
            : ComicChapter(
                id: summary.id,
                title: summary.title,
                sort: '1',
                index: 0,
              ));
    await _loadCurrentSourcePages(resetPageIndex: false);
  }

  Future<void> _loadCurrentSourcePages({bool resetPageIndex = true}) async {
    _isLoadingChapter = true;
    _error = null;
    if (resetPageIndex) _currentPageIndex = 0;
    notifyListeners();

    try {
      final chapterId = _currentChapter?.id ?? summary.id;
      final completedDl =
          offlineTask ?? deps.store.findCompletedDownload(summary.source, chapterId);

      if (completedDl != null && completedDl.pages.isNotEmpty) {
        _pages = completedDl.pages
            .map(
              (asset) => ComicPageData(
                pageIndex: asset.pageNumber - 1,
                pageNumber: asset.pageNumber,
                imageUrl: asset.imageUrl,
                localFilePath: asset.localPath,
                chapterId: completedDl.chapterId,
                scrambleId: completedDl.scrambleId,
              ),
            )
            .toList();
      } else if (summary.source == ComicSource.jmcomic) {
        final payload = await deps.jmRepo.fetchChapterPages(chapterId);
        _pages = payload.pages;
      } else {
        var resolvedDetail = detail;
        resolvedDetail ??= await deps.ehRepo.fetchDetail(
          summary.id,
          summary.token,
        );
        if (resolvedDetail.previews.isNotEmpty) {
          _ehPerPreviewPage = resolvedDetail.previews.length >= 40 ? 40 : 20;
          for (final item in resolvedDetail.previews) {
            _ehTokenMap[item.pageNumber] = item.pageToken;
          }
        }
        final total = resolvedDetail.summary.pageCount ??
            resolvedDetail.previews.length;
        _pages = deps.ehRepo.buildPagePlaceholders(
          totalPages: total,
          initialPreviews: resolvedDetail.previews,
        );
      }

      if (_pages.isNotEmpty) {
        _currentPageIndex = _currentPageIndex.clamp(0, _pages.length - 1);
      } else {
        _currentPageIndex = 0;
      }

      _saveProgress();
      if (summary.source == ComicSource.ehentai && _pages.isNotEmpty) {
        unawaited(_prefetchEhWindow(_currentPageIndex));
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingChapter = false;
      notifyListeners();
    }
  }

  Future<void> switchChapter(ComicChapter chapter) async {
    if (_currentChapter?.id == chapter.id) return;
    _currentChapter = chapter;
    await _loadCurrentSourcePages(resetPageIndex: true);
  }

  Future<void> goToNextChapter() async {
    final idx = chapters.indexWhere((c) => c.id == _currentChapter?.id);
    if (idx >= 0 && idx < chapters.length - 1) {
      await switchChapter(chapters[idx + 1]);
    }
  }

  Future<void> goToPrevChapter() async {
    final idx = chapters.indexWhere((c) => c.id == _currentChapter?.id);
    if (idx > 0) {
      await switchChapter(chapters[idx - 1]);
    }
  }

  Future<void> setMode(ReaderMode nextMode) async {
    _mode = nextMode;
    await deps.store.setDefaultReaderMode(nextMode);
    notifyListeners();
  }

  void onPageChanged(int index) {
    if (index < 0 || index >= _pages.length) return;
    if (_currentPageIndex == index) return;
    _currentPageIndex = index;
    _saveProgress();
    if (summary.source == ComicSource.ehentai) {
      unawaited(_prefetchEhWindow(index));
    }
    notifyListeners();
  }

  void _saveProgress() {
    if (_pages.isEmpty) return;
    final chapter = _currentChapter;
    deps.store.updateProgress(
      ReadingProgress(
        source: summary.source,
        comicId: summary.id,
        chapterId: chapter?.id ?? summary.id,
        chapterTitle: chapter?.title ?? summary.title,
        pageIndex: _currentPageIndex,
        totalPages: _pages.length,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        summary: summary,
      ),
    );
  }

  Future<void> _prefetchEhWindow(int center) async {
    final targets = [center, center + 1, center + 2, center + 3];
    for (final idx in targets) {
      if (idx >= 0 && idx < _pages.length) {
        unawaited(ensureEhPageResolved(idx));
      }
    }
  }

  Future<void> ensureEhPageResolved(
    int index, {
    bool forceNlReload = false,
  }) async {
    if (summary.source != ComicSource.ehentai) return;
    if (index < 0 || index >= _pages.length) return;
    final current = _pages[index];
    if (current.localFilePath != null && current.localFilePath!.isNotEmpty) {
      return;
    }
    if (!forceNlReload &&
        current.imageUrl != null &&
        current.imageUrl!.isNotEmpty) {
      return;
    }
    if (_resolvingIndices.contains(index)) return;

    _resolvingIndices.add(index);
    _pages[index] = current.copyWith(isLoading: true, clearError: true);
    notifyListeners();

    try {
      var pToken = current.ehPageToken ?? _ehTokenMap[current.pageNumber];
      if (pToken == null || pToken.isEmpty) {
        final previewPageIdx = (current.pageNumber - 1) ~/ _ehPerPreviewPage;
        if (!_loadedPreviewPages.contains(previewPageIdx)) {
          _loadedPreviewPages.add(previewPageIdx);
          final previews = await deps.ehRepo.fetchPreviewPage(
            gid: summary.id,
            token: summary.token,
            previewPage: previewPageIdx,
          );
          for (final pItem in previews) {
            _ehTokenMap[pItem.pageNumber] = pItem.pageToken;
          }
          pToken = _ehTokenMap[current.pageNumber];
        }
      }

      if (pToken == null || pToken.isEmpty) {
        throw StateError('无法定位第 ${current.pageNumber} 页令牌');
      }

      final resolved = await deps.ehRepo.resolvePageImage(
        gid: summary.id,
        galleryToken: summary.token,
        pageToken: pToken,
        pageNumber: current.pageNumber,
        showKey: forceNlReload ? null : _ehShowKey,
        nlKey: forceNlReload ? current.skipHathKey : null,
      );

      if (resolved.showKey != null && resolved.showKey!.isNotEmpty) {
        _ehShowKey = resolved.showKey;
      }

      if (resolved.is509) {
        _pages[index] = _pages[index].copyWith(
          isLoading: false,
          errorMessage: 'E-Hentai 509 配额超限',
          ehPageToken: pToken,
          skipHathKey: resolved.skipHathKey,
        );
      } else {
        _pages[index] = _pages[index].copyWith(
          imageUrl: resolved.imageUrl,
          ehPageToken: pToken,
          skipHathKey: resolved.skipHathKey,
          isLoading: false,
          clearError: true,
        );
      }
    } catch (e) {
      _pages[index] = _pages[index].copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    } finally {
      _resolvingIndices.remove(index);
      notifyListeners();
    }
  }
}
