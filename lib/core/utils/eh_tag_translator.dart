import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TagSuggestion {
  const TagSuggestion({
    required this.fullTag,
    required this.chinese,
    required this.namespaceZh,
  });

  final String fullTag;
  final String chinese;
  final String namespaceZh;
}

/// Bilingual E-Hentai tag translator with built-in common Chinese dictionary
/// plus support for downloading/loading the Mapaler EhTagTranslation binary DB.
class EhTagTranslator extends ChangeNotifier {
  EhTagTranslator();

  static const String sha1Url =
      'https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN.sha1';
  static const String dataUrl =
      'https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN';

  static const Map<String, String> _namespaceToPrefix = {
    'rows': 'n:',
    'artist': 'a:',
    'cosplayer': 'cos:',
    'character': 'c:',
    'female': 'f:',
    'group': 'g:',
    'language': 'l:',
    'location': 'loc:',
    'male': 'm:',
    'misc': '',
    'mixed': 'x:',
    'other': 'o:',
    'parody': 'p:',
    'reclass': 'r:',
    'temp': 't:',
  };

  static const Map<String, String> _prefixToNamespace = {
    'n:': 'rows',
    'a:': 'artist',
    'cos:': 'cosplayer',
    'c:': 'character',
    'f:': 'female',
    'g:': 'group',
    'l:': 'language',
    'loc:': 'location',
    'm:': 'male',
    '': 'misc',
    'x:': 'mixed',
    'o:': 'other',
    'p:': 'parody',
    'r:': 'reclass',
    't:': 'temp',
  };

  static const Map<String, String> _builtin = {
    // Namespaces
    'n:rows': '分类',
    'n:reclass': '重新分类',
    'n:language': '语言',
    'n:parody': '原作',
    'n:character': '角色',
    'n:group': '社团',
    'n:artist': '画师',
    'n:male': '男性',
    'n:female': '女性',
    'n:mixed': '混合',
    'n:other': '其他',
    'n:cosplayer': 'Coser',
    'n:location': '场景',
    'n:misc': '杂项',
    'n:temp': '临时',

    // Languages
    'l:chinese': '中文',
    'l:translated': '翻译',
    'l:english': '英语',
    'l:japanese': '日语',
    'l:korean': '韩语',
    'l:rewrite': '改写',
    'l:textless': '无字',
    'l:speechless': '无台词',
    'l:mosaic': '马赛克',

    // Reclass / Other
    'r:doujinshi': '同人志',
    'r:manga': '漫画',
    'r:artistcg': '画师CG',
    'r:gamecg': '游戏CG',
    'r:imageset': '图集',
    'r:cosplay': 'Cosplay',
    'r:non-h': '非H',
    'r:western': '西方',
    'o:full color': '全彩',
    'o:uncensored': '无修正',
    'o:mosaic censorship': '马赛克修正',
    'o:multi-work series': '多作品系列',
    'o:story arc': '剧情篇',
    'o:anthology': '合集',
    'o:artbook': '画集',
    'o:webtoon': '条漫',
    'o:tankoubon': '单行本',
    'o:3d': '3D',
    'o:ai generated': 'AI生成',
    'o:rough translation': '机翻/粗翻',
    'o:variant set': '差分图集',
    'o:themeless': '无主题',
    'o:sample': '试阅',
    'o:incomplete': '未完结',

    // Popular Parodies
    'p:original': '原创',
    'p:blue archive': '蔚蓝档案',
    'p:genshin impact': '原神',
    'p:honkai star rail': '崩坏：星穹铁道',
    'p:fate grand order': 'Fate/Grand Order',
    'p:azur lane': '碧蓝航线',
    'p:arknights': '明日方舟',
    'p:touhou project': '东方Project',
    'p:idolmaster': '偶像大师',
    'p:kantai collection': '舰队Collection',
    'p:hololive': 'Hololive',
    'p:zenless zone zero': '绝区零',
    'p:pokemon': '宝可梦',
    'p:naruto': '火影忍者',
    'p:one piece': '海贼王',
    'p:bleach': '死神',
    'p:neon genesis evangelion': '新世纪福音战士',

    // Common Female tags
    'f:sole female': '单女主',
    'f:big breasts': '巨乳',
    'f:medium breasts': '中等胸',
    'f:small breasts': '贫乳',
    'f:stockings': '丝袜',
    'f:pantyhose': '连裤袜',
    'f:thigh high boots': '过膝靴',
    'f:schoolgirl uniform': 'JK制服',
    'f:swimsuit': '泳装',
    'f:bikini': '比基尼',
    'f:maid': '女仆',
    'f:bunny girl': '兔女郎',
    'f:kemonomimi': '兽耳',
    'f:catgirl': '猫娘',
    'f:fox girl': '狐娘',
    'f:elf': '精灵',
    'f:glasses': '眼镜',
    'f:twintails': '双马尾',
    'f:ponytail': '马尾',
    'f:nakadashi': '中出',
    'f:blowjob': '口交',
    'f:paizuri': '乳交',
    'f:ahegao': '阿黑颜',
    'f:lingerie': '内衣',
    'f:kimono': '和服',
    'f:nurse': '护士',
    'f:teacher': '女教师',
    'f:milf': '熟女/人妻',
    'f:yuri': '百合',
    'f:netorare': 'NTR',
    'f:bondage': '捆绑',
    'f:collar': '项圈',
    'f:halo': '光环',
    'f:horns': '角',
    'f:wings': '翅膀',
    'f:tail': '尾巴',
    'f:dark skin': '黑皮',
    'f:sweating': '出汗',
    'f:heart pupils': '爱心眼',
    'f:kissing': '接吻',
    'f:handjob': '手交',
    'f:footjob': '足交',
    'f:femdom': '女攻',
    'f:futanari': '扶她',
    'f:pregnant': '怀孕',
    'f:lactation': '喷乳',

    // Common Male tags
    'm:sole male': '单男主',
    'm:males only': '纯爱男性/耽美',
    'm:crossdressing': '女装',
    'm:tomgirl': '伪娘',
    'm:shotacon': '正太',
    'm:dilf': '大叔',
    'm:muscle': '肌肉',
    'm:glasses': '眼镜',
    'm:dark skin': '黑皮',
    'm:yaoi': 'Yaoi',
    'm:anal': '肛交',
    'm:condom': '避孕套',
    'm:first person perspective': '第一人称视角',

    // Mixed tags
    'x:incest': '乱伦',
    'x:ffm threesome': '双飞3P',
    'x:mmf threesome': '两男一女3P',
    'x:group': '群交',
    'x:sister': '姐妹',
    'x:brother': '兄弟',
    'x:vanilla': '纯爱',
  };

