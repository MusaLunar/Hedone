import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedone/app.dart';
import 'package:hedone/core/app_dependencies.dart';
import 'package:hedone/core/theme/hedone_theme.dart';
import 'package:hedone/domain/models/comic_source.dart';
import 'package:hedone/ui/features/library/jm_batch_import_screen.dart';
import 'package:hedone/ui/features/library/library_screen.dart';
import 'package:hedone/ui/prism/prism_navigation_dock.dart';
import 'package:hedone/ui/prism/prism_sidebar.dart';
import 'package:hedone/ui/prism/prism_theme_preview.dart';

void main() {
  testWidgets('HedoneApp renders Prism UI shell and settings previews', (tester) async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    await tester.pumpWidget(HedoneApp(deps: deps));
    await tester.pumpAndSettle();

    expect(find.text('Hedone'), findsWidgets);
    expect(find.text('双源聚合'), findsOneWidget);
    expect(find.text('JMComic'), findsOneWidget);
    expect(find.text('E-Hentai'), findsOneWidget);
    expect(find.byType(PrismNavigationDock), findsOneWidget);

    // Switch to Settings destination and verify FlClash/Prism theme controls render
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('设置与账号'), findsOneWidget);
    expect(find.text('JMComic 专线与账号'), findsOneWidget);
    expect(find.text('E-Hentai / ExHentai 与标签汉化'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(PrismThemeModePicker),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.byType(PrismThemeModePicker), findsOneWidget);
    expect(find.text('对比度档位'), findsOneWidget);
    expect(find.text('悬浮胶囊导航栏'), findsOneWidget);
  });

  testWidgets('AdaptiveShell switches PrismNavigationDock, PrismSidebar, and single theme toggle cleanly', (tester) async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    // 1. Compact (< 600dp): Floating capsule dock + single AppBar theme toggle
    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpWidget(HedoneApp(deps: deps));
    await tester.pumpAndSettle();

    expect(find.byType(PrismNavigationDock), findsOneWidget);
    expect(find.byType(PrismSidebar), findsNothing);
    expect(find.byType(PrismGlassActionOrb), findsNothing);
    expect(find.byKey(const Key('theme_mode_toggle_button')), findsOneWidget);

    // 2. Expanded (>= 1200dp) default floating: Dock + detached Orb toggle only
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();

    expect(find.byType(PrismNavigationDock), findsOneWidget);
    expect(find.byType(PrismSidebar), findsNothing);
    expect(find.byType(PrismGlassActionOrb), findsOneWidget);
    expect(find.byKey(const Key('theme_mode_toggle_button')), findsOneWidget);

    // 3. Expanded (>= 1200dp) with floatingNavBar disabled: PrismSidebar + footer toggle only
    await deps.store.setFloatingNavBar(false);
    await tester.pumpAndSettle();

    expect(find.byType(PrismSidebar), findsOneWidget);
    expect(find.byType(PrismNavigationDock), findsNothing);
    expect(find.byKey(const Key('theme_mode_toggle_button')), findsOneWidget);

    // 4. Compact (< 600dp) always keeps PrismNavigationDock even when floatingNavBar is false
    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpAndSettle();

    expect(find.byType(PrismNavigationDock), findsOneWidget);
    expect(find.byType(PrismSidebar), findsNothing);
    expect(find.byKey(const Key('theme_mode_toggle_button')), findsOneWidget);
  });

  test('M3 contrast level persists in LocalStore and builds themes cleanly', () async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    expect(deps.store.contrastLevel, 0.0);

    for (final level in [0.0, 0.5, 1.0]) {
      await deps.store.setContrastLevel(level);
      expect(deps.store.contrastLevel, level);

      final seed = HedoneTheme.presets.first.color;
      final light = HedoneTheme.buildTheme(
        brightness: Brightness.light,
        seedColor: seed,
        contrastLevel: level,
      );
      final dark = HedoneTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: seed,
        contrastLevel: level,
      );

      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(light.textTheme.bodyMedium?.fontFamily, HedoneTheme.fontFamily);
      expect(dark.textTheme.titleLarge?.fontFamily, HedoneTheme.fontFamily);
    }
  });

  testWidgets('Dark and light mode quick toggle updates LocalStore themeMode', (tester) async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    await deps.store.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(HedoneApp(deps: deps));
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('theme_mode_toggle_button'));
    expect(toggleFinder, findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(deps.store.themeMode, ThemeMode.light);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(deps.store.themeMode, ThemeMode.dark);
  });

  testWidgets('JmBatchImportScreen extracts IDs and saves selected favorites', (tester) async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: HedoneTheme.buildTheme(
          brightness: Brightness.light,
          seedColor: HedoneTheme.presets.first.color,
        ),
        home: JmBatchImportScreen(deps: deps),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('jm_batch_input')),
      '推荐 JM422866 和 车牌号：512345，日期 2025-11-22 应被过滤',
    );
    await tester.pump();

    expect(find.text('识别结果 (2)'), findsOneWidget);
    expect(find.text('JM422866'), findsOneWidget);
    expect(find.text('JM512345'), findsOneWidget);
    expect(find.text('批量收藏已选 (2)'), findsOneWidget);

    await tester.tap(find.text('获取漫画标题与封面'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('jm_batch_import_submit')));
    await tester.pumpAndSettle();

    expect(deps.store.isFavorite(ComicSource.jmcomic, '422866'), isTrue);
    expect(deps.store.isFavorite(ComicSource.jmcomic, '512345'), isTrue);
    expect(deps.store.favorites.length, 2);
  });

  test('EhApiService.signInWithPassword captures cookies across 302 redirects and probes sk/igneous', () async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    deps.httpClient.dio.httpClientAdapter = _FakeHttpAdapter((options, body) async {
      final url = options.uri.toString();
      if (url.contains('CODE=00')) {
        return ResponseBody.fromString(
          '<form action="login"></form>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
            'set-cookie': ['ipb_session_id=sess123; path=/'],
          },
        );
      }
      if (url.contains('CODE=01')) {
        expect(options.headers['Cookie'].toString(), contains('ipb_session_id=sess123'));
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://forums.e-hentai.org/index.php?act=idx'],
            'set-cookie': [
              'ipb_member_id=778899; path=/; domain=.e-hentai.org',
              'ipb_pass_hash=deadbeef0123456789abcdef01234567; path=/',
            ],
          },
        );
      }
      if (url.contains('act=idx')) {
        expect(options.headers['Cookie'].toString(), contains('ipb_member_id=778899'));
        return ResponseBody.fromString(
          '<p>You are now logged in as: HedoneUser</p>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      }
      if (url == 'https://e-hentai.org/') {
        return ResponseBody.fromString(
          '<html></html>',
          200,
          headers: {
            'set-cookie': ['sk=sk_token_abc; path=/'],
          },
        );
      }
      if (url == 'https://exhentai.org/') {
        return ResponseBody.fromString(
          '<html></html>',
          200,
          headers: {
            'set-cookie': ['igneous=ign_xyz_99; path=/'],
          },
        );
      }
      return ResponseBody.fromString('', 404);
    });

    final res = await deps.ehApi.signInWithPassword('HedoneUser', 'secret-pass');
    expect(res.success, isTrue);
    expect(res.username, 'HedoneUser');
    expect(deps.store.isEhLoggedIn, isTrue);
    expect(deps.store.ehMemberId, '778899');
    expect(deps.store.ehPassHash, 'deadbeef0123456789abcdef01234567');
    expect(deps.store.ehSk, 'sk_token_abc');
    expect(deps.store.ehIgneous, 'ign_xyz_99');
  });

  testWidgets('LibraryScreen auto-loads cloud favorites, displays folders, and uses cache on tab revisit', (tester) async {
    final deps = await AppDependencies.create(inMemoryOnly: true);
    addTearDown(deps.dispose);

    await deps.store.setEhCookies(
      memberId: '10001',
      passHash: '0123456789abcdef0123456789abcdef',
    );

    var favRequests = 0;
    deps.httpClient.dio.httpClientAdapter = _FakeHttpAdapter((options, _) async {
      if (options.uri.path == '/favorites.php') {
        favRequests++;
        return ResponseBody.fromString(
          '''
          <html><body>
            <div class="ido">
              <div class="fp"><div>7</div><div></div><div>精选收藏</div></div>
              <div class="fp"><div>2</div><div></div><div>待读清单</div></div>
              <div class="fp fps">Show All Favorites</div>
            </div>
            <table class="itg gltc"><tbody>
              <tr>
                <td class="gl1c glcat"><div class="cn">Manga</div></td>
                <td class="gl2c"><div class="glthumb"><div><img src="" /></div></div></td>
                <td class="gl3c glname">
                  <a href="https://e-hentai.org/g/3300001/abcdef0123/">
                    <div class="glink">Cloud Sample Gallery</div>
                  </a>
                </td>
              </tr>
            </tbody></table>
          </body></html>
          ''',
          200,
          headers: {Headers.contentTypeHeader: ['text/html; charset=utf-8']},
        );
      }
      return ResponseBody.fromBytes(Uint8List(0), 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: HedoneTheme.buildTheme(
          brightness: Brightness.light,
          seedColor: HedoneTheme.presets.first.color,
        ),
        home: LibraryScreen(
          deps: deps,
          onSearchTag: (_, _) {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Cloud Favorites tab, then select E-Hentai source -> auto-loads without manual sync
    await tester.tap(find.text('云端收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('E-Hentai 云收藏'));
    await tester.pumpAndSettle();

    expect(favRequests, 1);
    expect(find.text('精选收藏 (7)'), findsOneWidget);
    expect(find.text('待读清单 (2)'), findsOneWidget);
    expect(find.text('Cloud Sample Gallery'), findsOneWidget);

    // Switch away to Reading History and return -> cached, zero extra HTTP requests
    await tester.tap(find.text('阅读历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('云端收藏'));
    await tester.pumpAndSettle();

    expect(favRequests, 1);
    expect(find.text('Cloud Sample Gallery'), findsOneWidget);

    // Explicit sync button refreshes once
    await tester.tap(find.byTooltip('同步云端收藏'));
    await tester.pumpAndSettle();
    expect(favRequests, 2);
  });
}

class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options, Stream<Uint8List>? stream) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options, requestStream);
  }

  @override
  void close({bool force = false}) {}
}
