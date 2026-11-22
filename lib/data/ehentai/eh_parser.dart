import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../domain/models/comic_item.dart';
import '../../domain/models/comic_source.dart';
import 'eh_url.dart';

class EhParseException implements Exception {
  const EhParseException(this.message);
  final String message;

  @override
  String toString() => 'EhParseException: $message';
}

class EhPageResolution {
  const EhPageResolution({
    required this.imageUrl,
    this.skipHathKey,
    this.showKey,
    this.originImageUrl,
    this.is509 = false,
  });

  final String imageUrl;
  final String? skipHathKey;
  final String? showKey;
  final String? originImageUrl;
  final bool is509;
}

class EhLoginResult {
  const EhLoginResult({
    required this.success,
    this.username,
    this.errorMessage,
  });

  final bool success;
  final String? username;
  final String? errorMessage;
}

/// HTML and JSON parsers for E-Hentai / ExHentai pages matching `Ehviewer_CN_SXJ`.
class EhParser {
  static final RegExp _galleryUrlRegex = RegExp(
    r'https?://(?:exhentai\.org|e-hentai\.org|lofi\.e-hentai\.org)/(?:g|mpv)/(\d+)/([0-9a-f]{10})',
    caseSensitive: false,
  );

  static final RegExp _pageUrlRegex = RegExp(
    r'/s/([0-9a-f]{10})/(\d+)-(\d+)',
    caseSensitive: false,
  );

  static final RegExp _ratingPxRegex = RegExp(r'(-?\d+)px\s+(-?\d+)px');

  static void checkCommonErrors(String body) {
    if (body.isEmpty) {
      throw const EhParseException('响应为空（若使用 ExHentai 请检查 igneous Cookie 是否有效）');
    }
    if (body.contains('https://exhentai.org/img/kokomade.jpg')) {
      throw const EhParseException('ExHentai 当前节点/IP 暂不可访问 (kokomade)');
    }
    if (body.contains('Your IP address has been temporarily banned')) {
      throw const EhParseException('当前 IP 请求过于频繁，已被临时限制');
    }
  }

  static ComicListResult parseGalleryList(
    String html, {
    required bool isExHentai,
  }) {
    checkCommonErrors(html);

    if (html.contains('No hits found</p>') ||
        html.contains('No hits found') && !html.contains('class="itg')) {
      return const ComicListResult(items: [], total: 0, hasMore: false);
    }
    if (html.contains('You do not have any watched tags')) {
      return const ComicListResult(
        items: [],
        total: 0,
        hasMore: false,
        totalText: '尚未订阅任何标签',
      );
    }

    final doc = html_parser.parse(html);
    final totalText = doc.querySelector('.searchtext')?.text.trim() ?? '';

    String? nextCursor;
    String? prevCursor;
    final nextEl = doc.querySelector('#unext');
    final prevEl = doc.querySelector('#uprev');
    if (nextEl != null) {
      final href = nextEl.attributes['href'] ?? '';
      nextCursor = Uri.tryParse(href)?.queryParameters['next'];
    }
    if (prevEl != null) {
      final href = prevEl.attributes['href'] ?? '';
      prevCursor = Uri.tryParse(href)?.queryParameters['prev'];
    }

    final itg = doc.querySelector('.itg');
    if (itg == null) {
      return ComicListResult(
        items: const [],
        hasMore: false,
        totalText: totalText,
      );
    }

    final rows = itg.localName == 'table'
        ? itg.querySelectorAll('tbody > tr')
        : itg.children;

    final items = <ComicSummary>[];
    for (final row in rows) {
      final parsed = _parseGalleryRow(row, isExHentai: isExHentai);
      if (parsed != null) {
        items.add(parsed);
      }
    }

    return ComicListResult(
      items: items,
      total: items.length,
      hasMore: nextCursor != null && nextCursor.isNotEmpty,
      nextCursor: nextCursor,
      prevCursor: prevCursor,
      totalText: totalText,
    );
  }

