import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/app_http_client.dart';
import '../../core/storage/local_store.dart';
import 'jm_crypto.dart';

class JmHostSpeedResult {
  const JmHostSpeedResult({
    required this.host,
    required this.label,
    required this.latencyMs,
    this.imgHost,
  });

  final String host;
  final String label;
  final int? latencyMs;
  final String? imgHost;
}

class JmApiException implements Exception {
  const JmApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'JmApiException($statusCode): $message';
}

/// Low-level HTTP & decryption client for JMComic3 API (`v2.1.9`).
class JmApiService {
  JmApiService({
    required AppHttpClient httpClient,
    required LocalStore store,
  }) : _http = httpClient,
       _store = store;

  final AppHttpClient _http;
  final LocalStore _store;

  static const String hostDiscoveryUrl =
      'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt';

  static const String backupHostCode =
      'X+bnzYIcwF6C7Rd3T7njPM0aeKgOoB+o/+lwS/klMzdv/yrVPk0UikahXv/MGxHqaSCwOCfGQjX0QpMpSxvr4+vsg/4ohUY8jspsJ7gSoQU5ANBMM99J2WtKxGgIBLq9PjCaS/34KK9HSiLJdaXz40oGSEHkBl8L0tTfPRC+dmPlp2CJ/97anZkSqForX+hTFgVoS0BZl/gXUQdF2njjAjgJwg13qbTJd3QB0CExaztlrC1Z1QGhXNjxM0Zk5v8i8JoPtTe7LWW55r96oLJrDOG60uspZxlV+Jp3FOdRXFH++Mann1Vo88iv9kbTa1f1FkaUCEgPpxNKmnCpnNUhNgCZExIlg7RcQQ6Ru+ys1D4+GAhA3Z1gUDMsYIit/bD8H30ZoBip59iW0Nx4haPYM5Pb9GyYRAkIJfQRP46w1JQXMPir0MCxMnvFahb0xzOULRx+WBrOe/oMKD1Dsohhxw==';

  static const List<String> defaultHosts = [
    'www.cdnbtd.cc',
    'www.cdnutc.cc',
    'www.cdngwc.net',
    'www.cdngwc.club',
    'www.cdnutc.me',
    'www.cdnaspa.vip',
    'www.cdnaspa.club',
    'www.cdnplaystation6.vip',
    'www.cdnplaystation6.cc',
    'www.cdnbea.net',
    'www.cdnhth.net',
    'www.cdngwc.cc',
    'www.cdnhth.club',
  ];

  static const List<String> defaultCdnHosts = [
    'https://cdn-msp.jmapiproxy3.cc',
    'https://cdn-msp2.jmapiproxy1.cc',
    'https://cdn-msp2.jmapiproxy2.cc',
    'https://cdn-msp3.jmapinodeudzn.net',
    'https://cdn-msp.jmapinodeudzn.net',
    'https://cdn-msp3.jmdanjonproxy.vip',
  ];

  List<String> _discoveredHosts = List<String>.from(defaultHosts);
  Map<String, String> _hostLabels = {};
  bool _initialized = false;

