import 'package:flutter/foundation.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/utils/eh_tag_translator.dart';
import '../../../data/ehentai/eh_url.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';

class DirectComicTarget {
  const DirectComicTarget({
    required this.source,
    required this.id,
    this.token = '',
  });

  final ComicSource source;
  final String id;
  final String token;
}

class JmSortOption {
  const JmSortOption(this.code, this.label);
  final String code;
  final String label;
}

class SearchViewModel extends ChangeNotifier {
  SearchViewModel({required this.deps});

  final AppDependencies deps;

  static const List<JmSortOption> jmSorts = [
    JmSortOption('mv', '最多观看'),
    JmSortOption('mr', '最新'),
    JmSortOption('tf', '最多爱心'),
    JmSortOption('mv_t', '日榜'),
    JmSortOption('mv_w', '周榜'),
    JmSortOption('mv_m', '月榜'),
  ];

  SourceScope _scope = SourceScope.all;
  String _query = '';
  String _activeCategorySlug = '';
  String _jmSort = 'mv';

  // E-Hentai advanced filters
  int _ehCategoryMask = EhUrl.allCategoryMask;
  bool _ehAdvanced = false;
  int? _ehMinRating;
  int? _ehMinPages;
  int? _ehMaxPages;
  bool _ehIncludeExpunged = false;
  bool _ehOnlyTorrents = false;

  // Discovery data
  JmCategoriesData? _jmCategories;
  List<String> _jmHotTags = [];
  bool _loadingMeta = false;

  // Search results
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasExecutedSearch = false;
  String? _error;
  List<ComicSummary> _results = [];
  int _jmPage = 1;
  bool _jmHasMore = false;
  String? _ehNextCursor;
  bool _ehHasMore = false;
  List<TagSuggestion> _suggestions = [];

  SourceScope get scope => _scope;
  String get query => _query;
  String get activeCategorySlug => _activeCategorySlug;
  String get jmSort => _jmSort;
  int get ehCategoryMask => _ehCategoryMask;
  bool get ehAdvanced => _ehAdvanced;
  int? get ehMinRating => _ehMinRating;
  int? get ehMinPages => _ehMinPages;
  int? get ehMaxPages => _ehMaxPages;
  bool get ehIncludeExpunged => _ehIncludeExpunged;
  bool get ehOnlyTorrents => _ehOnlyTorrents;

  JmCategoriesData? get jmCategories => _jmCategories;
  List<String> get jmHotTags => _jmHotTags;
  bool get loadingMeta => _loadingMeta;

  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasExecutedSearch => _hasExecutedSearch;
  String? get error => _error;
  List<ComicSummary> get results => _results;
  bool get hasMore => _jmHasMore || _ehHasMore;
  List<TagSuggestion> get suggestions => _suggestions;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadMeta() async {
    if (_loadingMeta || _jmCategories != null) return;
    _loadingMeta = true;
    _safeNotify();

    try {
      final catsFuture = deps.jmRepo.fetchCategories().then<JmCategoriesData?>(
        (v) => v,
        onError: (_) => null,
      );
      final tagsFuture = deps.jmRepo.fetchHotTags().then<List<String>>(
        (v) => v,
        onError: (_) => const <String>[],
      );
      _jmCategories = await catsFuture;
      _jmHotTags = await tagsFuture;
    } catch (_) {
      // Non-fatal if JM discovery fails while offline.
    } finally {
      _loadingMeta = false;
      _safeNotify();
    }
  }

  void setScope(SourceScope next) {
    if (_scope == next) return;
    _scope = next;
    notifyListeners();
    if (_hasExecutedSearch) {
      if (_activeCategorySlug.isNotEmpty && next == SourceScope.jmcomic) {
        searchByJmCategory(_activeCategorySlug);
      } else if (_query.isNotEmpty) {
        executeSearch(_query);
      }
    }
  }

  void setJmSort(String sortCode) {
    if (_jmSort == sortCode) return;
    _jmSort = sortCode;
    notifyListeners();
    if (_hasExecutedSearch) {
      if (_activeCategorySlug.isNotEmpty) {
        searchByJmCategory(_activeCategorySlug);
      } else if (_query.isNotEmpty) {
        executeSearch(_query);
      }
    }
  }

