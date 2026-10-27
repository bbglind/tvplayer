/// UI-independent core of tvplayer: models plus Xtream, M3U and XMLTV
/// clients/parsers, the TV guide (matching and time zones), movie and
/// series catalogues, metadata sources, audio/subtitle track selection and
/// watch history, replay (catch-up), favourites and hidden categories,
/// playlist refresh scheduling, title parsing, search, sorting and filters,
/// the provider stream guard and the downloads queue.
/// Pure Dart, no Flutter dependency.
library;

export 'src/downloads/disk_space.dart';
export 'src/downloads/download_item.dart';
export 'src/downloads/download_queue.dart';
export 'src/downloads/downloads_store.dart';
export 'src/downloads/file_names.dart';
export 'src/downloads/http_download.dart';
export 'src/downloads/replay_clip.dart';
export 'src/epg/archive_listings.dart';
export 'src/epg/channel_name.dart';
export 'src/epg/epg_builder.dart';
export 'src/epg/epg_guide.dart';
export 'src/epg/guide_time.dart';
export 'src/favourites/favourites_data.dart';
export 'src/favourites/favourites_logic.dart';
export 'src/favourites/ordering.dart';
export 'src/home/home_picks.dart';
export 'src/live/live_source.dart';
export 'src/live/replay.dart';
export 'src/m3u/m3u_client.dart';
export 'src/metadata/metadata_source.dart';
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
export 'src/playlist/missing_items.dart';
export 'src/playlist/playlist_status.dart';
export 'src/playlist/refresh_schedule.dart';
export 'src/streams/stream_guard.dart';
export 'src/text/provider_titles.dart';
export 'src/text/search_text.dart';
export 'src/text/title_parser.dart';
export 'src/tracks/language.dart';
export 'src/tracks/media_track.dart';
export 'src/tracks/track_picker.dart';
export 'src/util/provider_failure.dart';
export 'src/util/provider_key.dart';
export 'src/vod/variants.dart';
export 'src/vod/vod_catalog.dart';
export 'src/vod/vod_query.dart';
export 'src/vod/vod_source.dart';
export 'src/watch/watch_data.dart';
export 'src/watch/play_next.dart';
export 'src/watch/watch_logic.dart';
export 'src/xmltv/xmltv_parser.dart' show XmltvChannel, XmltvParser;
export 'src/xtream/xtream_client.dart';
