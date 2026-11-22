import 'package:flutter/foundation.dart';

import '../../../core/app_dependencies.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';

enum JmExploreTab {
  promote('推荐'),
  latest('最新'),
  weekly('每周必看');

  const JmExploreTab(this.label);
  final String label;
}

enum EhExploreTab {
  frontPage('最新'),
  popular('热门'),
  toplist('排行榜'),
  watched('关注');

  const EhExploreTab(this.label);
  final String label;
}

class ExploreViewModel extends ChangeNotifier {
  ExploreViewModel({required this.deps});

  final AppDependencies deps;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  // Dual-source aggregated state
  List<ComicSummary> _aggFeatured = [];
  List<ComicSummary> _aggItems = [];
  int _aggJmPage = 1;
  String? _aggEhNextCursor;
  bool _aggHasMore = true;

  // JMComic dedicated state
  JmExploreTab _jmTab = JmExploreTab.promote;
  List<JmPromoteSection> _jmPromoteSections = [];
  List<ComicSummary> _jmLatestItems = [];
  int _jmLatestPage = 1;
  bool _jmLatestHasMore = true;
  JmWeekMeta? _jmWeekMeta;
  String _selectedWeekPeriodId = '';
  String _selectedWeekTypeId = 'manga';
  List<ComicSummary> _jmWeekItems = [];
  int _jmWeekPage = 0;
  bool _jmWeekHasMore = false;

  // E-Hentai dedicated state
  EhExploreTab _ehTab = EhExploreTab.frontPage;
  List<ComicSummary> _ehItems = [];
  String? _ehNextCursor;
  bool _ehHasMore = false;
  String _ehToplistBoard = '15';
  int _ehToplistPage = 0;

  SourceScope get scope => deps.store.exploreScope;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;

  List<ComicSummary> get aggFeatured => _aggFeatured;
  List<ComicSummary> get aggItems => _aggItems;
  bool get aggHasMore => _aggHasMore;

  JmExploreTab get jmTab => _jmTab;
  List<JmPromoteSection> get jmPromoteSections => _jmPromoteSections;
  List<ComicSummary> get jmLatestItems => _jmLatestItems;
  bool get jmLatestHasMore => _jmLatestHasMore;
  JmWeekMeta? get jmWeekMeta => _jmWeekMeta;
  String get selectedWeekPeriodId => _selectedWeekPeriodId;
  String get selectedWeekTypeId => _selectedWeekTypeId;
  List<ComicSummary> get jmWeekItems => _jmWeekItems;
  bool get jmWeekHasMore => _jmWeekHasMore;

