/// UI-independent core of tvplayer: models plus Xtream, M3U and XMLTV
/// clients/parsers, and the TV guide (matching and time zones). Pure Dart, no Flutter dependency.
library;

export 'src/epg/channel_name.dart';
export 'src/epg/epg_builder.dart';
export 'src/epg/epg_guide.dart';
export 'src/epg/guide_time.dart';
export 'src/live/live_source.dart';
export 'src/m3u/m3u_client.dart';
export 'src/m3u/m3u_parser.dart' show M3uParser;
export 'src/models/account_info.dart';
export 'src/models/category.dart';
export 'src/models/epg_program.dart';
export 'src/models/episode.dart';
export 'src/models/live_channel.dart';
export 'src/models/m3u_entry.dart';
export 'src/models/movie.dart';
export 'src/models/provider_config.dart';
export 'src/models/series.dart';
export 'src/xmltv/xmltv_parser.dart' show XmltvChannel, XmltvParser;
export 'src/xtream/xtream_client.dart';