  void updateSuggestions(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      _suggestions = [];
    } else {
      // Suggest from last token if typing multiple tags.
      final lastToken = trimmed.split(RegExp(r'\s+')).last;
      _suggestions = deps.tagTranslator.suggest(lastToken, limit: 20);
    }
    notifyListeners();
  }

  void updateEhFilters({
    int? categoryMask,
    bool? advanced,
    int? minRating,
    bool clearMinRating = false,
    int? minPages,
    int? maxPages,
    bool? includeExpunged,
    bool? onlyTorrents,
  }) {
    if (categoryMask != null) _ehCategoryMask = categoryMask;
    if (advanced != null) _ehAdvanced = advanced;
    if (clearMinRating) {
      _ehMinRating = null;
    } else if (minRating != null) {
      _ehMinRating = minRating;
    }
    if (minPages != null) _ehMinPages = minPages <= 0 ? null : minPages;
    if (maxPages != null) _ehMaxPages = maxPages <= 0 ? null : maxPages;
    if (includeExpunged != null) _ehIncludeExpunged = includeExpunged;
    if (onlyTorrents != null) _ehOnlyTorrents = onlyTorrents;
    notifyListeners();
  }

  /// Detects direct JM ID (`JM123456` / `123456`) or E-Hentai gallery URL (`/g/gid/token`).
  static DirectComicTarget? detectDirectTarget(String input) {
    final trimmed = input.trim();
    final ehMatch = RegExp(
      r'https?://(?:e-hentai|exhentai)\.org/g/(\d+)/([0-9a-f]{10})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (ehMatch != null) {
      return DirectComicTarget(
        source: ComicSource.ehentai,
        id: ehMatch.group(1)!,
        token: ehMatch.group(2)!,
      );
    }

    final jmMatch = RegExp(r'^(?:jm)?(\d{5,8})$', caseSensitive: false)
        .firstMatch(trimmed);
    if (jmMatch != null) {
      return DirectComicTarget(
        source: ComicSource.jmcomic,
        id: jmMatch.group(1)!,
      );
    }
    return null;
  }

  void clearResults() {
    _hasExecutedSearch = false;
    _activeCategorySlug = '';
    _results = [];
    _error = null;
    _suggestions = [];
    notifyListeners();
  }

  Future<void> searchByJmCategory(String slug) async {
    _scope = SourceScope.jmcomic;
    _activeCategorySlug = slug;
    _query = '';
    _jmPage = 1;
    _ehHasMore = false;
    _hasExecutedSearch = true;
    _isSearching = true;
    _error = null;
    _suggestions = [];
    notifyListeners();

    try {
      final res = await deps.jmRepo.fetchCategoryFilter(
        categorySlug: slug,
        sort: _jmSort,
        page: 1,
      );
      _results = res.items;
      _jmHasMore = res.hasMore;
      if (res.hasMore) _jmPage = 2;
    } catch (e) {
      _error = e.toString();
      _results = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> executeSearch(String rawQuery, {bool saveHistory = true}) async {
    final q = rawQuery.trim();
    _query = q;
    _activeCategorySlug = '';
    _suggestions = [];
    _hasExecutedSearch = true;
    _isSearching = true;
    _error = null;
    _jmPage = 1;
    _ehNextCursor = null;
    notifyListeners();

    if (saveHistory && q.isNotEmpty) {
      await deps.store.addSearchQuery(q);
    }

    try {
      await _fetchPage(reset: true);
    } catch (e) {
      _error = e.toString();
      _results = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isSearching || _isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      if (_activeCategorySlug.isNotEmpty) {
        final res = await deps.jmRepo.fetchCategoryFilter(
          categorySlug: _activeCategorySlug,
          sort: _jmSort,
          page: _jmPage,
        );
        _results = [..._results, ...res.items];
        _jmHasMore = res.hasMore;
        if (res.hasMore) _jmPage++;
      } else {
        await _fetchPage(reset: false);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _fetchPage({required bool reset}) async {
    ComicListResult? jmRes;
    ComicListResult? ehRes;
    final errors = <String>[];

    final runJm = (_scope == SourceScope.all || _scope == SourceScope.jmcomic) &&
        (reset || _jmHasMore);
    final runEh = (_scope == SourceScope.all || _scope == SourceScope.ehentai) &&
        (reset || _ehHasMore);

    final futures = <Future<void>>[];

    if (runJm) {
      futures.add(
        deps.jmRepo
            .search(query: _query, sort: _jmSort, page: _jmPage)
            .then((v) => jmRes = v)
            .catchError((Object e) {
              errors.add('JMComic: $e');
              return const ComicListResult(items: []);
            }),
      );
    }
    if (runEh) {
      futures.add(
        deps.ehRepo
            .fetchGalleryList(
              searchQuery: _query,
              enabledCategoryMask: _ehCategoryMask,
              nextCursor: _ehNextCursor,
              advancedSearch: _ehAdvanced,
              minRating: _ehMinRating,
              minPages: _ehMinPages,
              maxPages: _ehMaxPages,
              includeExpunged: _ehIncludeExpunged,
              onlyTorrents: _ehOnlyTorrents,
            )
            .then((v) => ehRes = v)
            .catchError((Object e) {
              errors.add('E-Hentai: $e');
              return const ComicListResult(items: []);
            }),
      );
    }

    await Future.wait(futures);

    final jmItems = jmRes?.items ?? const <ComicSummary>[];
    final ehItems = ehRes?.items ?? const <ComicSummary>[];
    if (reset && jmItems.isEmpty && ehItems.isEmpty && errors.isNotEmpty) {
      throw StateError(errors.join('\n'));
    }
    if (errors.isNotEmpty) {
      _error = errors.join('\n');
    }

    final merged = <ComicSummary>[];
    final maxLen = jmItems.length > ehItems.length ? jmItems.length : ehItems.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < jmItems.length) merged.add(jmItems[i]);
      if (i < ehItems.length) merged.add(ehItems[i]);
    }

    _results = reset ? merged : [..._results, ...merged];
    if (runJm) {
      _jmHasMore = jmRes?.hasMore ?? false;
      if (_jmHasMore) _jmPage++;
    } else if (reset) {
      _jmHasMore = false;
    }

    if (runEh) {
      _ehHasMore = ehRes?.hasMore ?? false;
      _ehNextCursor = ehRes?.nextCursor;
    } else if (reset) {
      _ehHasMore = false;
    }
  }
}
