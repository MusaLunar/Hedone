import 'package:flutter/material.dart';

class EhCategorySpec {
  const EhCategorySpec({
    required this.bit,
    required this.key,
    required this.label,
    required this.color,
  });

  final int bit;
  final String key;
  final String label;
  final Color color;
}

class EhToplistBoard {
  const EhToplistBoard({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

/// URL builder, category bitmask definitions, and thumbnail normalizer for E-Hentai / ExHentai.
class EhUrl {
  static const String hostE = 'https://e-hentai.org';
  static const String hostEx = 'https://exhentai.org';
  static const String hostForums = 'https://forums.e-hentai.org';
  static const String thumbPrefix = 'https://ehgt.org/';

  static const int allCategoryMask = 0x3ff;

  static const List<EhCategorySpec> categories = [
    EhCategorySpec(bit: 0x2, key: 'Doujinshi', label: '同人志', color: Color(0xFFF44336)),
    EhCategorySpec(bit: 0x4, key: 'Manga', label: '漫画', color: Color(0xFFFF9800)),
    EhCategorySpec(bit: 0x8, key: 'Artist CG', label: '画师CG', color: Color(0xFFFBC02D)),
    EhCategorySpec(bit: 0x10, key: 'Game CG', label: '游戏CG', color: Color(0xFF4CAF50)),
    EhCategorySpec(bit: 0x200, key: 'Western', label: '西方', color: Color(0xFF8BC34A)),
    EhCategorySpec(bit: 0x100, key: 'Non-H', label: '非H', color: Color(0xFF2196F3)),
    EhCategorySpec(bit: 0x20, key: 'Image Set', label: '图集', color: Color(0xFF3F51B5)),
    EhCategorySpec(bit: 0x40, key: 'Cosplay', label: 'Cosplay', color: Color(0xFF9C27B0)),
    EhCategorySpec(bit: 0x80, key: 'Asian Porn', label: '亚洲', color: Color(0xFFE91E63)),
    EhCategorySpec(bit: 0x1, key: 'Misc', label: '杂项', color: Color(0xFF9E9E9E)),
  ];

  static const List<EhToplistBoard> toplistBoards = [
    EhToplistBoard(id: '15', label: '昨日热门'),
    EhToplistBoard(id: '13', label: '近一月'),
    EhToplistBoard(id: '12', label: '近一年'),
    EhToplistBoard(id: '11', label: '总排行榜'),
  ];

  static String host(bool useExHentai) => useExHentai ? hostEx : hostE;

  static String apiUrl(bool useExHentai) => '${host(useExHentai)}/api.php';

  /// `f_cats` uses an inverted 10-bit mask: set bits represent EXCLUDED categories.
  static int encodeExcludedCats(int enabledMask) => (~enabledMask) & allCategoryMask;

  static String buildGalleryListUrl({
    required bool useExHentai,
    String path = '/',
    int enabledCategoryMask = allCategoryMask,
    String searchQuery = '',
    String? nextCursor,
    String? prevCursor,
    bool advancedSearch = false,
    int? minRating,
    int? minPages,
    int? maxPages,
    bool includeExpunged = false,
    bool onlyTorrents = false,
    String? favCat,
    int? page,
  }) {
    final base = host(useExHentai);
    final query = <String, String>{};

    if (favCat != null && favCat.isNotEmpty) {
      query['favcat'] = favCat;
    }

    final excludedCats = encodeExcludedCats(enabledCategoryMask);
    if (excludedCats != 0 || path == '/') {
      query['f_cats'] = excludedCats.toString();
    }

    final trimmed = searchQuery.trim();
    if (trimmed.isNotEmpty) {
      query['f_search'] = trimmed;
    }

    if (advancedSearch) {
      query['advsearch'] = '1';
      query['f_sname'] = 'on';
      query['f_stags'] = 'on';
      if (minRating != null && minRating >= 2 && minRating <= 5) {
        query['f_sr'] = 'on';
        query['f_srdd'] = minRating.toString();
      }
      if ((minPages != null && minPages > 0) ||
          (maxPages != null && maxPages > 0)) {
        query['f_sp'] = 'on';
        if (minPages != null && minPages > 0) {
          query['f_spf'] = minPages.toString();
        }
        if (maxPages != null && maxPages > 0) {
          query['f_spt'] = maxPages.toString();
        }
      }
      if (includeExpunged) query['f_sh'] = 'on';
      if (onlyTorrents) query['f_sto'] = 'on';
    }

    if (nextCursor != null && nextCursor.isNotEmpty) {
      query['next'] = nextCursor;
    } else if (prevCursor != null && prevCursor.isNotEmpty) {
      query['prev'] = prevCursor;
    } else if (page != null && page > 0) {
      query['page'] = page.toString();
    }

    final uri = Uri.parse('$base$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    return uri.toString();
  }

  static String toplistUrl({
    required String boardId,
    int page = 0,
  }) {
    final query = <String, String>{'tl': boardId};
    if (page > 0) query['p'] = page.toString();
    return Uri.parse('$hostE/toplist.php')
        .replace(queryParameters: query)
        .toString();
  }

  static String galleryDetailUrl({
    required bool useExHentai,
    required String gid,
    required String token,
    int previewPage = 0,
    bool showAllComments = false,
  }) {
    final query = <String, String>{};
    if (previewPage > 0) query['p'] = previewPage.toString();
    if (showAllComments) query['hc'] = '1';
    return Uri.parse('${host(useExHentai)}/g/$gid/$token/')
        .replace(queryParameters: query.isEmpty ? null : query)
        .toString();
  }

  static String galleryPageUrl({
    required bool useExHentai,
    required String pToken,
    required String gid,
    required int pageNumber,
    String? nlKey,
  }) {
    final base = '${host(useExHentai)}/s/$pToken/$gid-$pageNumber';
    if (nlKey != null && nlKey.isNotEmpty) {
      return '$base?nl=${Uri.encodeQueryComponent(nlKey)}';
    }
    return base;
  }

  /// Normalizes E-Hentai / ExHentai preview thumbnail URLs to `https://ehgt.org/...`.
  static String getFixedThumbUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('https://exhentai.org/t/')) {
      return trimmed.replaceFirst('https://exhentai.org/t/', thumbPrefix);
    }
    if (trimmed.startsWith('https://e-hentai.org/t/')) {
      return trimmed.replaceFirst('https://e-hentai.org/t/', thumbPrefix);
    }
    final match = RegExp(
      r'^https?://[^/]+/(?:t/)?([0-9a-f]{2}/[0-9a-f]{2}/.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null) {
      return '$thumbPrefix${match.group(1)}';
    }
    return trimmed;
  }

  static Color categoryColor(String category) {
    final lower = category.trim().toLowerCase();
    for (final spec in categories) {
      if (spec.key.toLowerCase() == lower) {
        return spec.color;
      }
    }
    return const Color(0xFF9E9E9E);
  }
}