  /// Parses `/favorites.php` HTML into gallery items plus the 10 cloud favorite categories (`favcat 0..9`).
  static CloudFavoritesResult parseFavoritesPage(
    String html, {
    required bool isExHentai,
  }) {
    checkCommonErrors(html);
    if (html.contains('This page requires you to log on.</p>')) {
      throw const EhParseException('需要先登录 E-Hentai 账号（Cookie 无效或已过期）');
    }

    final doc = html_parser.parse(html);
    final root = doc.querySelector('.ido') ?? doc.documentElement;
    final fps = (root?.querySelectorAll('.fp') ?? const <Element>[])
        .where((el) => !el.classes.contains('fps'))
        .toList();

    final folders = <CloudFavoriteFolder>[];
    for (var i = 0; i < fps.length && i < 10; i++) {
      final fp = fps[i];
      final children = fp.children;
      int? count;
      var name = '';
      if (children.isNotEmpty) {
        count = int.tryParse(children.first.text.trim());
      }
      if (children.length >= 3) {
        name = children[2].text.trim();
      } else if (children.length >= 2) {
        name = children.last.text.trim();
      }
      folders.add(
        CloudFavoriteFolder(
          id: '$i',
          name: name.isNotEmpty ? name : 'Favorites $i',
          count: count,
        ),
      );
    }

    final listResult = parseGalleryList(html, isExHentai: isExHentai);
    return CloudFavoritesResult(
      items: listResult.items,
      folders: folders,
      total: listResult.total,
      hasMore: listResult.hasMore,
      nextCursor: listResult.nextCursor,
      totalText: listResult.totalText,
    );
  }

  static ComicSummary? _parseGalleryRow(
    Element row, {
    required bool isExHentai,
  }) {
    final glName = row.querySelector('.glname');
    if (glName == null) return null;

    Element? linkEl = glName.querySelector('a');
    if (linkEl == null && glName.parent?.localName == 'a') {
      linkEl = glName.parent;
    }
    linkEl ??= row.querySelector('a[href*="/g/"]');
    if (linkEl == null) return null;

    final href = linkEl.attributes['href'] ?? '';
    final urlMatch = _galleryUrlRegex.firstMatch(href);
    if (urlMatch == null) return null;

    final gid = urlMatch.group(1)!;
    final token = urlMatch.group(2)!;

    // Title
    final title = (glName.querySelector('.glink')?.text ?? glName.text).trim();
    if (title.isEmpty) return null;

    // Category
    final category = (row.querySelector('.cn')?.text ??
            row.querySelector('.cs')?.text ??
            '')
        .trim();

    // Thumbnail
    var thumbUrl = '';
    final img = row.querySelector('.glthumb img') ??
        row.querySelector('.gl1e img') ??
        row.querySelector('.gl3t img') ??
        row.querySelector('img');
    if (img != null) {
      thumbUrl = (img.attributes['data-src'] ?? img.attributes['src'] ?? '').trim();
    }
    thumbUrl = EhUrl.getFixedThumbUrl(thumbUrl);

    // Posted time
    final posted = (row.querySelector('#posted_$gid')?.text ?? '').trim();

    // Rating
    double? rating;
    final ir = row.querySelector('.ir');
    if (ir != null) {
      final style = ir.attributes['style'] ?? '';
      final rMatch = _ratingPxRegex.firstMatch(style);
      if (rMatch != null) {
        final xPx = int.tryParse(rMatch.group(1)!)?.abs() ?? 0;
        final yPx = int.tryParse(rMatch.group(2)!)?.abs() ?? 0;
        rating = 5.0 - (xPx / 16.0) - (yPx >= 21 ? 0.5 : 0.0);
        if (rating < 0) rating = 0;
      }
    }

    // Uploader & page count
    var uploader = '';
    int? pageCount;
    final glHide = row.querySelector('.glhide');
    if (glHide != null && glHide.children.length >= 2) {
      uploader = glHide.children[0].text.trim();
      pageCount = _extractPageCount(glHide.children[1].text);
    } else {
      final gl3e = row.querySelector('.gl3e');
      if (gl3e != null && gl3e.children.length >= 5) {
        uploader = gl3e.children[3].text.trim();
        pageCount = _extractPageCount(gl3e.children[4].text);
      } else {
        final gl5t = row.querySelector('.gl5t');
        if (gl5t != null) {
          pageCount = _extractPageCount(gl5t.text);
        }
      }
    }
    pageCount ??= _extractPageCount(row.text);

    // Simple tags
    final tags = <String>[];
    for (final tagEl in row.querySelectorAll('.gt, .gtl')) {
      final t = (tagEl.attributes['title'] ?? '').trim();
      if (t.isNotEmpty) {
        tags.add(t);
      }
    }
    if (tags.isEmpty) {
      final tbody = glName.querySelector('tbody');
      if (tbody != null) {
        for (final tr in tbody.querySelectorAll('tr')) {
          final tds = tr.querySelectorAll('td');
          if (tds.length >= 2) {
            final ns = tds[0].text.replaceAll(':', '').trim();
            for (final child in tds[1].children) {
              final tagVal = child.text.split('|').first.trim();
              if (tagVal.isNotEmpty) {
                tags.add('$ns:$tagVal');
              }
            }
          }
        }
      }
    }

    return ComicSummary(
      id: gid,
      source: ComicSource.ehentai,
      token: token,
      title: title,
      subtitle: uploader,
      coverUrl: thumbUrl,
      category: category,
      author: uploader,
      rating: rating,
      pageCount: pageCount,
      posted: posted,
      tags: tags,
      isExHentai: isExHentai,
    );
  }