  List<String> get availableHosts => List.unmodifiable(_discoveredHosts);
  Map<String, String> get hostLabels => Map.unmodifiable(_hostLabels);

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await refreshHostList(silent: true);
    await syncSetting(silent: true);
  }

  Future<List<String>> refreshHostList({bool silent = false}) async {
    Map<String, dynamic>? parsed;
    try {
      final resp = await _http.dio.get<String>(
        hostDiscoveryUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final body = resp.data?.trim() ?? '';
      if (body.isNotEmpty) {
        parsed = JmCrypto.decryptHostTxt(body);
      }
    } catch (_) {
      // Fallback to baked hostCode.
    }

    if (parsed == null) {
      try {
        parsed = JmCrypto.decryptHostTxt(backupHostCode);
      } catch (e) {
        if (!silent) rethrow;
      }
    }

    if (parsed != null) {
      final servers = <String>{};
      final labels = <String, String>{};
      final rawServer = parsed['Server'];
      if (rawServer is List) {
        for (final h in rawServer) {
          final host = h.toString().trim();
          if (host.isNotEmpty) servers.add(host);
        }
      }
      final rawJm3 = parsed['jm3_Server'];
      if (rawJm3 is List) {
        for (final entry in rawJm3) {
          if (entry is List && entry.isNotEmpty) {
            final host = entry[0].toString().trim();
            final label = entry.length > 1 ? entry[1].toString().trim() : host;
            if (host.isNotEmpty) {
              servers.add(host);
              labels[host] = label;
            }
          }
        }
      }
      servers.addAll(defaultHosts);
      _discoveredHosts = servers.toList();
      _hostLabels = labels;

      if (!servers.contains(_store.jmApiHost) && servers.isNotEmpty) {
        await _store.setJmNetwork(apiHost: servers.first);
      }
    }
    return _discoveredHosts;
  }

  Future<JmHostSpeedResult> pingHost(String host, {String? label}) async {
    final sw = Stopwatch()..start();
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    try {
      final resp = await _http.dio.get<dynamic>(
        'https://$host/setting',
        queryParameters: {
          'app_img_shunt': _store.jmImgShunt.toString(),
          'lang': 'TW',
          't': ts.toString(),
        },
        options: Options(
          headers: JmCrypto.buildHeaders(
            ts,
            jwtToken: _store.jmJwtToken,
            avsCookie: _store.jmAvsCookie,
          ),
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      sw.stop();
      final decoded = _unwrapResponse(resp.data, ts);
      final imgHost = decoded is Map ? decoded['img_host']?.toString() : null;
      return JmHostSpeedResult(
        host: host,
        label: label ?? _hostLabels[host] ?? host,
        latencyMs: sw.elapsedMilliseconds,
        imgHost: imgHost,
      );
    } catch (_) {
      return JmHostSpeedResult(
        host: host,
        label: label ?? _hostLabels[host] ?? host,
        latencyMs: null,
      );
    }
  }

  Future<Map<String, dynamic>> syncSetting({bool silent = false}) async {
    try {
      final data = await get(
        'setting',
        queryParameters: {
          'app_img_shunt': _store.jmImgShunt.toString(),
          't': (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
        },
      );
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final imgHost = map['img_host']?.toString().trim();
        if (imgHost != null && imgHost.isNotEmpty) {
          await _store.setJmNetwork(imgHost: imgHost);
        }
        return map;
      }
      return const {};
    } catch (_) {
      if (!silent) rethrow;
      return const {};
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool rotateOnFailure = true,
  }) async {
    final candidates = <String>[
      _store.jmApiHost,
      if (rotateOnFailure)
        ..._discoveredHosts.where((h) => h != _store.jmApiHost).take(3),
    ];

    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final host = candidates[i];
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final params = <String, dynamic>{
        ...?queryParameters,
      }..putIfAbsent('lang', () => 'TW');

      try {
        final resp = await _http.dio.get<dynamic>(
          'https://$host/$path',
          queryParameters: params,
          options: Options(
            headers: JmCrypto.buildHeaders(
              ts,
              jwtToken: _store.jmJwtToken,
              avsCookie: _store.jmAvsCookie,
            ),
          ),
        );
        final decoded = _unwrapResponse(resp.data, ts);
        if (host != _store.jmApiHost) {
          await _store.setJmNetwork(apiHost: host);
        }
        return decoded;
      } on JmApiException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const JmApiException('JMComic 接口请求失败');
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic> fields = const {},
  }) async {
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final host = _store.jmApiHost;
    final formData = FormData.fromMap(fields);
    final resp = await _http.dio.post<dynamic>(
      'https://$host/$path',
      data: formData,
      options: Options(
        headers: JmCrypto.buildHeaders(
          ts,
          jwtToken: _store.jmJwtToken,
          avsCookie: _store.jmAvsCookie,
        ),
      ),
    );
    return _unwrapResponse(resp.data, ts);
  }

  dynamic _unwrapResponse(dynamic rawBody, int timestamp) {
    final Map<String, dynamic> envelope;
    if (rawBody is Map<String, dynamic>) {
      envelope = rawBody;
    } else if (rawBody is Map) {
      envelope = Map<String, dynamic>.from(rawBody);
    } else if (rawBody is String) {
      final trimmed = rawBody.trim();
      if (trimmed.isEmpty) {
        throw const JmApiException('JMComic 返回为空');
      }
      final dynamic parsed;
      try {
        parsed = jsonDecode(trimmed);
      } catch (_) {
        throw const JmApiException('JMComic 返回非 JSON 响应');
      }
      if (parsed is Map) {
        envelope = Map<String, dynamic>.from(parsed);
      } else {
        throw const JmApiException('JMComic 返回格式异常');
      }
    } else {
      throw const JmApiException('JMComic 返回为空');
    }

    final code = (envelope['code'] as num?)?.toInt() ?? 0;
    if (code != 200) {
      final msg = envelope['errorMsg']?.toString() ??
          envelope['msg']?.toString() ??
          '请求失败 (code: $code)';
      throw JmApiException(msg, statusCode: code);
    }

    return JmCrypto.decryptApiPayload(envelope['data'], timestamp);
  }
}
