import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/comic_item.dart';
import '../../domain/models/comic_source.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/reader_models.dart';

/// Persistent local store for Hedone preferences, auth credentials,
/// multi-folder favorites, reading progress history, search history, and downloads.
class LocalStore extends ChangeNotifier {
  LocalStore({bool inMemoryOnly = false}) : _inMemoryOnly = inMemoryOnly;

  final bool _inMemoryOnly;
  SharedPreferences? _prefs;
  Directory? _supportDir;

  // Theme & UI preferences
  ThemeMode _themeMode = ThemeMode.dark;
  String _themeSeedId = 'celestial_lavender';
  bool _amoledBlack = false;
  double _contrastLevel = 0.0; // 0.0 Standard, 0.5 Medium, 1.0 High
  bool _floatingNavBar = true;
  SourceScope _exploreScope = SourceScope.all;
  bool _translateEhTags = true;

  // Reader preferences
  ReaderMode _defaultReaderMode = ReaderMode.webtoon;
  double _readerBrightness = 1.0; // 0.2..1.0 (dimming overlay below 1.0)
  bool _keepHistory = true;

  // Network & Proxy
  String _proxyAddress = '';
  bool _allowBadCertificates = true;

  // JMComic settings & auth
  String _jmApiHost = 'www.cdnbtd.cc';
  int _jmImgShunt = 1;
  String _jmImgHost = 'https://cdn-msp.jmapiproxy3.cc';
  String _jmJwtToken = '';
  String _jmAvsCookie = '';
  String _jmUsername = '';

  // E-Hentai / ExHentai settings & auth
  bool _ehUseExHentai = false;
  String _ehMemberId = '';
  String _ehPassHash = '';
  String _ehIgneous = '';
  String _ehSk = '';
  int _ehCategoryMask = 0x3ff; // All 10 categories enabled by default

  // Collections & History
  final List<FavoriteFolder> _folders = [
    const FavoriteFolder(id: 'default', name: '默认收藏', createdAtMs: 0),
  ];
  final List<FavoriteEntry> _favorites = [];
  final Map<String, ReadingProgress> _history = {};
  final List<String> _searchHistory = [];
  final List<DownloadTask> _downloads = [];

  // Getters
  ThemeMode get themeMode => _themeMode;
  String get themeSeedId => _themeSeedId;
  bool get amoledBlack => _amoledBlack;
  double get contrastLevel => _contrastLevel;
  bool get floatingNavBar => _floatingNavBar;
  SourceScope get exploreScope => _exploreScope;
  bool get translateEhTags => _translateEhTags;

  ReaderMode get defaultReaderMode => _defaultReaderMode;
  double get readerBrightness => _readerBrightness;
  bool get keepHistory => _keepHistory;

  String get proxyAddress => _proxyAddress;
  bool get allowBadCertificates => _allowBadCertificates;

  String get jmApiHost => _jmApiHost;
  int get jmImgShunt => _jmImgShunt;
  String get jmImgHost => _jmImgHost;
  String get jmJwtToken => _jmJwtToken;
  String get jmAvsCookie => _jmAvsCookie;
  String get jmUsername => _jmUsername;
  bool get isJmLoggedIn => _jmJwtToken.isNotEmpty || _jmAvsCookie.isNotEmpty;

  bool get ehUseExHentai => _ehUseExHentai;
  String get ehMemberId => _ehMemberId;
  String get ehPassHash => _ehPassHash;
  String get ehIgneous => _ehIgneous;
  String get ehSk => _ehSk;
  int get ehCategoryMask => _ehCategoryMask;
  bool get isEhLoggedIn => _ehMemberId.isNotEmpty && _ehPassHash.isNotEmpty;

  List<FavoriteFolder> get folders => List.unmodifiable(_folders);
  List<FavoriteEntry> get favorites => List.unmodifiable(_favorites);
  List<ReadingProgress> get historyList {
    final items = _history.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return items;
  }

  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  List<DownloadTask> get downloads {
    final items = List<DownloadTask>.from(_downloads)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return items;
  }

