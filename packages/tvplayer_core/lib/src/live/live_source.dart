import 'dart:io';

import 'package:http/http.dart' as http;

import '../m3u/m3u_client.dart';
import '../models/category.dart';
import '../models/live_channel.dart';
import '../models/m3u_entry.dart';
import '../models/provider_config.dart';
import '../text/search_text.dart';
import '../xtream/xtream_client.dart';

/// A live channel, independent of whether it came from Xtream or M3U.
///
/// Holds no stream URL: resolve one with [LiveSource.streamUrl].
final class LiveStream {
  const LiveStream({
    required this.id,
    required this.name,
    this.categoryIds = const [],
    this.logoUrl,
    this.number,
    this.epgChannelId,
    String? stableId,
  }) : stableId = stableId ?? id;

  /// Unique within its [LiveCatalog].
  final String id;

  /// Stays the same when the provider's list changes, so favourites can
  /// refer to it: the Xtream stream id, or for M3U the `tvg-id` (plus the
  /// name when several entries share it), else the name. Defaults to [id].
  final String stableId;
  final String name;
  final List<String> categoryIds;
  final String? logoUrl;
  final int? number;
  final String? epgChannelId;

  /// Whether this entry is a category heading rather than a channel, like
  /// `####### SWEDEN HD #######`. Providers add these to their lists; they
  /// have no programmes and can't be played.
  bool get isSeparator => separatorTitle(name) != null;

  @override
  String toString() => 'LiveStream($id, $name)';
}

/// The heading text of a separator entry's [name] (without the `#`
/// characters), or null when [name] is a real channel.
///
/// A name is a separator when it starts or ends with `###`, or when most of
/// its non-space characters are `#`.
String? separatorTitle(String name) {
  final trimmed = name.trim();
  final hashes = '#'.allMatches(trimmed).length;
  if (hashes == 0) return null;
  final others = trimmed.replaceAll(_hashOrSpace, '').length;
  if (!_hashRun.hasMatch(trimmed) && hashes <= others) return null;
  return trimmed.replaceAll('#', ' ').replaceAll(_spaces, ' ').trim();
}

final _hashOrSpace = RegExp(r'[#\s]');
final _hashRun = RegExp(r'^#{3,}|#{3,}$');
final _spaces = RegExp(r'\s+');

/// Categories and channels of one provider, with a per-category index.
final class LiveCatalog {
  LiveCatalog({required this.categories, required this.channels}) {
    for (final channel in channels) {
      final separator = channel.isSeparator;
      if (!separator) _channelCount++;
      for (final id in channel.categoryIds) {
        (_byCategory[id] ??= []).add(channel);
        if (!separator) _counts[id] = (_counts[id] ?? 0) + 1;
      }
      _byStableId.putIfAbsent(channel.stableId, () => channel);
    }
    for (final (i, channel) in channels.indexed) {
      _position[channel] = i;
    }
  }

  final List<Category> categories;

  /// Channels in provider order, including [LiveStream.isSeparator] entries.
  final List<LiveStream> channels;
  final Map<String, List<LiveStream>> _byCategory = {};
  final Map<String, int> _counts = {};
  final Map<String, LiveStream> _byStableId = {};

  final Map<LiveStream, int> _position = Map.identity();
  SearchIndex? _searchIndex;

  int _channelCount = 0;

  /// The search index of the channel names, built on first use unless
  /// [attachSearchIndex] gave one (built in a background isolate).
  SearchIndex get searchIndex =>
      _searchIndex ??= SearchIndex([for (final c in channels) c.name]);

  /// Whether the search index is built (or attached).
  bool get hasSearchIndex => _searchIndex != null;

  /// Uses [index], built elsewhere from the channel names in order (see
  /// [names]), instead of building one on first use.
  void attachSearchIndex(SearchIndex index) {
    if (index.length != channels.length) {
      throw ArgumentError(
        'Search index of ${index.length} names for '
        '${channels.length} channels',
      );
    }
    _searchIndex = index;
  }

  /// The channel names in order, for building a [SearchIndex] elsewhere.
  List<String> get names => [for (final c in channels) c.name];

  /// Channels of [within] (all channels when null) whose name matches
  /// [query] (see [SearchQuery]), without separators. With [ranked], the
  /// best matches come first (see [SearchIndex.ranked]); otherwise they
  /// keep their order. An empty query matches every channel.
  List<LiveStream> search(
    String query, {
    Iterable<LiveStream>? within,
    bool ranked = false,
  }) {
    final q = SearchQuery(query);
    final positions = [
      for (final c in within ?? channels)
        if (!c.isSeparator) ?_position[c],
    ];
    if (ranked) {
      return [
        for (final i in searchIndex.ranked(q, within: positions)) channels[i],
      ];
    }
    if (q.isEmpty) return [for (final i in positions) channels[i]];
    final hits = searchIndex.matching(q);
    return [
      for (final i in positions)
        if (hits[i] == 1) channels[i],
    ];
  }

  /// Number of real channels, without separators.
  int get channelCount => _channelCount;

  /// Channels in [categoryId], or all channels when it is null, including
  /// separators.
  List<LiveStream> channelsIn(String? categoryId) =>
      categoryId == null ? channels : _byCategory[categoryId] ?? const [];

  /// Number of real channels in [categoryId], without separators.
  int countIn(String categoryId) => _counts[categoryId] ?? 0;

  /// The first channel with [LiveStream.stableId] [stableId].
  LiveStream? byStableId(String stableId) => _byStableId[stableId];

  /// Whether [channel] is left out of "All channels" when the categories
  /// [hidden] are hidden: only when all its categories are.
  static bool isHidden(LiveStream channel, Set<String> hidden) =>
      hidden.isNotEmpty &&
      channel.categoryIds.isNotEmpty &&
      channel.categoryIds.every(hidden.contains);

