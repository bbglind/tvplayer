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

/// Start of a [tmdbImageRef].
const tmdbImageRefPrefix = 'tmdb:';

/// A reference to the TMDB image at [path] (e.g. `/abc.jpg`) in [size]:
/// `tmdb:w342/abc.jpg`. Images from TMDB are passed around this way so
/// they can be told apart from provider images, which may be hosted on
/// TMDB too; [tmdbImageRefToUrl] gives the address to download.
String tmdbImageRef(String path, TmdbImageSize size) =>
    '$tmdbImageRefPrefix${size.name}${path.startsWith('/') ? '' : '/'}$path';

/// [tmdbImageRef] for an optional [path].
String? tmdbImageRefOrNull(String? path, TmdbImageSize size) =>
    path == null ? null : tmdbImageRef(path, size);

/// Whether [image] is a [tmdbImageRef] rather than a provider address.
bool isTmdbImageRef(String image) => image.startsWith(tmdbImageRefPrefix);

/// The download address of the [tmdbImageRef] [ref].
String tmdbImageRefToUrl(String ref) =>
    '$tmdbImageBase${ref.substring(tmdbImageRefPrefix.length)}';