  final Map<String, String> _remoteMap = {};
  bool _hasDatabase = false;
  bool _isUpdating = false;
  String? _lastError;

  bool get hasDatabase => _hasDatabase;
  bool get isUpdating => _isUpdating;
  int get entryCount => _remoteMap.isNotEmpty ? _remoteMap.length : _builtin.length;
  String? get lastError => _lastError;

  Future<void> initFromDisk() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dataFile = File(p.join(dir.path, 'tag-translations-zh-rCN'));
      if (await dataFile.exists()) {
        final bytes = await dataFile.readAsBytes();
        final parsed = parseBinaryDatabase(bytes);
        if (parsed.isNotEmpty) {
          _remoteMap
            ..clear()
            ..addAll(parsed);
          _hasDatabase = true;
          notifyListeners();
        }
      }
    } catch (_) {
      // Fall back silently to built-in dictionary.
    }
  }

  /// Parses the Mapaler/EhViewer binary database format into `prefix+tag -> chinese`.
  static Map<String, String> parseBinaryDatabase(Uint8List bytes) {
    if (bytes.length < 4) return const {};
    final totalBytes = ByteData.sublistView(bytes, 0, 4).getInt32(0, Endian.big);
    if (totalBytes <= 0 || 4 + totalBytes > bytes.length) {
      return const {};
    }
    final content = utf8.decode(bytes.sublist(4, 4 + totalBytes), allowMalformed: true);
    final result = <String, String>{};
    for (final line in content.split('\n')) {
      if (line.isEmpty) continue;
      final crIndex = line.indexOf('\r');
      if (crIndex <= 0 || crIndex + 1 >= line.length) continue;
      final key = line.substring(0, crIndex);
      final b64 = line.substring(crIndex + 1).trim();
      if (b64.isEmpty) continue;
      try {
        final decoded = utf8.decode(base64Decode(b64));
        result[key] = decoded;
      } catch (_) {
        // Skip malformed entry.
      }
    }
    return result;
  }

  Future<bool> downloadAndUpdate(Dio dio) async {
    if (_isUpdating) return false;
    _isUpdating = true;
    _lastError = null;
    notifyListeners();

    try {
      final dir = await getApplicationSupportDirectory();
      final shaResp = await dio.get<List<int>>(
        sha1Url,
        options: Options(responseType: ResponseType.bytes),
      );
      final remoteShaBytes = Uint8List.fromList(shaResp.data ?? const []);
      final dataResp = await dio.get<List<int>>(
        dataUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final dataBytes = Uint8List.fromList(dataResp.data ?? const []);

      if (remoteShaBytes.length >= 20) {
        final actualDigest = sha1.convert(dataBytes).bytes;
        final matches = listEquals(actualDigest, remoteShaBytes.sublist(0, 20));
        if (!matches) {
          throw const FormatException('标签数据库 SHA-1 校验失败');
        }
      }

      final parsed = await compute(parseBinaryDatabase, dataBytes);
      if (parsed.isEmpty) {
        throw const FormatException('标签数据库解析为空');
      }

      final dataFile = File(p.join(dir.path, 'tag-translations-zh-rCN'));
      final shaFile = File(p.join(dir.path, 'tag-translations-zh-rCN.sha1'));
      await dataFile.writeAsBytes(dataBytes, flush: true);
      await shaFile.writeAsBytes(remoteShaBytes, flush: true);

      _remoteMap
        ..clear()
        ..addAll(parsed);
      _hasDatabase = true;
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  String translateNamespace(String namespace) {
    final ns = namespace.trim().toLowerCase();
    final key = 'n:$ns';
    return _remoteMap[key] ?? _builtin[key] ?? namespace;
  }

  String? translateTag(String namespace, String tag) {
    final ns = namespace.trim().toLowerCase();
    final prefix = _namespaceToPrefix[ns] ?? '$ns:';
    final cleanTag = tag.split('|').first.trim().toLowerCase();
    final key = '$prefix$cleanTag';
    final hit = _remoteMap[key] ?? _builtin[key];
    if (hit != null) return hit;

    // Fallback: try raw `ns:tag` or `misc` if prefix unknown.
    return _remoteMap['$ns:$cleanTag'] ?? _builtin['$ns:$cleanTag'];
  }

  String translateFullTag(String rawTag) {
    final idx = rawTag.indexOf(':');
    if (idx <= 0) {
      return _remoteMap[rawTag.toLowerCase()] ??
          _builtin[rawTag.toLowerCase()] ??
          rawTag;
    }
    final ns = rawTag.substring(0, idx);
    final body = rawTag.substring(idx + 1);
    return translateTag(ns, body) ?? body;
  }

  /// Formats a tag for display, e.g. `巨乳 (big breasts)` or just `big breasts`.
  String formatTagDisplay(String namespace, String tag, {bool enabled = true}) {
    final cleanTag = tag.split('|').first.trim();
    if (!enabled) return cleanTag;
    final zh = translateTag(namespace, cleanTag);
    if (zh == null || zh.isEmpty) return cleanTag;
    return '$zh ($cleanTag)';
  }

  /// Returns bilingual autocomplete suggestions matching English or Chinese.
  List<TagSuggestion> suggest(String query, {int limit = 30}) {
    final kw = query.trim().toLowerCase();
    if (kw.isEmpty) return const [];

    final source = _remoteMap.isNotEmpty ? _remoteMap : _builtin;
    final results = <TagSuggestion>[];

    for (final entry in source.entries) {
      final key = entry.key;
      if (key.startsWith('n:')) continue;
      final zh = entry.value;

      var fullTag = key;
      var ns = 'misc';
      for (final prefixEntry in _prefixToNamespace.entries) {
        final pfx = prefixEntry.key;
        if (pfx.isNotEmpty && key.startsWith(pfx)) {
          ns = prefixEntry.value;
          fullTag = '$ns:${key.substring(pfx.length)}';
          break;
        }
      }

      if (fullTag.contains(kw) || zh.toLowerCase().contains(kw)) {
        final quoted = fullTag.contains(' ')
            ? '$ns:"${fullTag.substring(ns.length + 1)}"'
            : fullTag;
        results.add(
          TagSuggestion(
            fullTag: quoted,
            chinese: zh,
            namespaceZh: translateNamespace(ns),
          ),
        );
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}
