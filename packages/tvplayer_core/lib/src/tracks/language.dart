/// A language, recognised from an ISO 639-1 code (`sv`), an ISO 639-2
/// bibliographic or terminology code (`swe`; `ger`/`deu`), its English name
/// (`Swedish`) or its own name (`Svenska`).
///
/// Media files and settings use all of these, so tracks are matched through
/// [Language.parse] rather than by comparing strings.
final class Language {
  const Language._(
    this.code,
    this.iso639_2,
    this.englishName,
    this.nativeName, [
    this._aliases = const [],
  ]);

  /// ISO 639-1 code; the canonical id stored in settings.
  final String code;

  /// ISO 639-2 terminology code (`deu`, `fra`); bibliographic variants are
  /// in the alias list.
  final String iso639_2;
  final String englishName;

  /// The language's own name, as shown in menus (`Svenska`, `Deutsch`).
  final String nativeName;

  /// Other codes and names that mean this language.
  final List<String> _aliases;

  /// All languages known to [parse], in [englishName] order.
  static List<Language> get all => _all;

  /// The language [text] names, or null when it isn't recognised (also for
  /// `und`, "undetermined"). Case, surrounding spaces and region suffixes
  /// (`en-US`, `sv_SE`) are ignored.
  static Language? parse(String? text) {
    if (text == null) return null;
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return null;
    final direct = _index[key];
    if (direct != null) return direct;
    final base = key.split(RegExp('[-_]')).first;
    return _index[base];
  }

  /// Whether [a] and [b] name the same language. False when either is not
  /// recognised.
  static bool same(String? a, String? b) {
    final la = parse(a);
    return la != null && identical(la, parse(b));
  }

  @override
  String toString() => 'Language($code)';
}

const _all = [
  Language._('ar', 'ara', 'Arabic', 'العربية'),
  Language._('bg', 'bul', 'Bulgarian', 'Български'),
  Language._('bs', 'bos', 'Bosnian', 'Bosanski'),
  Language._('ca', 'cat', 'Catalan', 'Català'),
  Language._('cs', 'ces', 'Czech', 'Čeština', ['cze']),
  Language._('da', 'dan', 'Danish', 'Dansk'),
  Language._('de', 'deu', 'German', 'Deutsch', ['ger']),
  Language._('el', 'ell', 'Greek', 'Ελληνικά', ['gre']),
  Language._('en', 'eng', 'English', 'English'),
  Language._('es', 'spa', 'Spanish', 'Español', ['castellano']),
  Language._('et', 'est', 'Estonian', 'Eesti'),
  Language._('fa', 'fas', 'Persian', 'فارسی', ['per', 'farsi']),
  Language._('fi', 'fin', 'Finnish', 'Suomi'),
  Language._('fr', 'fra', 'French', 'Français', ['fre']),
  Language._('he', 'heb', 'Hebrew', 'עברית', ['iw']),
  Language._('hi', 'hin', 'Hindi', 'हिन्दी'),
  Language._('hr', 'hrv', 'Croatian', 'Hrvatski', ['scr']),
  Language._('hu', 'hun', 'Hungarian', 'Magyar'),
  Language._('id', 'ind', 'Indonesian', 'Bahasa Indonesia'),
  Language._('is', 'isl', 'Icelandic', 'Íslenska', ['ice']),
  Language._('it', 'ita', 'Italian', 'Italiano'),
  Language._('ja', 'jpn', 'Japanese', '日本語'),
  Language._('ko', 'kor', 'Korean', '한국어'),
  Language._('ku', 'kur', 'Kurdish', 'Kurdî'),
  Language._('lt', 'lit', 'Lithuanian', 'Lietuvių'),
  Language._('lv', 'lav', 'Latvian', 'Latviešu'),
  Language._('mk', 'mkd', 'Macedonian', 'Македонски', ['mac']),
  Language._('ms', 'msa', 'Malay', 'Bahasa Melayu', ['may']),
  Language._('nl', 'nld', 'Dutch', 'Nederlands', ['dut', 'flemish']),
  // Bokmål and Nynorsk count as Norwegian: a "Norwegian" preference should
  // pick either.
  Language._('no', 'nor', 'Norwegian', 'Norsk', [
    'nb',
    'nn',
    'nob',
    'nno',
    'norwegian bokmål',
    'norwegian nynorsk',
    'bokmål',
    'nynorsk',
    'norsk bokmål',
    'norsk nynorsk',
  ]),
  Language._('pl', 'pol', 'Polish', 'Polski'),
  Language._('pt', 'por', 'Portuguese', 'Português'),
  Language._('ro', 'ron', 'Romanian', 'Română', ['rum']),
  Language._('ru', 'rus', 'Russian', 'Русский'),
  Language._('sk', 'slk', 'Slovak', 'Slovenčina', ['slo']),
  Language._('sl', 'slv', 'Slovenian', 'Slovenščina', ['slovene']),
  Language._('so', 'som', 'Somali', 'Soomaali'),
  Language._('sq', 'sqi', 'Albanian', 'Shqip', ['alb']),
  Language._('sr', 'srp', 'Serbian', 'Српски', ['scc', 'srpski']),
  Language._('sv', 'swe', 'Swedish', 'Svenska', ['sve']),
  Language._('th', 'tha', 'Thai', 'ไทย'),
  Language._('tl', 'tgl', 'Tagalog', 'Tagalog', ['fil', 'filipino']),
  Language._('tr', 'tur', 'Turkish', 'Türkçe'),
  Language._('uk', 'ukr', 'Ukrainian', 'Українська'),
  Language._('ur', 'urd', 'Urdu', 'اردو'),
  Language._('vi', 'vie', 'Vietnamese', 'Tiếng Việt'),
  Language._('zh', 'zho', 'Chinese', '中文', ['chi', 'mandarin']),
];

final Map<String, Language> _index = {
  for (final l in _all)
    for (final key in [
      l.code,
      l.iso639_2,
      l.englishName,
      l.nativeName,
      ...l._aliases,
    ])
      key.toLowerCase(): l,
};
