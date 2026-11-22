import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Shared Dio HTTP client supporting optional proxy and certificate compatibility.
class AppHttpClient {
  AppHttpClient({
    String? proxyAddress,
    bool allowBadCertificates = true,
  }) : _proxyAddress = proxyAddress?.trim() ?? '',
       _allowBadCertificates = allowBadCertificates {
    _dio = _createDio();
  }

  late Dio _dio;
  String _proxyAddress;
  bool _allowBadCertificates;

  Dio get dio => _dio;
  String get proxyAddress => _proxyAddress;
  bool get allowBadCertificates => _allowBadCertificates;

  void updateConfig({
    String? proxyAddress,
    bool? allowBadCertificates,
  }) {
    final nextProxy = proxyAddress?.trim() ?? _proxyAddress;
    final nextBadCert = allowBadCertificates ?? _allowBadCertificates;
    if (nextProxy == _proxyAddress && nextBadCert == _allowBadCertificates) {
      return;
    }
    _proxyAddress = nextProxy;
    _allowBadCertificates = nextBadCert;
    _dio.close(force: false);
    _dio = _createDio();
  }

  Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.idleTimeout = const Duration(seconds: 20);
        if (_allowBadCertificates) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        if (_proxyAddress.isNotEmpty) {
          final normalized = _normalizeProxy(_proxyAddress);
          client.findProxy = (uri) => 'PROXY $normalized; DIRECT';
        }
        return client;
      },
    );
    return dio;
  }

  static String _normalizeProxy(String raw) {
    var clean = raw.trim();
    clean = clean.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'/+$'), '');
    return clean;
  }

  Future<Response<T>> getWithRetry<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    int maxRetries = 2,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _dio.get<T>(
          url,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      } catch (e) {
        lastError = e;
        if (cancelToken?.isCancelled == true || attempt == maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unknown network error');
  }
}