  /// All channels (with separators) except those in [hidden] categories
  /// only.
  List<LiveStream> channelsExcluding(Set<String> hidden) => hidden.isEmpty
      ? channels
      : [
          for (final c in channels)
            if (!isHidden(c, hidden)) c,
        ];

  /// Number of real channels outside [hidden] categories.
  int countExcluding(Set<String> hidden) {
    if (hidden.isEmpty) return channelCount;
    var count = 0;
    for (final c in channels) {
      if (!c.isSeparator && !isHidden(c, hidden)) count++;
    }
    return count;
  }
}

/// Loads live TV from a provider and resolves playback URLs.
abstract interface class LiveSource {
  /// Creates the source matching [config]'s type.
  factory LiveSource.forConfig(
    ProviderConfig config, {
    http.Client? httpClient,
  }) => switch (config.type) {
    ProviderType.xtream => XtreamLiveSource(
      XtreamClient(config, httpClient: httpClient),
    ),
    ProviderType.m3u => M3uLiveSource(
      M3uClient(config.playlistUrl ?? '', httpClient: httpClient),
    ),
  };

  /// Fetches all categories and channels. Throws [XtreamException] or
  /// [M3uException] on failure.
  Future<LiveCatalog> load();

  /// Playback URL for [stream]. Contains credentials: never log or show it.
  Uri streamUrl(LiveStream stream);

  /// Whether [downloadGuide] is supported.
  bool get hasGuide;

  /// Downloads the provider's XMLTV guide into [target]. Throws
  /// [XtreamException] on failure and [UnsupportedError] when [hasGuide] is
  /// false.
  Future<void> downloadGuide(File target);

  void close();
}

/// [LiveSource] backed by an Xtream panel.
class XtreamLiveSource implements LiveSource {
  XtreamLiveSource(this._client);

  final XtreamClient _client;

  @override
  Future<LiveCatalog> load() async {
    // Future.wait rethrows the first error as-is (record .wait would wrap it).
    final results = await Future.wait<Object>([
      _client.getLiveCategories(),
      _client.getLiveStreams(),
    ]);
    final categories = results[0] as List<Category>;
    final streams = results[1] as List<LiveChannel>;
    return LiveCatalog(
      categories: categories,
      channels: [
        for (final s in streams)
          LiveStream(
            id: '${s.streamId}',
            name: s.name,
            categoryIds: {?s.categoryId, ...s.categoryIds}.toList(),
            logoUrl: s.logoUrl,
            number: s.number,
            epgChannelId: s.epgChannelId,
          ),
      ],
    );
  }

  @override
  Uri streamUrl(LiveStream stream) =>
      _client.liveStreamUrl(int.parse(stream.id));

  @override
  bool get hasGuide => true;

  @override
  Future<void> downloadGuide(File target) => _client.downloadXmltv(target);

  @override
  void close() => _client.close();
}

/// [LiveStream.stableId]s for playlist [entries]: `tvg:<tvg-id>` when the
/// id is unique in the playlist, `tvg:<tvg-id>|<name>` when several entries
/// share it (HD and SD variants often do), else `name:<name>`.
List<String> m3uStableIds(List<M3uEntry> entries) {
  String? tvg(M3uEntry e) {
    final id = e.tvgId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  final counts = <String, int>{};
  for (final e in entries) {
    if (tvg(e) case final id?) counts[id] = (counts[id] ?? 0) + 1;
  }
  return [
    for (final e in entries)
      switch (tvg(e)) {
        final id? when counts[id] == 1 => 'tvg:$id',
        final id? => 'tvg:$id|${e.name.trim()}',
        null => 'name:${e.name.trim()}',
      },
  ];
}

/// [LiveSource] backed by an M3U playlist. Categories are the playlist's
/// `group-title`s, in order of first appearance.
class M3uLiveSource implements LiveSource {
  M3uLiveSource(this._client);

  /// Category id used for entries without a `group-title`.
  static const ungroupedId = '';

  final M3uClient _client;
  Map<String, String> _urls = const {};

  @override
  Future<LiveCatalog> load() async {
    final entries = await _client.fetch();
    // Swapped in whole once the playlist is read, so a failed or running
    // refresh never changes the URL behind a channel.
    final urls = <String, String>{};
    final stableIds = m3uStableIds(entries);
    final groups = <String>{};
    final channels = <LiveStream>[];
    for (final (i, e) in entries.indexed) {
      final group = e.groupTitle ?? ungroupedId;
      groups.add(group);
      final id = '$i';
      urls[id] = e.url;
      channels.add(
        LiveStream(
          id: id,
          name: e.name,
          categoryIds: [group],
          logoUrl: e.tvgLogo,
          epgChannelId: e.tvgId,
          stableId: stableIds[i],
        ),
      );
    }
    _urls = urls;
    return LiveCatalog(
      categories: [
        for (final g in groups)
          Category(id: g, name: g == ungroupedId ? 'Ungrouped' : g),
      ],
      channels: channels,
    );
  }

  @override
  Uri streamUrl(LiveStream stream) {
    final url = _urls[stream.id];
    if (url == null) throw StateError('Unknown stream ${stream.id}');
    return Uri.parse(url);
  }

  // A playlist's `url-tvg` guide isn't supported yet. A guide URL added
  // later must be kept out of error messages, like the playlist URL.
  @override
  bool get hasGuide => false;

  @override
  Future<void> downloadGuide(File target) =>
      throw UnsupportedError('M3U playlists have no guide yet');

  @override
  void close() => _client.close();
}
