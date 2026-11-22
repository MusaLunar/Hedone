enum JmIdMatchKind {
  url,
  explicit,
  numeric;

  String get label {
    switch (this) {
      case JmIdMatchKind.url:
        return '链接';
      case JmIdMatchKind.explicit:
        return 'JM前缀';
      case JmIdMatchKind.numeric:
        return '数字识别';
    }
  }

  int get priority {
    switch (this) {
      case JmIdMatchKind.url:
        return 0;
      case JmIdMatchKind.explicit:
        return 1;
      case JmIdMatchKind.numeric:
        return 2;
    }
  }
}

class JmExtractedId {
  const JmExtractedId({
    required this.id,
    required this.kind,
  });

  final String id;
  final JmIdMatchKind kind;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is JmExtractedId && other.id == id && other.kind == kind);
  }

  @override
  int get hashCode => Object.hash(id, kind);
}

class _RawMatch {
  const _RawMatch({
    required this.start,
    required this.id,
    required this.kind,
  });

  final int start;
  final String id;
  final JmIdMatchKind kind;
}

/// Extracts JMComic album IDs ("车牌号") from free-form text, URLs, and chat logs.
class JmIdExtractor {
  static final RegExp _ehUrlPattern = RegExp(
    r'(?:e-hentai|exhentai)\.org/g/\d+/[0-9a-fA-F]+',
    caseSensitive: false,
  );
  static final RegExp _separatedDatePattern = RegExp(
    r'\b(?:19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\b',
  );
  static final RegExp _compactDatePattern = RegExp(
    r'^(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])$',
  );

  static final RegExp _jmUrlPattern = RegExp(
    r'/(?:album|photo)/([1-9]\d{3,7})(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _explicitPattern = RegExp(
    r'(?:jm|禁漫(?:天堂)?|车牌号?|车号)[\s:#：\-_号]*(?:id[\s:#：\-_]*)?([1-9]\d{3,7})(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _standaloneNumericPattern = RegExp(
    r'(?<![0-9a-zA-Z.])([1-9]\d{4,7})(?![0-9a-zA-Z])',
  );

  static String _maskMatches(String input, RegExp pattern) {
    return input.replaceAllMapped(pattern, (m) => ' ' * (m.end - m.start));
  }

  /// Extracts unique JMComic album IDs in first-appearance order.
  static List<JmExtractedId> extract(String rawText) {
    if (rawText.trim().isEmpty) return const [];

    var sanitized = _maskMatches(rawText, _ehUrlPattern);
    sanitized = _maskMatches(sanitized, _separatedDatePattern);

    final rawMatches = <_RawMatch>[];

    for (final m in _jmUrlPattern.allMatches(sanitized)) {
      final id = m.group(1);
      if (id != null && id.isNotEmpty) {
        rawMatches.add(_RawMatch(start: m.start, id: id, kind: JmIdMatchKind.url));
      }
    }

    for (final m in _explicitPattern.allMatches(sanitized)) {
      final id = m.group(1);
      if (id != null && id.isNotEmpty) {
        rawMatches.add(
          _RawMatch(start: m.start, id: id, kind: JmIdMatchKind.explicit),
        );
      }
    }

    for (final m in _standaloneNumericPattern.allMatches(sanitized)) {
      final id = m.group(1);
      if (id != null && id.isNotEmpty && !_compactDatePattern.hasMatch(id)) {
        rawMatches.add(
          _RawMatch(start: m.start, id: id, kind: JmIdMatchKind.numeric),
        );
      }
    }

    rawMatches.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.kind.priority.compareTo(b.kind.priority);
    });

    final seen = <String>{};
    final result = <JmExtractedId>[];
    for (final item in rawMatches) {
      if (seen.add(item.id)) {
        result.add(JmExtractedId(id: item.id, kind: item.kind));
      }
    }
    return result;
  }

  /// Convenience helper returning only the recognized numeric ID strings.
  static List<String> extractIds(String rawText) {
    return extract(rawText).map((e) => e.id).toList();
  }
}
