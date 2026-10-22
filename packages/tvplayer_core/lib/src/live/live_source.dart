import 'dart:io';

import 'package:http/http.dart' as http;

import '../m3u/m3u_client.dart';
import '../models/category.dart';
import '../models/live_channel.dart';
import '../models/provider_config.dart';
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
  });

  /// Unique within its [LiveCatalog].
  final String id;
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
    }
  }

  final List<Category> categories;

  /// Channels in provider order, including [LiveStream.isSeparator] entries.
  final List<LiveStream> channels;
  final Map<String, List<LiveStream>> _byCategory = {};
  final Map<String, int> _counts = {};

  int _channelCount = 0;

  /// Number of real channels, without separators.
  int get channelCount => _channelCount;

  /// Channels in [categoryId], or all channels when it is null, including
  /// separators.
  List<LiveStream> channelsIn(String? categoryId) =>
      categoryId == null ? channels : _byCategory[categoryId] ?? const [];

  /// Number of real channels in [categoryId], without separators.
  int countIn(String categoryId) => _counts[categoryId] ?? 0;
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

/// [LiveSource] backed by an M3U playlist. Categories are the playlist's
/// `group-title`s, in order of first appearance.
class M3uLiveSource implements LiveSource {
  M3uLiveSource(this._client);

  /// Category id used for entries without a `group-title`.
  static const ungroupedId = '';

  final M3uClient _client;
  final Map<String, String> _urls = {};

  @override
  Future<LiveCatalog> load() async {
    final entries = await _client.fetch();
    _urls.clear();
    final groups = <String>{};
    final channels = <LiveStream>[];
    for (final (i, e) in entries.indexed) {
      final group = e.groupTitle ?? ungroupedId;
      groups.add(group);
      final id = '$i';
      _urls[id] = e.url;
      channels.add(
        LiveStream(
          id: id,
          name: e.name,
          categoryIds: [group],
          logoUrl: e.tvgLogo,
          epgChannelId: e.tvgId,
        ),
      );
    }
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

  // A playlist's `url-tvg` guide isn't supported yet.
  @override
  bool get hasGuide => false;

  @override
  Future<void> downloadGuide(File target) =>
      throw UnsupportedError('M3U playlists have no guide yet');

  @override
  void close() => _client.close();
}
