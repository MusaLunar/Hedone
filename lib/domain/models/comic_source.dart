/// Supported comic data sources in Hedone.
enum ComicSource {
  jmcomic,
  ehentai;

  String get displayName => switch (this) {
    ComicSource.jmcomic => 'JMComic',
    ComicSource.ehentai => 'E-Hentai',
  };

  String get shortLabel => switch (this) {
    ComicSource.jmcomic => 'JM',
    ComicSource.ehentai => 'EH',
  };

  static ComicSource fromString(String? value) {
    return ComicSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ComicSource.jmcomic,
    );
  }
}

/// Source scope used in Explore and Search views.
enum SourceScope {
  all,
  jmcomic,
  ehentai;

  String get label => switch (this) {
    SourceScope.all => '双源聚合',
    SourceScope.jmcomic => 'JMComic',
    SourceScope.ehentai => 'E-Hentai',
  };
}
