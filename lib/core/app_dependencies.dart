import 'network/app_http_client.dart';
import 'storage/local_store.dart';
import 'utils/eh_tag_translator.dart';
import '../data/ehentai/eh_api_service.dart';
import '../data/ehentai/eh_repository.dart';
import '../data/jmcomic/jm_api_service.dart';
import '../data/jmcomic/jm_repository.dart';
import '../data/services/download_service.dart';

/// Application-wide dependency container following layered Repository pattern.
class AppDependencies {
  AppDependencies._({
    required this.store,
    required this.httpClient,
    required this.tagTranslator,
    required this.jmApi,
    required this.jmRepo,
    required this.ehApi,
    required this.ehRepo,
    required this.downloadService,
  }) {
    store.addListener(_syncHttpConfig);
  }

  final LocalStore store;
  final AppHttpClient httpClient;
  final EhTagTranslator tagTranslator;
  final JmApiService jmApi;
  final JmRepository jmRepo;
  final EhApiService ehApi;
  final EhRepository ehRepo;
  final DownloadService downloadService;

  void _syncHttpConfig() {
    httpClient.updateConfig(
      proxyAddress: store.proxyAddress,
      allowBadCertificates: store.allowBadCertificates,
    );
  }

  static Future<AppDependencies> create({bool inMemoryOnly = false}) async {
    final store = LocalStore(inMemoryOnly: inMemoryOnly);
    await store.init();

    final httpClient = AppHttpClient(
      proxyAddress: store.proxyAddress,
      allowBadCertificates: store.allowBadCertificates,
    );
    final tagTranslator = EhTagTranslator();
    if (!inMemoryOnly) {
      await tagTranslator.initFromDisk();
    }

    final jmApi = JmApiService(httpClient: httpClient, store: store);
    final jmRepo = JmRepository(api: jmApi, store: store);
    final ehApi = EhApiService(httpClient: httpClient, store: store);
    final ehRepo = EhRepository(api: ehApi, store: store);
    final downloadService = DownloadService(
      store: store,
      httpClient: httpClient,
      jmRepo: jmRepo,
      ehRepo: ehRepo,
      ehApi: ehApi,
    );

    return AppDependencies._(
      store: store,
      httpClient: httpClient,
      tagTranslator: tagTranslator,
      jmApi: jmApi,
      jmRepo: jmRepo,
      ehApi: ehApi,
      ehRepo: ehRepo,
      downloadService: downloadService,
    );
  }

  void dispose() {
    store.removeListener(_syncHttpConfig);
    store.dispose();
    tagTranslator.dispose();
    downloadService.dispose();
  }
}
