import 'dart:async';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'title_match.dart';
import 'tmdb_client.dart';
import 'tmdb_credential.dart';
import 'tmdb_models.dart';
import 'tmdb_store.dart';
import 'tmdb_sync.dart';

/// [TmdbBackend] running [TmdbSync], its HTTP client and the database in a
/// background isolate, so requests, JSON parsing and database writes never
/// slow down the UI.
class TmdbWorker implements TmdbBackend {
  TmdbWorker._(this._isolate, this._commands, this._replies);

  /// Starts a worker with the database at [databasePath].
  static Future<TmdbWorker> spawn({
    required String databasePath,
    required TmdbCredential credential,
  }) async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    TmdbWorker? worker;
    replies.listen((message) {
      if (message is SendPort && !ready.isCompleted) {
        ready.complete(message);
      } else {
        worker?._onReply(message);
      }
    });
    final isolate = await Isolate.spawn(
      _main,
      (replies.sendPort, databasePath, credential),
      debugName: 'tmdb',
      errorsAreFatal: false,
    );
    return worker = TmdbWorker._(isolate, await ready.future, replies);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final _events = StreamController<TmdbEvent>.broadcast();
  final _calls = <int, Completer<Object?>>{};
  var _nextCall = 0;

  void _onReply(Object? message) {
    switch (message) {
      case TmdbEvent event:
        _events.add(event);
      case (int id, Object? result, String? error):
        final call = _calls.remove(id);
        if (call == null) return;
        if (error != null) {
          call.completeError(StateError(error));
        } else {
          call.complete(result);
        }
    }
  }

  Future<T> _call<T>(_Command command) {
    final id = _nextCall++;
    final completer = _calls[id] = Completer<Object?>();
    _commands.send((id, command));
    return completer.future.then((r) => r as T);
  }

  @override
  Stream<TmdbEvent> get events => _events.stream;

  @override
  Future<void> setWork(List<TmdbKey> wanted, List<TitleSearch> searches) =>
      _call(_SetWork(wanted, searches));

  @override
  Future<void> setPause(TmdbPause? pause) => _call(_SetPause(pause));

  @override
  Future<TmdbTitle?> title(TmdbKey key) => _call(_Title(key));

  @override
  Future<TmdbKey?> resolve(TitleSearch search) => _call(_Resolve(search));

  @override
  Future<TmdbSeason?> season(int tvId, int number, {bool ongoing = false}) =>
      _call(_Season(tvId, number, ongoing));

  @override
  Future<TmdbPerson?> person(int id) => _call(_Person(id));

  @override
  Future<Map<(TmdbKind, String), TitleMatch>> matches() => _call(_Matches());

  @override
  Future<Set<TmdbKey>> removedLinks() => _call(_RemovedLinks());

  @override
  Future<List<TmdbArtwork>> artwork() => _call(_Artwork());

  @override
  Future<void> removeMatch(TmdbKind kind, String key) =>
      _call(_RemoveMatch(kind, key));

  @override
  Future<void> removeLink(TmdbKey key) => _call(_RemoveLink(key));

  @override
  Future<int> removedCount() => _call(_RemovedCount());

  @override
  Future<void> allowMatchingAgain() => _call(_AllowAgain());

  @override
  Future<void> close() async {
    try {
      await _call<void>(_Close()).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Killed below anyway.
    }
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.close();
    for (final call in _calls.values) {
      call.completeError(StateError('TMDB worker closed'));
    }
    _calls.clear();
    await _events.close();
  }

  static Future<void> _main((SendPort, String, TmdbCredential) args) async {
    final (replies, path, credential) = args;
    final commands = ReceivePort();
    final client = http.Client();
    final store = TmdbStore.open(path);
    final sync = TmdbSync(store: store, api: TmdbClient(client, credential));
    sync.events.listen(replies.send);
    replies.send(commands.sendPort);
    await for (final message in commands) {
      if (message case (final int id, final _Command command)) {
        if (command is _Close) {
          await sync.close();
          store.close();
          client.close();
          replies.send((id, null, null));
          commands.close();
          return;
        }
        unawaited(
          Future(() => command.run(sync)).then(
            (result) => replies.send((id, result, null)),
            // The type only: messages may quote request details.
            onError: (Object e) => replies.send((id, null, '${e.runtimeType}')),
          ),
        );
      }
    }
  }
}

sealed class _Command {
  FutureOr<Object?> run(TmdbSync sync);
}

final class _SetWork extends _Command {
  _SetWork(this.wanted, this.searches);

  final List<TmdbKey> wanted;
  final List<TitleSearch> searches;

  @override
  Future<void> run(TmdbSync sync) => sync.setWork(wanted, searches);
}

final class _SetPause extends _Command {
  _SetPause(this.pause);

  final TmdbPause? pause;

  @override
  Future<void> run(TmdbSync sync) => sync.setPause(pause);
}

final class _Title extends _Command {
  _Title(this.key);

  final TmdbKey key;

  @override
  Future<TmdbTitle?> run(TmdbSync sync) => sync.title(key);
}

final class _Resolve extends _Command {
  _Resolve(this.search);

  final TitleSearch search;

  @override
  Future<TmdbKey?> run(TmdbSync sync) => sync.resolve(search);
}

final class _Season extends _Command {
  _Season(this.tvId, this.number, this.ongoing);

  final int tvId;
  final int number;
  final bool ongoing;

  @override
  Future<TmdbSeason?> run(TmdbSync sync) =>
      sync.season(tvId, number, ongoing: ongoing);
}

final class _Person extends _Command {
  _Person(this.id);

  final int id;

  @override
  Future<TmdbPerson?> run(TmdbSync sync) => sync.person(id);
}

final class _Matches extends _Command {
  @override
  Future<Map<(TmdbKind, String), TitleMatch>> run(TmdbSync sync) =>
      sync.matches();
}

final class _RemovedLinks extends _Command {
  @override
  Future<Set<TmdbKey>> run(TmdbSync sync) => sync.removedLinks();
}

final class _Artwork extends _Command {
  @override
  Future<List<TmdbArtwork>> run(TmdbSync sync) => sync.artwork();
}

final class _RemoveMatch extends _Command {
  _RemoveMatch(this.kind, this.key);

  final TmdbKind kind;
  final String key;

  @override
  Future<void> run(TmdbSync sync) => sync.removeMatch(kind, key);
}

final class _RemoveLink extends _Command {
  _RemoveLink(this.key);

  final TmdbKey key;

  @override
  Future<void> run(TmdbSync sync) => sync.removeLink(key);
}

final class _RemovedCount extends _Command {
  @override
  Future<int> run(TmdbSync sync) => sync.removedCount();
}

final class _AllowAgain extends _Command {
  @override
  Future<void> run(TmdbSync sync) => sync.allowMatchingAgain();
}

final class _Close extends _Command {
  @override
  Object? run(TmdbSync sync) => null;
}
