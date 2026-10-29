/// The sync server's HTTP API, shared by the app's client and the server.
///
/// - `GET /v1/health` (no login): `{"service", "api"}`
/// - `GET /v1/info`: `{"service", "api", "salt", "serverTime"}`
/// - `GET /v1/spaces/<space>/changes?since=<cursor>&limit=<n>`:
///   `{"records", "cursor", "more", "serverTime"}`
/// - `POST /v1/spaces/<space>/records` with `{"records"}`:
///   `{"stale", "serverTime"}`; HTTP 422 with `{"error": "clock"}` when a
///   record is dated more than [syncMaxAhead] after the server's clock.
///
/// Every request but health needs `Authorization: Bearer <token>`.
library;

/// The `service` value that identifies a tvplayer sync server.
const syncServiceName = 'tvplayer-sync';

/// The API version in `/v1/...` and the `api` value.
const syncApiVersion = 1;

/// Largest request body the server takes (HTTP 413 above it).
const syncMaxRequestBytes = 1024 * 1024;

/// Largest push body the app sends: well under the 1 MB that nginx (and
/// so Nginx Proxy Manager) takes by default, so a reverse proxy needs no
/// extra setting.
const syncMaxPushBytes = 256 * 1024;

/// Most records in one push or one page of changes.
const syncMaxRecords = 500;

/// About the largest page of changes the server sends.
const syncMaxPageBytes = 512 * 1024;

/// How far ahead of the server's clock a record may be dated.
const syncMaxAhead = Duration(minutes: 10);

final _spacePattern = RegExp(r'^[a-z][a-z0-9-]{0,63}$');

/// Whether [space] is a valid space name: lower-case letters, digits and
/// dashes, starting with a letter.
bool isSyncSpace(String space) => _spacePattern.hasMatch(space);