  static ComicDetail parseGalleryDetail(
    String html, {
    required String gid,
    required String token,
    required bool isExHentai,
  }) {
    checkCommonErrors(html);

    if (html.contains('This gallery is pining for the fjords.')) {
      throw const EhParseException('该画廊已被移除 (Expunged)');
    }
    if (html.contains('This gallery is unavailable')) {
      throw const EhParseException('该画廊当前不可用');
    }

    final doc = html_parser.parse(html);
    final title = (doc.querySelector('#gn')?.text ?? '').trim();
    if (title.isEmpty) {
      final errText = doc.querySelector('.d p')?.text.trim();
      if (errText != null && errText.isNotEmpty) {
        throw EhParseException(errText);
      }
      throw const EhParseException('无法解析画廊详情页面');
    }

    final titleJpn = (doc.querySelector('#gj')?.text ?? '').trim();
    final category = (doc.querySelector('#gdc .cn')?.text ??
            doc.querySelector('#gdc .cs')?.text ??
            doc.querySelector('#gdc')?.text ??
            '')
        .trim();
    final uploader = (doc.querySelector('#gdn')?.text ?? '').trim();

    // Cover URL from #gd1 style: url(...)
    var coverUrl = '';
    final gd1Inner = doc.querySelector('#gd1 > div');
    final gd1Style = gd1Inner?.attributes['style'] ?? '';
    final coverMatch = RegExp(r'url\(([^)]+)\)').firstMatch(gd1Style);
    if (coverMatch != null) {
      coverUrl = coverMatch.group(1)!.replaceAll('"', '').replaceAll("'", '').trim();
      coverUrl = EhUrl.getFixedThumbUrl(coverUrl);
    }

    // Properties table #gdd
    var posted = '';
    var language = '';
    var fileSize = '';
    var favoriteCount = '';
    int? pageCount;
    for (final tr in doc.querySelectorAll('#gdd table tr')) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 2) continue;
      final label = tds[0].text.trim().toLowerCase();
      final val = tds[1].text.trim();
      if (label.startsWith('posted')) {
        posted = val;
      } else if (label.startsWith('language')) {
        language = val;
      } else if (label.startsWith('file size')) {
        fileSize = val;
      } else if (label.startsWith('length')) {
        pageCount = _extractPageCount(val);
      } else if (label.startsWith('favorited')) {
        favoriteCount = val;
      }
    }

    // Rating
    final ratingCount =
        int.tryParse(doc.querySelector('#rating_count')?.text.trim() ?? '0') ?? 0;
    final ratingLabel = doc.querySelector('#rating_label')?.text.trim() ?? '';
    double? rating;
    if (!ratingLabel.contains('Not Yet Rated')) {
      final numMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(ratingLabel);
      if (numMatch != null) {
        rating = double.tryParse(numMatch.group(1)!);
      }
    }

    // Favorite status
    final gdfText = doc.querySelector('#gdf')?.text.trim() ?? '';
    final isFavorited = gdfText.isNotEmpty && gdfText != 'Add to Favorites';

    // Grouped tags (#taglist)
    final tagGroups = <String, List<String>>{};
    final flatTags = <String>[];
    for (final tr in doc.querySelectorAll('#taglist table tr')) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 2) continue;
      final ns = tds[0].text.replaceAll(':', '').trim();
      if (ns.isEmpty) continue;
      final tags = <String>[];
      for (final child in tds[1].children) {
        final rawTag = child.text.split('|').first.trim();
        if (rawTag.isNotEmpty) {
          tags.add(rawTag);
          flatTags.add('$ns:$rawTag');
        }
      }
      if (tags.isNotEmpty) {
        tagGroups[ns] = tags;
      }
    }

    // Comments (#cdiv .c1)
    final comments = <ComicComment>[];
    for (final c1 in doc.querySelectorAll('#cdiv .c1')) {
      final prevName = c1.previousElementSibling?.attributes['name'] ?? '';
      final cid = prevName.startsWith('c') ? prevName.substring(1) : '';
      final author = (c1.querySelector('.c3 a')?.text ?? '匿名').trim();
      final c3Text = c1.querySelector('.c3')?.text.trim() ?? '';
      final dateMatch = RegExp(r'Posted on (.+?) by:').firstMatch(c3Text);
      final postedAt = dateMatch?.group(1)?.trim() ?? c3Text;
      final score = (c1.querySelector('.c5 span')?.text ?? '').trim();
      final c6 = c1.querySelector('.c6');
      final content = (c6?.innerHtml ?? '')
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (content.isNotEmpty) {
        comments.add(
          ComicComment(
            id: cid,
            author: author,
            content: content,
            postedAt: postedAt,
            score: score,
          ),
        );
      }
    }

    // Total preview pages from .ptt
    var totalPreviewPages = 1;
    final pttCells = doc.querySelectorAll('.ptt td');
    if (pttCells.length >= 2) {
      final candidate = int.tryParse(
        pttCells[pttCells.length - 2].text.replaceAll(',', '').trim(),
      );
      if (candidate != null && candidate > 0) {
        totalPreviewPages = candidate;
      }
    }

    // Preview grid
    final previews = parsePreviewsFromHtml(html);

    final summary = ComicSummary(
      id: gid,
      source: ComicSource.ehentai,
      token: token,
      title: title,
      subtitle: titleJpn.isNotEmpty ? titleJpn : uploader,
      coverUrl: coverUrl,
      category: category,
      author: uploader,
      rating: rating,
      pageCount: pageCount ?? previews.length,
      posted: posted,
      tags: flatTags,
      isExHentai: isExHentai,
      isFavorite: isFavorited,
    );

    return ComicDetail(
      summary: summary,
      titleJpn: titleJpn,
      uploader: uploader,
      language: language,
      fileSize: fileSize,
      posted: posted,
      favoriteCount: favoriteCount,
      ratingCount: ratingCount,
      isFavorited: isFavorited,
      favoriteFolderName: isFavorited ? gdfText : '',
      tagGroups: tagGroups,
      previews: previews,
      totalPreviewPages: totalPreviewPages,
      comments: comments,
    );
  }

  /// Parses preview thumbnail grid items from gallery detail HTML (all EH preview layouts).
  static List<EhPreviewItem> parsePreviewsFromHtml(String html) {
    final doc = html_parser.parse(html);
    final gdt = doc.querySelector('#gdt') ?? doc.body;
    if (gdt == null) return const [];

    final previews = <EhPreviewItem>[];
    final seenPages = <int>{};

    for (final anchor in gdt.querySelectorAll('a[href*="/s/"]')) {
      final href = anchor.attributes['href'] ?? '';
      final urlMatch = _pageUrlRegex.firstMatch(href);
      if (urlMatch == null) continue;

      final pToken = urlMatch.group(1)!;
      final pageNum = int.tryParse(urlMatch.group(3)!) ?? 0;
      if (pageNum <= 0 || seenPages.contains(pageNum)) continue;

      var thumbUrl = '';
      var isSprite = false;
      var xOffset = 0;
      var width = 0;
      var height = 0;

      final innerImg = anchor.querySelector('img');
      if (innerImg != null) {
        thumbUrl = (innerImg.attributes['data-src'] ??
                innerImg.attributes['src'] ??
                '')
            .trim();
      }

      if (thumbUrl.isEmpty) {
        // Modern sprite/background div inside anchor or sibling
        final styledDiv = anchor.querySelector('div[style*="url("]') ??
            (anchor.attributes['style']?.contains('url(') == true ? anchor : null);
        if (styledDiv != null) {
          final style = styledDiv.attributes['style'] ?? '';
          final bgMatch = RegExp(r'url\(([^)]+)\)').firstMatch(style);
          if (bgMatch != null) {
            thumbUrl = bgMatch.group(1)!.replaceAll('"', '').replaceAll("'", '').trim();
          }
          final wMatch = RegExp(r'width\s*:\s*(\d+)px').firstMatch(style);
          final hMatch = RegExp(r'height\s*:\s*(\d+)px').firstMatch(style);
          width = int.tryParse(wMatch?.group(1) ?? '') ?? 0;
          height = int.tryParse(hMatch?.group(1) ?? '') ?? 0;
          final xMatch = RegExp(r'-\s*(\d+)px\s+0(?:px)?').firstMatch(style);
          if (xMatch != null) {
            isSprite = true;
            xOffset = int.tryParse(xMatch.group(1)!) ?? 0;
          }
        }
      }

      thumbUrl = EhUrl.getFixedThumbUrl(thumbUrl);
      seenPages.add(pageNum);
      previews.add(
        EhPreviewItem(
          pageNumber: pageNum,
          pageToken: pToken,
          pageUrl: href,
          thumbUrl: thumbUrl,
          isSprite: isSprite,
          xOffset: xOffset,
          width: width,
          height: height,
        ),
      );
    }

    previews.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return previews;
  }

  /// Parses an `/s/{pToken}/{gid}-{page}` HTML page.
  static EhPageResolution parseGalleryPage(String html) {
    checkCommonErrors(html);

    final imgMatch = RegExp(
      r'<img[^>]*id="img"[^>]*src="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html) ??
        RegExp(
          r'<img[^>]*src="([^"]+)"[^>]*style="',
          caseSensitive: false,
        ).firstMatch(html);

    final imageUrl = _unescapeHtml(imgMatch?.group(1) ?? '');
    if (imageUrl.isEmpty) {
      throw const EhParseException('无法解析图片地址');
    }

    final nlMatch = RegExp(r"return nl\('([^']+)'\)").firstMatch(html);
    final showKeyMatch = RegExp(r'var\s+showkey\s*=\s*"([0-9a-z]+)"').firstMatch(html);
    final originMatch = RegExp(r'<a[^>]*href="([^"]*fullimg[^"]*)"').firstMatch(html);

    final is509 = imageUrl.endsWith('/509.gif') || imageUrl.endsWith('/509s.gif');
    return EhPageResolution(
      imageUrl: imageUrl,
      skipHathKey: nlMatch?.group(1),
      showKey: showKeyMatch?.group(1),
      originImageUrl: originMatch != null ? _unescapeHtml(originMatch.group(1)!) : null,
      is509: is509,
    );
  }

  /// Parses `api.php` `showpage` JSON response.
  static EhPageResolution parseShowPageApi(Map<String, dynamic> json) {
    final err = json['error']?.toString();
    if (err != null && err.isNotEmpty) {
      throw EhParseException(err);
    }
    final i3 = json['i3']?.toString() ?? '';
    final i6 = json['i6']?.toString() ?? '';
    final i7 = json['i7']?.toString() ?? '';

    final imgMatch = RegExp(r'<img[^>]*src="([^"]+)"').firstMatch(i3);
    final imageUrl = _unescapeHtml(imgMatch?.group(1) ?? '');
    if (imageUrl.isEmpty) {
      throw const EhParseException('showpage API 未返回图片 URL');
    }

    final nlMatch = RegExp(r"return nl\('([^']+)'\)").firstMatch(i6);
    final originMatch =
        RegExp(r'<a[^>]*href="([^"]*fullimg[^"]*)"').firstMatch(i7.isNotEmpty ? i7 : i6);

    final is509 = imageUrl.endsWith('/509.gif') || imageUrl.endsWith('/509s.gif');
    return EhPageResolution(
      imageUrl: imageUrl,
      skipHathKey: nlMatch?.group(1),
      originImageUrl: originMatch != null ? _unescapeHtml(originMatch.group(1)!) : null,
      is509: is509,
    );
  }

  static EhLoginResult parseSignInHtml(String html) {
    final okMatch = RegExp(
      r'(?:<p>\s*)?You are now logged in as:\s*([^<\r\n]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (okMatch != null) {
      return EhLoginResult(success: true, username: okMatch.group(1)?.trim());
    }

    final errMatch = RegExp(
      r'(?:<h4>The error returned was:</h4>\s*<p>(.+?)</p>)|(?:<div class="errorwrap">.*?<p>(.+?)</p>)|(?:<span class="postcolor">(.+?)</span>)',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    final rawMsg =
        errMatch?.group(1) ?? errMatch?.group(2) ?? errMatch?.group(3) ?? '';
    final msg = _unescapeHtml(
      rawMsg.replaceAll(RegExp(r'<[^>]*>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();

    final lower = html.toLowerCase();
    final hasCaptcha = lower.contains('g-recaptcha') ||
        lower.contains('recaptcha/api.js') ||
        lower.contains('cf-turnstile') ||
        lower.contains('h-captcha') ||
        msg.toLowerCase().contains('captcha');
    if (hasCaptcha) {
      return const EhLoginResult(
        success: false,
        errorMessage: 'E-Hentai 论坛登录触发了人机验证（CAPTCHA），请改用「配置 Cookie」方式登录',
      );
    }

    return EhLoginResult(
      success: false,
      errorMessage: msg.isNotEmpty ? msg : '登录失败，请检查账号密码或改用 Cookie 登录',
    );
  }

  static int? _extractPageCount(String text) {
    final match = RegExp(r'(\d+)\s*page', caseSensitive: false).firstMatch(text);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static String _unescapeHtml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  static Map<String, dynamic> decodeJsonObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return Map<String, dynamic>.from(jsonDecode(data.toString()) as Map);
  }
}
