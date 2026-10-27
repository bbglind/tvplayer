import 'dart:io';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  late Directory root;
  late Directory from;
  late Directory to;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy_directory');
    from = Directory('${root.path}/old.id');
    to = Directory('${root.path}/new.id');
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> write(Directory dir, String path, String text) async {
    final file = File('${dir.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<String> read(Directory dir, String path) =>
      File('${dir.path}/$path').readAsString();

  Future<List<String>> names() async => [
    for (final e in await root.list().toList())
      e.path.substring(root.path.length + 1),
  ]..sort();

  test('moves the old folder when only it exists', () async {
    await write(from, 'settings.json', '{"a":1}');
    await write(from, 'watch/key.json', 'watched');
    await Directory('${from.path}/empty').create();

    expect(
      await migrateLegacyDirectory(from, to),
      LegacyMigrationResult.migrated,
    );
    expect(await read(to, 'settings.json'), '{"a":1}');
    expect(await read(to, 'watch/key.json'), 'watched');
    expect(await Directory('${to.path}/empty').exists(), isTrue);
    expect(await names(), ['new.id']);
  });

  test('moves into an existing empty new folder', () async {
    await write(from, 'settings.json', 'old');
    await to.create();

    expect(
      await migrateLegacyDirectory(from, to),
      LegacyMigrationResult.migrated,
    );
    expect(await read(to, 'settings.json'), 'old');
    expect(await names(), ['new.id']);
  });

  test('leaves the new folder alone when there is no old one', () async {
    await write(to, 'settings.json', 'new');

    expect(await migrateLegacyDirectory(from, to), LegacyMigrationResult.none);
    expect(await read(to, 'settings.json'), 'new');
    expect(await names(), ['new.id']);
  });

  test('never overwrites data in the new folder', () async {
    await write(from, 'settings.json', 'old');
    await write(from, 'favourites/key.json', 'old');
    await write(to, 'settings.json', 'new');

    expect(
      await migrateLegacyDirectory(from, to),
      LegacyMigrationResult.skipped,
    );
    expect(await read(to, 'settings.json'), 'new');
    expect(await File('${to.path}/favourites/key.json').exists(), isFalse);
    expect(await read(from, 'settings.json'), 'old');
  });

  test('does nothing when neither folder exists', () async {
    expect(await migrateLegacyDirectory(from, to), LegacyMigrationResult.none);
    expect(await names(), isEmpty);
  });

  test('keeps the old folder when copying fails', () async {
    await write(from, 'settings.json', 'old');
    await write(from, 'playlist/key.json', 'old');
    await to.create();
    var copies = 0;

    final result = await migrateLegacyDirectory(
      from,
      to,
      copy: (file, target) async {
        if (++copies == 2) throw FileSystemException('Disk full', target);
        await file.copy(target);
      },
    );

    expect(result, LegacyMigrationResult.failed);
    expect(await read(from, 'settings.json'), 'old');
    expect(await read(from, 'playlist/key.json'), 'old');
    expect(await to.list().isEmpty, isTrue);
    expect(await names(), ['new.id', 'old.id']);
  });

  test('treats a short copy as failed', () async {
    await write(from, 'settings.json', 'old data');

    final result = await migrateLegacyDirectory(
      from,
      to,
      copy: (file, target) => File(target).writeAsString('old'),
    );

    expect(result, LegacyMigrationResult.failed);
    expect(await read(from, 'settings.json'), 'old data');
    expect(await names(), ['old.id']);
  });

  test('replaces staging left by an earlier failed attempt', () async {
    await write(from, 'settings.json', 'old');
    await write(Directory('${to.path}.migrating'), 'stale.json', 'stale');

    expect(
      await migrateLegacyDirectory(from, to),
      LegacyMigrationResult.migrated,
    );
    expect(await read(to, 'settings.json'), 'old');
    expect(await File('${to.path}/stale.json').exists(), isFalse);
    expect(await names(), ['new.id']);
  });
}
