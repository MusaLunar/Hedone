import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/app_http_client.dart';
import '../../core/storage/local_store.dart';
import 'eh_parser.dart';
import 'eh_url.dart';

/// Low-level HTTP client for E-Hentai, ExHentai, and E-Hentai Forums.
class EhApiService {
  EhApiService({
    required AppHttpClient httpClient,
    required LocalStore store,
  }) : _http = httpClient,
       _store = store;

  final AppHttpClient _http;
  final LocalStore _store;

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  String buildCookieHeader({bool forExHentai = false}) {
    final parts = <String>['nw=1'];
    if (_store.ehMemberId.isNotEmpty) {
      parts.add('ipb_member_id=${_store.ehMemberId}');
    }
    if (_store.ehPassHash.isNotEmpty) {
      parts.add('ipb_pass_hash=${_store.ehPassHash}');
    }
    if (_store.ehIgneous.isNotEmpty) {
      parts.add('igneous=${_store.ehIgneous}');
    }
    if (_store.ehSk.isNotEmpty) {
      parts.add('sk=${_store.ehSk}');
    }
    if (forExHentai && _store.ehIgneous.isEmpty) {
      // ExHentai without igneous will fail cleanly with parser error.
    }
    return parts.join('; ');
  }

  Map<String, String> buildHeaders({
    bool? useExHentai,
    String? referer,
  }) {
    final isEx = useExHentai ?? _store.ehUseExHentai;
    final origin = EhUrl.host(isEx);
    return {
      'User-Agent': userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      'Cookie': buildCookieHeader(forExHentai: isEx),
      'Referer': referer ?? '$origin/',
      'Origin': origin,
    };
  }

