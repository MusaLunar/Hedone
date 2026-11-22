import 'package:flutter/foundation.dart';

import '../../../core/app_dependencies.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/reader_models.dart';

class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required this.deps,
    required this.initialSummary,
  });

  final AppDependencies deps;
  final ComicSummary initialSummary;

  ComicDetail? _detail;
  bool _isLoading = true;
  String? _error;
  int _currentPreviewPage = 0;
  bool _isLoadingPreviews = false;

  ComicDetail? get detail => _detail;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPreviewPage => _currentPreviewPage;
  bool get isLoadingPreviews => _isLoadingPreviews;

  ComicSummary get summary => _detail?.summary ?? initialSummary;

  bool get isLocalFavorite =>
      deps.store.isFavorite(initialSummary.source, initialSummary.id);

  ReadingProgress? get readingProgress =>
      deps.store.getProgress(initialSummary.source, initialSummary.id);

  Future<void> loadDetail({bool showAllComments = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (initialSummary.source == ComicSource.jmcomic) {
        _detail = await deps.jmRepo.fetchDetail(initialSummary.id);
      } else {
        _detail = await deps.ehRepo.fetchDetail(
          initialSummary.id,
          initialSummary.token,
          previewPage: _currentPreviewPage,
          showAllComments: showAllComments,
        );
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPreviewPage(int pageIndex) async {
    if (initialSummary.source != ComicSource.ehentai || _detail == null) return;
    _isLoadingPreviews = true;
    notifyListeners();

    try {
      final previews = await deps.ehRepo.fetchPreviewPage(
        gid: initialSummary.id,
        token: initialSummary.token,
        previewPage: pageIndex,
      );
      _currentPreviewPage = pageIndex;
      _detail = _detail!.copyWith(previews: previews);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingPreviews = false;
      notifyListeners();
    }
  }

  Future<void> saveToFavoriteFolder(String folderId) async {
    await deps.store.saveFavorite(summary, folderId: folderId);
    notifyListeners();
  }

  Future<void> removeLocalFavorite() async {
    await deps.store.removeFavorite(summary.source, summary.id);
    notifyListeners();
  }

  Future<String?> toggleCloudFavorite() async {
    try {
      if (summary.source == ComicSource.jmcomic) {
        if (!deps.store.isJmLoggedIn) {
          return '请先在设置中登录 JMComic 账号';
        }
        final ok = await deps.jmRepo.toggleCloudFavorite(summary.id);
        if (_detail != null) {
          _detail = _detail!.copyWith(isFavorited: ok);
          notifyListeners();
        }
        return ok ? '已同步至 JM 云端收藏' : '已取消 JM 云端收藏';
      } else {
        if (!deps.store.isEhLoggedIn) {
          return '请先在设置中登录 E-Hentai Cookie';
        }
        final currentlyFav = _detail?.isFavorited ?? false;
        await deps.ehRepo.toggleCloudFavorite(
          gid: summary.id,
          token: summary.token,
          remove: currentlyFav,
        );
        if (_detail != null) {
          _detail = _detail!.copyWith(isFavorited: !currentlyFav);
          notifyListeners();
        }
        return !currentlyFav ? '已加入 EH 云端收藏' : '已从 EH 云端收藏移除';
      }
    } catch (e) {
      return '云端操作失败: $e';
    }
  }

  Future<String?> postJmComment(String text) async {
    if (summary.source != ComicSource.jmcomic) return 'E-Hentai 暂不支持直接发表评论';
    if (!deps.store.isJmLoggedIn) return '请先在设置中登录 JMComic 账号';
    if (text.trim().isEmpty) return '请输入评论内容';
    try {
      await deps.jmRepo.sendComment(summary.id, text);
      await loadDetail();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
