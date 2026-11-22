import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:hedone/core/network/app_http_client.dart';
import 'package:hedone/core/storage/local_store.dart';
import 'package:hedone/core/utils/eh_tag_translator.dart';
import 'package:hedone/core/utils/jm_image_descrambler.dart';
import 'package:hedone/data/ehentai/eh_api_service.dart';
import 'package:hedone/data/ehentai/eh_parser.dart';
import 'package:hedone/data/ehentai/eh_url.dart';
import 'package:hedone/data/jmcomic/jm_api_service.dart';
import 'package:hedone/data/jmcomic/jm_crypto.dart';
import 'package:hedone/data/jmcomic/jm_repository.dart';
import 'package:image/image.dart' as img;

void main() {
  group('JMComic3 Crypto & Host Discovery', () {
    test('decryptHostTxt decrypts real JMComic3 backupHostCode', () {
      final decoded = JmCrypto.decryptHostTxt(JmApiService.backupHostCode);
      expect(decoded['Server'], isA<List>());
      expect(decoded['Server'], contains('www.cdnaspa.vip'));
      expect(decoded['jm3_Server'], isA<List>());
    });

    test('decryptApiPayload decrypts primary and secondary secrets with timestamp', () {
      const ts = 1795276590;
      const sampleObj = {'id': '1216570', 'scramble_id': 220980};
      final plainJson = jsonEncode(sampleObj);

      for (final secret in [
        JmCrypto.primarySecret,
        JmCrypto.secondarySecret,
      ]) {
        final keyHex = md5.convert(utf8.encode('$ts$secret')).toString();
        final encrypter = enc.Encrypter(
          enc.AES(enc.Key.fromUtf8(keyHex), mode: enc.AESMode.ecb, padding: 'PKCS7'),
        );
        final encrypted = encrypter.encrypt(plainJson).base64;
        final result = JmCrypto.decryptApiPayload(encrypted, ts);
        expect(result, equals(sampleObj));
      }

      final headers = JmCrypto.buildHeaders(ts, jwtToken: 'jwt123', avsCookie: 'avs456');
      expect(headers['Tokenparam'], '$ts,2.1.9');
      expect(headers['Token'], md5.convert(utf8.encode('${ts}185Hcomic3PAPP7R')).toString());
      expect(headers['Authorization'], 'Bearer jwt123');
      expect(headers['Cookie'], 'AVS=avs456');
    });
  });

  group('JMComic3 Image Descrambler', () {
    test('calculateSliceCount matches JMComic3 Function.js across all aid ranges', () {
      // Below scramble_id -> 0
      expect(
        JmImageDescrambler.calculateSliceCount(
          '220979',
          'https://cdn/media/photos/220979/00001.webp',
          scrambleId: 220980,
        ),
        0,
      );

      // GIF -> 0
      expect(
        JmImageDescrambler.calculateSliceCount(
          '500000',
          'https://cdn/media/photos/500000/00001.gif?t=123',
        ),
        0,
      );

      // aid < 268850 -> always 10
      expect(
        JmImageDescrambler.calculateSliceCount(
          '250000',
          'https://cdn/media/photos/250000/00001.webp',
        ),
        10,
      );

      // 268850 <= aid <= 421925 -> (lastCharCode % 10) * 2 + 2
      const aidMid = '300000';
      const pageMid = '00005';
      final md5Mid = md5.convert(utf8.encode('$aidMid$pageMid')).toString();
      final expectedMid = (md5Mid.codeUnitAt(md5Mid.length - 1) % 10) * 2 + 2;
      expect(
        JmImageDescrambler.calculateSliceCount(
          aidMid,
          'https://cdn/media/photos/$aidMid/$pageMid.webp?t=999',
        ),
        expectedMid,
      );

      // aid >= 421926 -> (lastCharCode % 8) * 2 + 2
      const aidNew = '1216570';
      const pageNew = '00001';
      final md5New = md5.convert(utf8.encode('$aidNew$pageNew')).toString();
      final expectedNew = (md5New.codeUnitAt(md5New.length - 1) % 8) * 2 + 2;
      expect(
        JmImageDescrambler.calculateSliceCount(
          aidNew,
          'https://cdn-msp.jmapiproxy3.cc/media/photos/$aidNew/$pageNew.webp?t=1795276590',
        ),
        expectedNew,
      );
    });

    test('descrambleBytesSync restores scrambled slices including uneven remainder', () {
      const w = 12;
      const h = 107; // 107 % 6 == 5 remainder
      const numSlices = 6;

      // Build original unscrambled image where row y has unique RGB signature (y, 255-y, 128)
      final original = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          original.setPixelRgb(x, y, y, 255 - y, 128);
        }
      }

      // Forward-scramble using inverse of Function.js slice mapping
      final scrambled = img.Image(width: w, height: h);
      final remainder = h % numSlices;
      final baseH = h ~/ numSlices;
      for (var i = 0; i < numSlices; i++) {
        var copyH = baseH;
        var py = baseH * i;
        final y = h - baseH * (i + 1) - remainder;
        if (i == 0) {
          copyH += remainder;
        } else {
          py += remainder;
        }
        img.compositeImage(
          scrambled,
          original,
          dstX: 0,
          dstY: y,
          dstW: w,
          dstH: copyH,
          srcX: 0,
          srcY: py,
          srcW: w,
          srcH: copyH,
          blend: img.BlendMode.direct,
        );
      }

      final scrambledPng = Uint8List.fromList(img.encodePng(scrambled));
      final restoredPng =
          JmImageDescrambler.descrambleBytesSync(scrambledPng, numSlices);
      final restored = img.decodeImage(restoredPng)!;

      expect(restored.width, w);
      expect(restored.height, h);
      for (var y = 0; y < h; y++) {
        final px = restored.getPixel(0, y);
        expect(px.r.toInt(), y, reason: 'Row $y red channel mismatch');
        expect(px.g.toInt(), 255 - y, reason: 'Row $y green channel mismatch');
      }
    });
  });

  group('E-Hentai URL & HTML Parsers', () {
    test('f_cats inverted bitmask and ehgt thumb normalization', () {
      // Enabling only Doujinshi (0x2) & Manga (0x4) => mask = 0x6 => excluded = 0x3f9
      expect(EhUrl.encodeExcludedCats(0x6), 0x3f9);
      expect(EhUrl.encodeExcludedCats(EhUrl.allCategoryMask), 0);

      final url = EhUrl.buildGalleryListUrl(
        useExHentai: false,
        enabledCategoryMask: 0x6,
        searchQuery: 'blue archive',
        nextCursor: '3001234',
      );
      expect(url, contains('f_cats=1017'));
      expect(url, contains('f_search=blue+archive'));
      expect(url, contains('next=3001234'));

      expect(
        EhUrl.getFixedThumbUrl('https://exhentai.org/t/ab/cd/123456_250.jpg'),
        'https://ehgt.org/ab/cd/123456_250.jpg',
      );
    });

    test('parseGalleryList parses rows, rating, cursor, and tags', () {
      const sampleHtml = '''
      <html><body>
        <p class="searchtext">Found about 1,234 results.</p>
        <div class="searchnav">
          <a id="uprev" href="https://e-hentai.org/?prev=999">Prev</a>
          <a id="unext" href="https://e-hentai.org/?next=123456">Next</a>
        </div>
        <table class="itg gltc"><tbody>
          <tr>
            <td class="gl1c glcat"><div class="cn">Doujinshi</div></td>
            <td class="gl2c">
              <div class="glthumb">
                <div><img data-src="https://exhentai.org/t/aa/bb/cover_250.jpg" /></div>
              </div>
              <div id="posted_3100001">2026-11-20 12:00</div>
              <div class="ir" style="background-position:-16px -21px"></div>
            </td>
            <td class="gl3c glname">
              <a href="https://e-hentai.org/g/3100001/abcdef1234/">
                <div class="glink">[Sample Artist] Test Gallery [Chinese]</div>
              </a>
              <div class="gt" title="language:chinese">chinese</div>
              <div class="gtl" title="female:maid">maid</div>
            </td>
            <td class="gl4c glhide">
              <div><a href="#">uploader1</a></div>
              <div>42 pages</div>
            </td>
          </tr>
        </tbody></table>
      </body></html>
      ''';

      final res = EhParser.parseGalleryList(sampleHtml, isExHentai: false);
      expect(res.totalText, 'Found about 1,234 results.');
      expect(res.nextCursor, '123456');
      expect(res.prevCursor, '999');
      expect(res.hasMore, isTrue);
      expect(res.items, hasLength(1));

      final g = res.items.first;
      expect(g.id, '3100001');
      expect(g.token, 'abcdef1234');
      expect(g.title, '[Sample Artist] Test Gallery [Chinese]');
      expect(g.category, 'Doujinshi');
      expect(g.coverUrl, 'https://ehgt.org/aa/bb/cover_250.jpg');
      expect(g.posted, '2026-11-20 12:00');
      expect(g.rating, 3.5); // 5 - (16/16) - 0.5 = 3.5
      expect(g.uploaderSafe, 'uploader1');
      expect(g.pageCount, 42);
      expect(g.tags, ['language:chinese', 'female:maid']);
    });

    test('parseGalleryDetail and parseGalleryPage extract tags, previews, and image URL', () {
      const detailHtml = '''
      <html><body>
        <div id="gd1"><div style="width:250px; height:350px; background:transparent url(https://exhentai.org/t/11/22/cov.jpg)"></div></div>
        <h1 id="gn">English Title</h1>
        <h1 id="gj">日本語タイトル</h1>
        <div id="gdc"><div class="cs">Manga</div></div>
        <div id="gdn"><a>TestUploader</a></div>
        <div id="gdd"><table>
          <tr><td class="gdt1">Posted:</td><td class="gdt2">2026-11-20 10:00</td></tr>
          <tr><td class="gdt1">Language:</td><td class="gdt2">Chinese</td></tr>
          <tr><td class="gdt1">Length:</td><td class="gdt2">24 pages</td></tr>
        </table></div>
        <span id="rating_count">18</span>
        <div id="rating_label">Average: 4.82</div>
        <div id="gdf">Add to Favorites</div>
        <div id="taglist"><table>
          <tr><td>language:</td><td><div>chinese</div><div>translated</div></td></tr>
          <tr><td>female:</td><td><div>maid | 女仆</div></td></tr>
        </table></div>
        <div id="gdt">
          <a href="https://e-hentai.org/s/1122334455/3100001-1">
            <div style="width:100px; height:140px; background:transparent url(https://ehgt.org/m/001/sprite.jpg) -100px 0 no-repeat"></div>
          </a>
        </div>
        <table class="ptt"><tr><td>1</td><td>2</td><td>&gt;</td></tr></table>
      </body></html>
      ''';

      final detail = EhParser.parseGalleryDetail(
        detailHtml,
        gid: '3100001',
        token: 'abcdef1234',
        isExHentai: false,
      );
      expect(detail.summary.title, 'English Title');
      expect(detail.titleJpn, '日本語タイトル');
      expect(detail.summary.coverUrl, 'https://ehgt.org/11/22/cov.jpg');
      expect(detail.summary.pageCount, 24);
      expect(detail.summary.rating, 4.82);
      expect(detail.ratingCount, 18);
      expect(detail.totalPreviewPages, 2);
      expect(detail.tagGroups['language'], ['chinese', 'translated']);
      expect(detail.tagGroups['female'], ['maid']);
      expect(detail.previews, hasLength(1));
      expect(detail.previews.first.pageToken, '1122334455');
      expect(detail.previews.first.isSprite, isTrue);
      expect(detail.previews.first.xOffset, 100);

      const pageHtml = '''
      <html><body>
        <script>var showkey="abc987xyz";</script>
        <img id="img" src="https://hath.network/h/12345/image.jpg?nl=1" style="max-width:1280px" />
        <a id="loadfail" onclick="return nl('54321-98765')">Reload</a>
      </body></html>
      ''';
      final pageRes = EhParser.parseGalleryPage(pageHtml);
      expect(pageRes.imageUrl, 'https://hath.network/h/12345/image.jpg?nl=1');
      expect(pageRes.skipHathKey, '54321-98765');
      expect(pageRes.showKey, 'abc987xyz');
      expect(pageRes.is509, isFalse);
    });
  });

  group('EhTagTranslator', () {
    test('parses Mapaler binary tag database and suggests bilingual tags', () {
      final translator = EhTagTranslator();
      expect(translator.translateTag('language', 'chinese'), '中文');
      expect(translator.formatTagDisplay('female', 'maid'), '女仆 (maid)');

      final lines = [
        'f:tsundere\r${base64Encode(utf8.encode('傲娇'))}',
        'p:test work\r${base64Encode(utf8.encode('测试作品'))}',
      ].join('\n');
      final contentBytes = utf8.encode(lines);
      final header = ByteData(4)..setInt32(0, contentBytes.length, Endian.big);
      final fullBytes = Uint8List.fromList([
        ...header.buffer.asUint8List(),
        ...contentBytes,
      ]);

      final parsed = EhTagTranslator.parseBinaryDatabase(fullBytes);
      expect(parsed['f:tsundere'], '傲娇');
      expect(parsed['p:test work'], '测试作品');

      final suggestions = translator.suggest('女仆');
      expect(suggestions.any((s) => s.fullTag.contains('maid')), isTrue);
    });
  });

  group('Cloud Favorites Folders & E-Hentai Sign-In Parsers', () {
    test('JmRepository parses cloud folder_list and items cleanly', () {
      final store = LocalStore(inMemoryOnly: true);
      final httpClient = AppHttpClient();
      final repo = JmRepository(
        api: JmApiService(httpClient: httpClient, store: store),
        store: store,
      );

      final res = repo.parseCloudFavoritesResponse({
        'total': '25',
        'folder_list': [
          {'FID': 101, 'UID': 9, 'name': '纯爱收藏'},
          {'FID': '202', 'UID': 9, 'name': '短篇精选'},
        ],
        'list': [
          {
            'id': 422866,
            'name': 'Sample Comic',
            'author': ['AuthorA'],
            'category': {'title': '同人'},
            'category_sub': {'title': '汉化'},
          },
        ],
      }, page: 1);

      expect(res.total, 25);
      expect(res.hasMore, isTrue);
      expect(res.items, hasLength(1));
      expect(res.items.first.id, '422866');
      expect(res.folders, hasLength(2));
      expect(res.folders[0].id, '101');
      expect(res.folders[0].name, '纯爱收藏');
      expect(res.folders[1].id, '202');
      expect(res.folders[1].name, '短篇精选');
    });

    test('EhParser.parseFavoritesPage extracts 10 favcats and gallery list', () {
      final favHtml = '''
      <html><body>
        <div class="ido">
          <div class="fp"><div>12</div><div></div><div>FavZero</div></div>
          <div class="fp"><div>5</div><div></div><div>Manga</div></div>
          <div class="fp"><div>0</div><div></div><div>Favorites 2</div></div>
          <div class="fp"><div>3</div><div></div><div>Artist CG</div></div>
          <div class="fp"><div>0</div><div></div><div>Favorites 4</div></div>
          <div class="fp"><div>8</div><div></div><div>Doujin</div></div>
          <div class="fp"><div>0</div><div></div><div>Favorites 6</div></div>
          <div class="fp"><div>0</div><div></div><div>Favorites 7</div></div>
          <div class="fp"><div>0</div><div></div><div>Favorites 8</div></div>
          <div class="fp"><div>1</div><div></div><div>Read Later</div></div>
          <div class="fp fps">Show All Favorites</div>
        </div>
        <table class="itg gltc"><tbody>
          <tr>
            <td class="gl1c glcat"><div class="cn">Manga</div></td>
            <td class="gl2c">
              <div class="glthumb"><div><img src="https://ehgt.org/t/cov.jpg" /></div></div>
            </td>
            <td class="gl3c glname">
              <a href="https://e-hentai.org/g/3200001/0123456789/">
                <div class="glink">Fav Gallery Title</div>
              </a>
            </td>
          </tr>
        </tbody></table>
      </body></html>
      ''';

      final res = EhParser.parseFavoritesPage(favHtml, isExHentai: false);
      expect(res.folders, hasLength(10));
      expect(res.folders[0].id, '0');
      expect(res.folders[0].name, 'FavZero');
      expect(res.folders[0].count, 12);
      expect(res.folders[9].id, '9');
      expect(res.folders[9].name, 'Read Later');
      expect(res.folders[9].count, 1);
      expect(res.items, hasLength(1));
      expect(res.items.first.id, '3200001');
    });

    test('EhParser.parseSignInHtml and EhApiService.harvestCookies work cleanly', () {
      final ok = EhParser.parseSignInHtml(
        '<p>You are now logged in as: TestUser<br />Please wait...</p>',
      );
      expect(ok.success, isTrue);
      expect(ok.username, 'TestUser');

      final bad = EhParser.parseSignInHtml(
        '<div class="errorwrap"><h4>The error returned was:</h4><p>Username or password incorrect</p></div>',
      );
      expect(bad.success, isFalse);
      expect(bad.errorMessage, 'Username or password incorrect');

      final captcha = EhParser.parseSignInHtml(
        '<form><div class="g-recaptcha" data-sitekey="abc"></div></form>',
      );
      expect(captcha.success, isFalse);
      expect(captcha.errorMessage, contains('CAPTCHA'));

      final jar = <String, String>{'nw': '1', 'stale': 'old'};
      EhApiService.harvestCookies([
        'ipb_member_id=987654; path=/; domain=.e-hentai.org; HttpOnly',
        'ipb_pass_hash=0123456789abcdef0123456789abcdef; expires=Tue, 23-Nov-2027 00:00:00 GMT',
        'stale=deleted; Max-Age=0',
      ], jar);
      expect(jar['ipb_member_id'], '987654');
      expect(jar['ipb_pass_hash'], '0123456789abcdef0123456789abcdef');
      expect(jar.containsKey('stale'), isFalse);
    });
  });
}

extension on dynamic {
  String get uploaderSafe => (this.author as String?) ?? '';
}