  Future<void> init() async {
    if (_inMemoryOnly) return;
    _prefs = await SharedPreferences.getInstance();
    _supportDir = await getApplicationSupportDirectory();

    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == _prefs?.getString('themeMode'),
      orElse: () => ThemeMode.dark,
    );
    _themeSeedId = _prefs?.getString('themeSeedId') ?? 'celestial_lavender';
    _amoledBlack = _prefs?.getBool('amoledBlack') ?? false;
    _contrastLevel = (_prefs?.getDouble('contrastLevel') ?? 0.0).clamp(0.0, 1.0);
    _floatingNavBar = _prefs?.getBool('floatingNavBar') ?? true;
    _exploreScope = SourceScope.values.firstWhere(
      (e) => e.name == _prefs?.getString('exploreScope'),
      orElse: () => SourceScope.all,
    );
    _translateEhTags = _prefs?.getBool('translateEhTags') ?? true;

    _defaultReaderMode = ReaderMode.fromString(
      _prefs?.getString('defaultReaderMode'),
    );
    _readerBrightness = _prefs?.getDouble('readerBrightness') ?? 1.0;
    _keepHistory = _prefs?.getBool('keepHistory') ?? true;

    _proxyAddress = _prefs?.getString('proxyAddress') ?? '';
    _allowBadCertificates = _prefs?.getBool('allowBadCertificates') ?? true;

    _jmApiHost = _prefs?.getString('jmApiHost') ?? 'www.cdnbtd.cc';
    _jmImgShunt = _prefs?.getInt('jmImgShunt') ?? 1;
    _jmImgHost =
        _prefs?.getString('jmImgHost') ?? 'https://cdn-msp.jmapiproxy3.cc';
    _jmJwtToken = _prefs?.getString('jmJwtToken') ?? '';
    _jmAvsCookie = _prefs?.getString('jmAvsCookie') ?? '';
    _jmUsername = _prefs?.getString('jmUsername') ?? '';

    _ehUseExHentai = _prefs?.getBool('ehUseExHentai') ?? false;
    _ehMemberId = _prefs?.getString('ehMemberId') ?? '';
    _ehPassHash = _prefs?.getString('ehPassHash') ?? '';
    _ehIgneous = _prefs?.getString('ehIgneous') ?? '';
    _ehSk = _prefs?.getString('ehSk') ?? '';
    _ehCategoryMask = _prefs?.getInt('ehCategoryMask') ?? 0x3ff;

    final searchList = _prefs?.getStringList('searchHistory');
    if (searchList != null) {
      _searchHistory
        ..clear()
        ..addAll(searchList);
    }

