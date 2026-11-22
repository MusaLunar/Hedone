import 'package:flutter_test/flutter_test.dart';
import 'package:hedone/core/utils/jm_id_extractor.dart';

void main() {
  group('JmIdExtractor', () {
    test('extracts JM prefixes, URLs, and standalone numbers in order', () {
      const sample = '''
      今天推荐 JM123456，还有 jm 422866 也不错；
      群友发了个 车牌号：512345 和链接 https://18comic.vip/album/654321/foo ，
      以及备用 /photo/765432 与纯数字 876543。
      ''';

      final items = JmIdExtractor.extract(sample);
      expect(
        items.map((e) => '${e.kind.name}:${e.id}').toList(),
        [
          'explicit:123456',
          'explicit:422866',
          'explicit:512345',
          'url:654321',
          'url:765432',
          'numeric:876543',
        ],
      );
    });

    test('deduplicates preserving first occurrence and prefers url/explicit on overlap', () {
      const sample = '''
      第一名 车号 422866，第二名 https://18comic.org/album/334455/bar，
      重复提及 JM422866、334455 以及纯数字 998877。
      ''';

      expect(JmIdExtractor.extractIds(sample), ['422866', '334455', '998877']);
      final items = JmIdExtractor.extract(sample);
      expect(items[0].kind, JmIdMatchKind.explicit);
      expect(items[1].kind, JmIdMatchKind.url);
      expect(items[2].kind, JmIdMatchKind.numeric);
    });

    test('ignores E-Hentai URLs, dates, phone numbers, and short numbers', () {
      const sample = '''
      日期 2025-11-22 和 2025/11/22 与 20251122 不该被识别；
      手机号 13812345678、短编号 1234 和 2025 也不算；
      EH 画廊 https://e-hentai.org/g/2987654/a1b2c3d4e5/ 与 https://exhentai.org/g/3123456/ff00aa11bb/ 应排除；
      真正想看的是 JM556677 和禁漫天堂 667788。
      ''';

      expect(JmIdExtractor.extractIds(sample), ['556677', '667788']);
    });
  });
}
