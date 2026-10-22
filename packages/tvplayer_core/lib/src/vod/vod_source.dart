import 'package:http/http.dart' as http;

import '../models/category.dart';
import '../models/episode.dart';
import '../models/movie.dart';
import '../models/provider_config.dart';
import '../models/series.dart';
import '../xtream/xtream_client.dart';
import 'vod_catalog.dart';

/// Loads movies and series from a provider and resolves playback URLs.
abstract interface class VodSource {
  /// The source for [config], or null when the provider type has no movies
  /// or series (M3U playlists).
  static VodSource? forConfig(
    ProviderConfig config, {
    http.Client? httpClient,
  }) => switch (config.type) {
    ProviderType.xtream => XtreamVodSource(
      XtreamClient(config, httpClient: httpClient),
    ),
    ProviderType.m3u => null,
  };

  /// Fetches all movie categories and movies. Throws [XtreamException].
  Future<VodCatalog<Movie>> loadMovies({required DateTime now});

  /// Fetches all series categories and series. Throws [XtreamException].
  Future<VodCatalog<Series>> loadSeries({required DateTime now});

  /// Full details of [movie] (`get_vod_info`). Throws [XtreamException].
  Future<Movie> movieInfo(Movie movie);

  /// Seasons and episodes of a series (`get_series_info`). Recent results
  /// are reused. Throws [XtreamException].
  Future<SeriesInfo> seriesInfo(int seriesId);

  /// Playback URL of [movie]. Contains credentials: never log or show it.
  Uri movieUrl(Movie movie);

  /// Playback URL of [episode]. Contains credentials: never log or show it.
  Uri episodeUrl(Episode episode);

  void close();
}

/// [VodSource] backed by an Xtream panel.
class XtreamVodSource implements VodSource {
  XtreamVodSource(this._client, {this.seriesInfoMaxAge = _tenMinutes});

  static const _tenMinutes = Duration(minutes: 10);
  static const _seriesInfoCacheSize = 20;

  final XtreamClient _client;

  /// How long a [seriesInfo] result is reused.
  final Duration seriesInfoMaxAge;
  final _seriesInfo = <int, (DateTime, Future<SeriesInfo>)>{};

  @override
  Future<VodCatalog<Movie>> loadMovies({required DateTime now}) async {
    final results = await Future.wait<Object>([
      _client.getVodCategories(),
      _client.getVodStreams(),
    ]);
    return VodCatalog.movies(
      categories: results[0] as List<Category>,
      items: results[1] as List<Movie>,
      fetchedAt: now,
    );
  }

  @override
  Future<VodCatalog<Series>> loadSeries({required DateTime now}) async {
    final results = await Future.wait<Object>([
      _client.getSeriesCategories(),
      _client.getSeries(),
    ]);
    return VodCatalog.series(
      categories: results[0] as List<Category>,
      items: results[1] as List<Series>,
      fetchedAt: now,
    );
  }

  @override
  Future<Movie> movieInfo(Movie movie) => _client.getVodInfo(movie.streamId);

  @override
  Future<SeriesInfo> seriesInfo(int seriesId) {
    final now = DateTime.now();
    final cached = _seriesInfo.remove(seriesId);
    if (cached != null && now.difference(cached.$1) < seriesInfoMaxAge) {
      _seriesInfo[seriesId] = cached; // Most recently used last.
      return cached.$2;
    }
    final future = _client.getSeriesInfo(seriesId);
    _seriesInfo[seriesId] = (now, future);
    // Failures aren't kept, so a retry asks again.
    future
        .then<void>(
          (_) {},
          onError: (Object _) {
            if (identical(_seriesInfo[seriesId]?.$2, future)) {
              _seriesInfo.remove(seriesId);
            }
          },
        )
        .ignore();
    while (_seriesInfo.length > _seriesInfoCacheSize) {
      _seriesInfo.remove(_seriesInfo.keys.first);
    }
    return future;
  }

  @override
  Uri movieUrl(Movie movie) => _client.movieUrl(movie);

  @override
  Uri episodeUrl(Episode episode) => _client.episodeUrl(episode);

  @override
  void close() => _client.close();
}