    await _loadCollectionsFromDisk();
    notifyListeners();
  }

  Future<void> _loadCollectionsFromDisk() async {
    final dir = _supportDir;
    if (dir == null) return;
    final file = File(p.join(dir.path, 'hedone_data.json'));
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      final loadedFolders = (decoded['folders'] as List?)
          ?.map((e) => FavoriteFolder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loadedFolders != null && loadedFolders.isNotEmpty) {
        _folders
          ..clear()
          ..addAll(loadedFolders);
      }

      final loadedFavs = (decoded['favorites'] as List?)
          ?.map((e) => FavoriteEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loadedFavs != null) {
        _favorites
          ..clear()
          ..addAll(loadedFavs);
      }

      final loadedHistory = (decoded['history'] as List?)
          ?.map((e) => ReadingProgress.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loadedHistory != null) {
        _history.clear();
        for (final h in loadedHistory) {
          _history[h.uniqueKey] = h;
        }
      }

      final loadedDownloads = (decoded['downloads'] as List?)
          ?.map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (loadedDownloads != null) {
        _downloads
          ..clear()
          ..addAll(loadedDownloads.map((t) => t.status == DownloadStatus.downloading
              ? t.copyWith(status: DownloadStatus.paused)
              : t));
      }
    } catch (_) {
      // Ignore corrupt store file.
    }
  }

  Future<void> _saveCollectionsToDisk() async {
    if (_inMemoryOnly || _supportDir == null) return;
    final file = File(p.join(_supportDir!.path, 'hedone_data.json'));
    final payload = {
      'folders': _folders.map((e) => e.toJson()).toList(),
      'favorites': _favorites.map((e) => e.toJson()).toList(),
      'history': _history.values.map((e) => e.toJson()).toList(),
      'downloads': _downloads.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  // Settings setters
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setString('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> toggleDarkLightMode(Brightness currentBrightness) async {
    await setThemeMode(
      currentBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  Future<void> setThemeSeedId(String id) async {
    _themeSeedId = id;
    await _prefs?.setString('themeSeedId', id);
    notifyListeners();
  }

  Future<void> setAmoledBlack(bool value) async {
    _amoledBlack = value;
    await _prefs?.setBool('amoledBlack', value);
    notifyListeners();
  }

  Future<void> setContrastLevel(double value) async {
    _contrastLevel = value.clamp(0.0, 1.0);
    await _prefs?.setDouble('contrastLevel', _contrastLevel);
    notifyListeners();
  }

  Future<void> setFloatingNavBar(bool value) async {
    _floatingNavBar = value;
    await _prefs?.setBool('floatingNavBar', value);
    notifyListeners();
  }

  Future<void> setExploreScope(SourceScope scope) async {
    _exploreScope = scope;
    await _prefs?.setString('exploreScope', scope.name);
    notifyListeners();
  }

  Future<void> setTranslateEhTags(bool value) async {
    _translateEhTags = value;
    await _prefs?.setBool('translateEhTags', value);
    notifyListeners();
  }

  Future<void> setDefaultReaderMode(ReaderMode mode) async {
    _defaultReaderMode = mode;
    await _prefs?.setString('defaultReaderMode', mode.name);
    notifyListeners();
  }

  Future<void> setReaderBrightness(double value) async {
    _readerBrightness = value.clamp(0.2, 1.0);
    await _prefs?.setDouble('readerBrightness', _readerBrightness);
    notifyListeners();
  }

  Future<void> setKeepHistory(bool value) async {
    _keepHistory = value;
    await _prefs?.setBool('keepHistory', value);
    notifyListeners();
  }

  Future<void> setNetworkConfig({
    String? proxyAddress,
    bool? allowBadCertificates,
  }) async {
    if (proxyAddress != null) {
      _proxyAddress = proxyAddress.trim();
      await _prefs?.setString('proxyAddress', _proxyAddress);
    }
    if (allowBadCertificates != null) {
      _allowBadCertificates = allowBadCertificates;
      await _prefs?.setBool('allowBadCertificates', _allowBadCertificates);
    }
    notifyListeners();
  }

  Future<void> setJmNetwork({
    String? apiHost,
    int? imgShunt,
    String? imgHost,
  }) async {
    if (apiHost != null && apiHost.isNotEmpty) {
      _jmApiHost = apiHost;
      await _prefs?.setString('jmApiHost', apiHost);
    }
    if (imgShunt != null) {
      _jmImgShunt = imgShunt;
      await _prefs?.setInt('jmImgShunt', imgShunt);
    }
    if (imgHost != null && imgHost.isNotEmpty) {
      _jmImgHost = imgHost;
      await _prefs?.setString('jmImgHost', imgHost);
    }
    notifyListeners();
  }

  Future<void> setJmAuth({
    required String jwtToken,
    required String avsCookie,
    required String username,
  }) async {
    _jmJwtToken = jwtToken;
    _jmAvsCookie = avsCookie;
    _jmUsername = username;
    await _prefs?.setString('jmJwtToken', jwtToken);
    await _prefs?.setString('jmAvsCookie', avsCookie);
    await _prefs?.setString('jmUsername', username);
    notifyListeners();
  }

  Future<void> clearJmAuth() async {
    await setJmAuth(jwtToken: '', avsCookie: '', username: '');
  }

  Future<void> setEhUseExHentai(bool value) async {
    _ehUseExHentai = value;
    await _prefs?.setBool('ehUseExHentai', value);
    notifyListeners();
  }

  Future<void> setEhCookies({
    required String memberId,
    required String passHash,
    String igneous = '',
    String sk = '',
  }) async {
    _ehMemberId = memberId.trim();
    _ehPassHash = passHash.trim();
    _ehIgneous = igneous.trim();
    if (sk.isNotEmpty) _ehSk = sk.trim();
    await _prefs?.setString('ehMemberId', _ehMemberId);
    await _prefs?.setString('ehPassHash', _ehPassHash);
    await _prefs?.setString('ehIgneous', _ehIgneous);
    await _prefs?.setString('ehSk', _ehSk);
    notifyListeners();
  }

  Future<void> clearEhCookies() async {
    _ehMemberId = '';
    _ehPassHash = '';
    _ehIgneous = '';
    _ehSk = '';
    _ehUseExHentai = false;
    await _prefs?.remove('ehMemberId');
    await _prefs?.remove('ehPassHash');
    await _prefs?.remove('ehIgneous');
    await _prefs?.remove('ehSk');
    await _prefs?.setBool('ehUseExHentai', false);
    notifyListeners();
  }

  Future<void> setEhCategoryMask(int mask) async {
    _ehCategoryMask = mask & 0x3ff;
    await _prefs?.setInt('ehCategoryMask', _ehCategoryMask);
    notifyListeners();
  }

  // Favorites management
  bool isFavorite(ComicSource source, String comicId) {
    final key = '${source.name}:$comicId';
    return _favorites.any((e) => e.summary.uniqueKey == key);
  }

  String? favoriteFolderFor(ComicSource source, String comicId) {
    final key = '${source.name}:$comicId';
    for (final f in _favorites) {
      if (f.summary.uniqueKey == key) return f.folderId;
    }
    return null;
  }

  Future<void> createFavoriteFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    _folders.add(
      FavoriteFolder(
        id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
        name: clean,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> deleteFavoriteFolder(String folderId) async {
    if (folderId == 'default') return;
    _folders.removeWhere((f) => f.id == folderId);
    _favorites.removeWhere((e) => e.folderId == folderId);
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> saveFavorite(ComicSummary summary, {String folderId = 'default'}) async {
    _favorites.removeWhere((e) => e.summary.uniqueKey == summary.uniqueKey);
    _favorites.insert(
      0,
      FavoriteEntry(
        folderId: folderId,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
        summary: summary,
      ),
    );
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> removeFavorite(ComicSource source, String comicId) async {
    final key = '${source.name}:$comicId';
    _favorites.removeWhere((e) => e.summary.uniqueKey == key);
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  // Reading progress history
  ReadingProgress? getProgress(ComicSource source, String comicId) {
    return _history['${source.name}:$comicId'];
  }

  Future<void> updateProgress(ReadingProgress progress) async {
    if (!_keepHistory) return;
    _history[progress.uniqueKey] = progress;
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> removeHistoryItem(String uniqueKey) async {
    _history.remove(uniqueKey);
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  // Search history
  Future<void> addSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _searchHistory.remove(q);
    _searchHistory.insert(0, q);
    if (_searchHistory.length > 30) {
      _searchHistory.removeRange(30, _searchHistory.length);
    }
    await _prefs?.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> removeSearchQuery(String query) async {
    _searchHistory.remove(query);
    await _prefs?.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory.clear();
    await _prefs?.setStringList('searchHistory', _searchHistory);
    notifyListeners();
  }

  // Download tasks persistence
  DownloadTask? findDownloadTask(String taskId) {
    for (final t in _downloads) {
      if (t.id == taskId) return t;
    }
    return null;
  }

  DownloadTask? findCompletedDownload(ComicSource source, String chapterId) {
    for (final t in _downloads) {
      if (t.source == source &&
          t.chapterId == chapterId &&
          t.status == DownloadStatus.completed) {
        return t;
      }
    }
    return null;
  }

  Future<void> upsertDownloadTask(DownloadTask task) async {
    final idx = _downloads.indexWhere((e) => e.id == task.id);
    if (idx >= 0) {
      _downloads[idx] = task;
    } else {
      _downloads.insert(0, task);
    }
    notifyListeners();
    await _saveCollectionsToDisk();
  }

  Future<void> removeDownloadTask(String taskId) async {
    _downloads.removeWhere((e) => e.id == taskId);
    notifyListeners();
    await _saveCollectionsToDisk();
  }
}