  EhExploreTab get ehTab => _ehTab;
  List<ComicSummary> get ehItems => _ehItems;
  bool get ehHasMore => _ehHasMore;
  String get ehToplistBoard => _ehToplistBoard;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_isLoading) return;
    switch (scope) {
      case SourceScope.all:
        if (_aggItems.isEmpty) await refresh();
      case SourceScope.jmcomic:
        if (_jmTab == JmExploreTab.promote && _jmPromoteSections.isEmpty) {
          await refresh();
        } else if (_jmTab == JmExploreTab.latest && _jmLatestItems.isEmpty) {
          await refresh();
        } else if (_jmTab == JmExploreTab.weekly && _jmWeekItems.isEmpty) {
          await refresh();
        }
      case SourceScope.ehentai:
        if (_ehItems.isEmpty) await refresh();
    }
  }

  Future<void> setScope(SourceScope next) async {
    if (scope == next) return;
    await deps.store.setExploreScope(next);
    _error = null;
    notifyListeners();
    await ensureLoaded();
  }

  Future<void> setJmTab(JmExploreTab tab) async {
    if (_jmTab == tab) return;
    _jmTab = tab;
    _error = null;
    notifyListeners();
    await ensureLoaded();
  }

  Future<void> setEhTab(EhExploreTab tab) async {
    if (_ehTab == tab) return;
    _ehTab = tab;
    _ehItems = [];
    _ehNextCursor = null;
    _ehToplistPage = 0;
    _error = null;
    notifyListeners();
    await refresh();
  }

  Future<void> setEhToplistBoard(String boardId) async {
    if (_ehToplistBoard == boardId) return;
    _ehToplistBoard = boardId;
    _ehToplistPage = 0;
    _ehItems = [];
    await refresh();
  }

  Future<void> toggleEhCategoryBit(int bit) async {
    final nextMask = deps.store.ehCategoryMask ^ bit;
    await deps.store.setEhCategoryMask(nextMask == 0 ? bit : nextMask);
    if (scope == SourceScope.ehentai && _ehTab == EhExploreTab.frontPage) {
      await refresh();
    } else if (scope == SourceScope.all) {
      await refresh();
    }
  }

  Future<void> setWeekFilter({String? periodId, String? typeId}) async {
    if (periodId != null) _selectedWeekPeriodId = periodId;
    if (typeId != null) _selectedWeekTypeId = typeId;
    _jmWeekPage = 0;
    _jmWeekItems = [];
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      switch (scope) {
        case SourceScope.all:
          await _loadAggregated(reset: true);
        case SourceScope.jmcomic:
          await _loadJm(reset: true);
        case SourceScope.ehentai:
          await _loadEh(reset: true);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore) return;
    _isLoadingMore = true;
    _safeNotify();

    try {
      switch (scope) {
        case SourceScope.all:
          if (_aggHasMore) await _loadAggregated(reset: false);
        case SourceScope.jmcomic:
          await _loadJm(reset: false);
        case SourceScope.ehentai:
          if (_ehHasMore) await _loadEh(reset: false);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      _safeNotify();
    }
  }

  Future<void> _loadAggregated({required bool reset}) async {
    if (reset) {
      _aggJmPage = 1;
      _aggEhNextCursor = null;
    }

    final jmFuture = deps.jmRepo.fetchLatest(page: _aggJmPage).then<ComicListResult?>(
      (v) => v,
      onError: (Object e) {
        _error = 'JMComic: $e';
        return null;
      },
    );
    final ehFuture = deps.ehRepo
        .fetchGalleryList(
          nextCursor: _aggEhNextCursor,
        )
        .then<ComicListResult?>(
      (v) => v,
      onError: (Object e) {
        _error = '${_error != null ? '$_error\n' : ''}E-Hentai: $e';
        return null;
      },
    );

    Future<List<JmPromoteSection>>? promoteFuture;
    if (reset) {
      promoteFuture = deps.jmRepo.fetchPromote().then(
        (v) => v,
        onError: (_) => const <JmPromoteSection>[],
      );
    }

    final jmRes = await jmFuture;
    final ehRes = await ehFuture;
    final promote = promoteFuture != null ? await promoteFuture : null;

    if (reset && promote != null && promote.isNotEmpty) {
      _aggFeatured = promote.first.items.take(12).toList();
    }

    final jmList = jmRes?.items ?? const <ComicSummary>[];
    final ehList = ehRes?.items ?? const <ComicSummary>[];
    if (jmList.isEmpty && ehList.isEmpty && reset && _error != null) {
      throw StateError(_error!);
    }

    final merged = _interleave(jmList, ehList);
    if (reset) {
      _aggItems = merged;
    } else {
      _aggItems = [..._aggItems, ...merged];
    }

    if (jmRes != null && jmRes.hasMore) _aggJmPage++;
    if (ehRes != null) _aggEhNextCursor = ehRes.nextCursor;
    _aggHasMore = (jmRes?.hasMore ?? false) || (ehRes?.hasMore ?? false);
  }

  Future<void> _loadJm({required bool reset}) async {
    switch (_jmTab) {
      case JmExploreTab.promote:
        if (!reset) return;
        _jmPromoteSections = await deps.jmRepo.fetchPromote();
      case JmExploreTab.latest:
        if (reset) {
          _jmLatestPage = 1;
        } else if (!_jmLatestHasMore) {
          return;
        }
        final res = await deps.jmRepo.fetchLatest(page: _jmLatestPage);
        _jmLatestItems =
            reset ? res.items : [..._jmLatestItems, ...res.items];
        _jmLatestHasMore = res.hasMore;
        if (res.hasMore) _jmLatestPage++;
      case JmExploreTab.weekly:
        if (_jmWeekMeta == null || reset && _selectedWeekPeriodId.isEmpty) {
          _jmWeekMeta = await deps.jmRepo.fetchWeeklyMeta();
          if (_selectedWeekPeriodId.isEmpty &&
              _jmWeekMeta!.periods.isNotEmpty) {
            _selectedWeekPeriodId = _jmWeekMeta!.periods.first.id;
          }
          if (_jmWeekMeta!.types.isNotEmpty &&
              !_jmWeekMeta!.types.any((t) => t.id == _selectedWeekTypeId)) {
            _selectedWeekTypeId = _jmWeekMeta!.types.first.id;
          }
        }
        if (_selectedWeekPeriodId.isEmpty) return;
        if (reset) {
          _jmWeekPage = 0;
        } else if (!_jmWeekHasMore) {
          return;
        }
        final res = await deps.jmRepo.fetchWeeklyList(
          categoryId: _selectedWeekPeriodId,
          typeId: _selectedWeekTypeId,
          page: _jmWeekPage,
        );
        _jmWeekItems = reset ? res.items : [..._jmWeekItems, ...res.items];
        _jmWeekHasMore = res.items.length >= 20;
        if (_jmWeekHasMore) _jmWeekPage++;
    }
  }

  Future<void> _loadEh({required bool reset}) async {
    if (reset) {
      _ehNextCursor = null;
      _ehToplistPage = 0;
    }

    final ComicListResult res;
    switch (_ehTab) {
      case EhExploreTab.frontPage:
        res = await deps.ehRepo.fetchGalleryList(
          nextCursor: _ehNextCursor,
        );
      case EhExploreTab.popular:
        if (!reset) return;
        res = await deps.ehRepo.fetchPopular();
      case EhExploreTab.toplist:
        res = await deps.ehRepo.fetchToplist(
          boardId: _ehToplistBoard,
          page: _ehToplistPage,
        );
        if (res.hasMore) _ehToplistPage++;
      case EhExploreTab.watched:
        res = await deps.ehRepo.fetchWatched(nextCursor: _ehNextCursor);
    }

    _ehItems = reset ? res.items : [..._ehItems, ...res.items];
    _ehNextCursor = res.nextCursor;
    _ehHasMore = res.hasMore;
  }

  static List<ComicSummary> _interleave(
    List<ComicSummary> a,
    List<ComicSummary> b,
  ) {
    final result = <ComicSummary>[];
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < a.length) result.add(a[i]);
      if (i < b.length) result.add(b[i]);
    }
    return result;
  }
}
