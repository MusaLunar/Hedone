import '../../core/storage/local_store.dart';
import '../../domain/models/comic_item.dart';
import '../../domain/models/reader_models.dart';
import 'eh_api_service.dart';
import 'eh_parser.dart';
import 'eh_url.dart';

/// High-level E-Hentai / ExHentai repository.
class EhRepository {
  EhRepository({
    required EhApiService api,
    required LocalStore store,
  }) : _api = api,
       _store = store;

  final EhApiService _api;
  final LocalStore _store;

  bool get isExHentai => _store.ehUseExHentai && _store.isEhLoggedIn;

  Future<ComicListResult> fetchGalleryList({
    String path = '/',
    String searchQuery = '',
    int? enabledCategoryMask,
    String? nextCursor,
    String? prevCursor,
    bool advancedSearch = false,
    int? minRating,
    int? minPages,
    int? maxPages,
    bool includeExpunged = false,
    bool onlyTorrents = false,
  }) async {
    final useEx = isExHentai;
    final url = EhUrl.buildGalleryListUrl(
      useExHentai: useEx,
      path: path,
      enabledCategoryMask: enabledCategoryMask ?? _store.ehCategoryMask,
      searchQuery: searchQuery,
      nextCursor: nextCursor,
      prevCursor: prevCursor,
      advancedSearch: advancedSearch,
      minRating: minRating,
      minPages: minPages,
      maxPages: maxPages,
      includeExpunged: includeExpunged,
      onlyTorrents: onlyTorrents,
    );
    final html = await _api.getHtml(url, useExHentai: useEx);
    return EhParser.parseGalleryList(html, isExHentai: useEx);
  }

  Future<ComicListResult> fetchPopular() async {
    return fetchGalleryList(path: '/popular', enabledCategoryMask: EhUrl.allCategoryMask);
  }

  Future<ComicListResult> fetchWatched({String? nextCursor}) async {
    return fetchGalleryList(
      path: '/watched',
      enabledCategoryMask: EhUrl.allCategoryMask,
      nextCursor: nextCursor,
    );
  }

  Future<ComicListResult> fetchToplist({
    String boardId = '15',
    int page = 0,
  }) async {
    final url = EhUrl.toplistUrl(boardId: boardId, page: page);
    final html = await _api.getHtml(url, useExHentai: false);
    final result = EhParser.parseGalleryList(html, isExHentai: false);
    return ComicListResult(
      items: result.items,
      total: result.items.length,
      hasMore: result.items.isNotEmpty && page < 199,
      nextCursor: '${page + 1}',
      totalText: result.totalText,
    );
  }

  Future<CloudFavoritesResult> fetchCloudFavorites({
    String favCat = '',
    String searchQuery = '',
    String? nextCursor,
  }) async {
    final useEx = isExHentai;
    final url = EhUrl.buildGalleryListUrl(
      useExHentai: useEx,
      path: '/favorites.php',
      enabledCategoryMask: EhUrl.allCategoryMask,
      favCat: favCat,
      searchQuery: searchQuery,
      nextCursor: nextCursor,
    );
    final html = await _api.getHtml(url, useExHentai: useEx);
    return EhParser.parseFavoritesPage(html, isExHentai: useEx);
  }

  Future<void> toggleCloudFavorite({
    required String gid,
    required String token,
    required bool remove,
    String favCat = '0',
  }) async {
    final useEx = isExHentai;
    final url =
        '${EhUrl.host(useEx)}/gallerypopups.php?gid=$gid&t=$token&act=addfav';
    await _api.postForm(
      url,
      {
        'favcat': remove ? 'favdel' : favCat,
        'favnote': '',
        'submit': 'Apply Changes',
        'update': '1',
      },
      useExHentai: useEx,
      referer: url,
    );
  }

  Future<ComicDetail> fetchDetail(
    String gid,
    String token, {
    int previewPage = 0,
    bool showAllComments = false,
  }) async {
    final useEx = isExHentai;
    final url = EhUrl.galleryDetailUrl(
      useExHentai: useEx,
      gid: gid,
      token: token,
      previewPage: previewPage,
      showAllComments: showAllComments,
    );
    final html = await _api.getHtml(url, useExHentai: useEx);
    return EhParser.parseGalleryDetail(
      html,
      gid: gid,
      token: token,
      isExHentai: useEx,
    );
  }

  Future<List<EhPreviewItem>> fetchPreviewPage({
    required String gid,
    required String token,
    required int previewPage,
  }) async {
    final useEx = isExHentai;
    final url = EhUrl.galleryDetailUrl(
      useExHentai: useEx,
      gid: gid,
      token: token,
      previewPage: previewPage,
    );
    final html = await _api.getHtml(url, useExHentai: useEx);
    return EhParser.parsePreviewsFromHtml(html);
  }

  /// Resolves a single E-Hentai gallery page to its real image URL.
  Future<EhPageResolution> resolvePageImage({
    required String gid,
    required String galleryToken,
    required String pageToken,
    required int pageNumber,
    String? showKey,
    String? nlKey,
  }) async {
    final useEx = isExHentai;
    final pageUrl = EhUrl.galleryPageUrl(
      useExHentai: useEx,
      pToken: pageToken,
      gid: gid,
      pageNumber: pageNumber,
      nlKey: nlKey,
    );

    if (showKey != null && showKey.isNotEmpty && (nlKey == null || nlKey.isEmpty)) {
      try {
        final json = await _api.postApi(
          {
            'method': 'showpage',
            'gid': int.tryParse(gid) ?? gid,
            'page': pageNumber,
            'imgkey': pageToken,
            'showkey': showKey,
          },
          useExHentai: useEx,
          referer: pageUrl,
        );
        return EhParser.parseShowPageApi(json);
      } catch (_) {
        // Fallback to HTML scraping if showkey expired or rejected.
      }
    }

    final detailReferer = EhUrl.galleryDetailUrl(
      useExHentai: useEx,
      gid: gid,
      token: galleryToken,
    );
    final html = await _api.getHtml(
      pageUrl,
      useExHentai: useEx,
      referer: detailReferer,
    );
    return EhParser.parseGalleryPage(html);
  }

  /// Builds initial lazy-loaded [ComicPageData] placeholders for the reader.
  List<ComicPageData> buildPagePlaceholders({
    required int totalPages,
    required List<EhPreviewItem> initialPreviews,
  }) {
    final count = totalPages > 0 ? totalPages : initialPreviews.length;
    final byPage = <int, EhPreviewItem>{
      for (final item in initialPreviews) item.pageNumber: item,
    };

    return List.generate(count, (index) {
      final pageNum = index + 1;
      final preview = byPage[pageNum];
      return ComicPageData(
        pageIndex: index,
        pageNumber: pageNum,
        ehPageToken: preview?.pageToken,
        ehPageUrl: preview?.pageUrl,
      );
    });
  }
}
