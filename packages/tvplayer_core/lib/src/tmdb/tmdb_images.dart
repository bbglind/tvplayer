/// Image widths TMDB serves. Originals are never downloaded.
enum TmdbImageSize {
  /// Cast photos.
  w185,

  /// Episode stills.
  w300,

  /// Posters in lists and rows, person photos.
  w342,

  /// Posters on detail pages.
  w500,

  /// Backdrops on phones.
  w780,

  /// Backdrops on desktops.
  w1280,
}

const tmdbImageBase = 'https://image.tmdb.org/t/p/';

/// The address of the TMDB image at [path] (e.g. `/abc.jpg`) in [size].
String tmdbImageUrl(String path, TmdbImageSize size) =>
    '$tmdbImageBase${size.name}${path.startsWith('/') ? '' : '/'}$path';

/// [tmdbImageUrl] for an optional [path].
String? tmdbImageUrlOrNull(String? path, TmdbImageSize size) =>
    path == null ? null : tmdbImageUrl(path, size);