  Future<String> getHtml(
    String url, {
    bool? useExHentai,
    String? referer,
  }) async {
    final isEx = useExHentai ?? _store.ehUseExHentai;
    final resp = await _http.getWithRetry<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: buildHeaders(useExHentai: isEx, referer: referer),
      ),
    );

    final disposition = resp.headers.value('content-disposition') ?? '';
    final contentType = resp.headers.value('content-type') ?? '';
    if (disposition.contains('sadpanda.jpg') ||
        (contentType.startsWith('image/gif') &&
            (resp.data?.length ?? 0) < 12000 &&
            url.contains('exhentai.org'))) {
      throw const EhParseException('ExHentai 访问受限 (Sad Panda)，请检查账号权限或 Cookie');
    }

    _captureSetCookies(resp.headers['set-cookie']);
    return resp.data ?? '';
  }

  Future<Map<String, dynamic>> postApi(
    Map<String, dynamic> body, {
    bool? useExHentai,
    String? referer,
  }) async {
    final isEx = useExHentai ?? _store.ehUseExHentai;
    final resp = await _http.dio.post<dynamic>(
      EhUrl.apiUrl(isEx),
      data: jsonEncode(body),
      options: Options(
        contentType: 'application/json; charset=utf-8',
        headers: buildHeaders(useExHentai: isEx, referer: referer),
      ),
    );
    return EhParser.decodeJsonObject(resp.data);
  }

  Future<void> postForm(
    String url,
    Map<String, dynamic> fields, {
    bool? useExHentai,
    String? referer,
  }) async {
    final isEx = useExHentai ?? _store.ehUseExHentai;
    await _http.dio.post<String>(
      url,
      data: fields,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        headers: buildHeaders(useExHentai: isEx, referer: referer),
      ),
    );
  }

  Future<EhLoginResult> signInWithPassword(
    String username,
    String password,
  ) async {
    final trimmedUser = username.trim();
    if (trimmedUser.isEmpty || password.isEmpty) {
      return const EhLoginResult(
        success: false,
        errorMessage: '请输入用户名和密码',
      );
    }

    const formUrl = '${EhUrl.hostForums}/index.php?act=Login&CODE=00';
    const loginUrl = '${EhUrl.hostForums}/index.php?act=Login&CODE=01';
    final cookieJar = <String, String>{'nw': '1'};

    // Step 1: Pre-GET login form to collect initial forum session cookies.
    try {
      final preResp = await _http.dio.get<String>(
        formUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'User-Agent': userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Cookie': serializeCookies(cookieJar),
          },
        ),
      );
      harvestCookies(preResp.headers['set-cookie'], cookieJar);
    } on DioException catch (e) {
      return EhLoginResult(
        success: false,
        errorMessage: '无法连接 E-Hentai 论坛（请检查网络或代理）：${e.message ?? e.type.name}',
      );
    }

    // Step 2: Submit credentials with followRedirects=false so intermediate Set-Cookie
    // headers on 301/302 responses are preserved rather than discarded by Dio.
    Response<String> resp;
    try {
      resp = await _http.dio.post<String>(
        loginUrl,
        data: {
          'UserName': trimmedUser,
          'PassWord': password,
          'CookieDate': '1',
          'b': 'd',
          'bt': '1-1',
          'submit': 'Log me in',
          'temporary_https': 'off',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'User-Agent': userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Referer': formUrl,
            'Origin': EhUrl.hostForums,
            'Cookie': serializeCookies(cookieJar),
          },
        ),
      );
    } on DioException catch (e) {
      return EhLoginResult(
        success: false,
        errorMessage: '登录请求失败（请检查网络或代理）：${e.message ?? e.type.name}',
      );
    }
    harvestCookies(resp.headers['set-cookie'], cookieJar);

    // Step 3: Follow any redirects manually, harvesting cookies at each hop.
    var currentUri = Uri.parse(loginUrl);
    for (var hop = 0; hop < 5; hop++) {
      final status = resp.statusCode ?? 0;
      if (status != 301 &&
          status != 302 &&
          status != 303 &&
          status != 307 &&
          status != 308) {
        break;
      }
      final location = resp.headers.value('location');
      if (location == null || location.isEmpty) break;
      currentUri = currentUri.resolve(location);
      try {
        resp = await _http.dio.get<String>(
          currentUri.toString(),
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
            headers: {
              'User-Agent': userAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
              'Referer': loginUrl,
              'Cookie': serializeCookies(cookieJar),
            },
          ),
        );
        harvestCookies(resp.headers['set-cookie'], cookieJar);
      } catch (_) {
        break;
      }
    }

    final memberId = (cookieJar['ipb_member_id'] ?? '').trim();
    final passHash = (cookieJar['ipb_pass_hash'] ?? '').trim();
    final html = resp.data ?? '';
    final parsed = EhParser.parseSignInHtml(html);

    if (memberId.isEmpty || memberId == '0' || passHash.isEmpty) {
      return EhLoginResult(
        success: false,
        errorMessage: parsed.success
            ? '登录响应缺少 ipb_member_id / ipb_pass_hash Cookie，请改用「配置 Cookie」方式登录'
            : (parsed.errorMessage ??
                '登录未返回有效 Cookie（ipb_member_id / ipb_pass_hash），请检查账号密码、网络代理，或改用 Cookie 登录'),
      );
    }

    // Step 4: Best-effort probe of e-hentai.org / exhentai.org to acquire sk & igneous.
    for (final probeUrl in [EhUrl.hostE, EhUrl.hostEx]) {
      try {
        final probeResp = await _http.dio.get<String>(
          '$probeUrl/',
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
            headers: {
              'User-Agent': userAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Cookie': serializeCookies(cookieJar),
            },
          ),
        );
        harvestCookies(probeResp.headers['set-cookie'], cookieJar);
      } catch (_) {
        // Non-fatal: ipb_member_id & ipb_pass_hash are already valid for e-hentai.org.
      }
    }

    var igneous = (cookieJar['igneous'] ?? '').trim();
    if (igneous == 'mystery' || igneous == 'expired' || igneous == 'deleted') {
      igneous = '';
    }
    final sk = (cookieJar['sk'] ?? '').trim();

    await _store.setEhCookies(
      memberId: memberId,
      passHash: passHash,
      igneous: igneous,
      sk: sk,
    );
    return EhLoginResult(
      success: true,
      username: (parsed.username?.isNotEmpty ?? false)
          ? parsed.username
          : trimmedUser,
    );
  }

  /// Parses `Set-Cookie` headers into [jar], retaining key=value pairs and removing `deleted` ones.
  static void harvestCookies(List<String>? setCookies, Map<String, String> jar) {
    if (setCookies == null || setCookies.isEmpty) return;
    for (final header in setCookies) {
      final firstSep = header.indexOf(';');
      final kv = (firstSep >= 0 ? header.substring(0, firstSep) : header).trim();
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      final name = kv.substring(0, eq).trim();
      final value = kv.substring(eq + 1).trim();
      if (value.isEmpty || value == 'deleted') {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }
  }

  static String serializeCookies(Map<String, String> jar) {
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _captureSetCookies(List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return;
    var sk = _store.ehSk;
    var igneous = _store.ehIgneous;
    var changed = false;
    for (final header in setCookies) {
      for (final seg in header.split(';')) {
        final kv = seg.trim();
        if (kv.startsWith('sk=')) {
          final v = kv.substring(3);
          if (v.isNotEmpty && v != sk) {
            sk = v;
            changed = true;
          }
        } else if (kv.startsWith('igneous=')) {
          final v = kv.substring(8);
          if (v.isNotEmpty && v != 'mystery' && v != igneous) {
            igneous = v;
            changed = true;
          }
        }
      }
    }
    if (changed && _store.isEhLoggedIn) {
      _store.setEhCookies(
        memberId: _store.ehMemberId,
        passHash: _store.ehPassHash,
        igneous: igneous,
        sk: sk,
      );
    }
  }
}
