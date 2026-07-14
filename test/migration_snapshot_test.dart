// Pre-migration snapshot tests (data/migration_snapshot.dart). Everything is
// plain file IO on crafted bytes — no real SQLite needed: the version check
// reads the documented header field (offset 60, big-endian user_version), so
// a fake file with those four bytes set behaves exactly like a database.

import 'dart:io';
import 'dart:typed_data';

import 'package:cardboardpress/data/migration_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake SQLite file: 128 bytes with user_version at offset 60 (big-endian).
Uint8List _fakeDb(int version) {
  final b = Uint8List(128);
  b[60] = (version >> 24) & 0xFF;
  b[61] = (version >> 16) & 0xFF;
  b[62] = (version >> 8) & 0xFF;
  b[63] = version & 0xFF;
  return b;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('cbp_snap_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeDb(int version, [String name = 'cardboardpress.sqlite']) {
    final f = File('${tmp.path}/$name');
    f.writeAsBytesSync(_fakeDb(version));
    return f;
  }

  Directory snapDir() => Directory('${tmp.path}/snaps');

  List<String> snapshotNames() => snapDir()
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.sqlite'))
      .toList();

  test('reads the big-endian user_version from the header', () {
    expect(readSqliteUserVersion(writeDb(11)), equals(11));
    expect(readSqliteUserVersion(writeDb(0x01020304)), equals(0x01020304));
  });

  test('too-short and missing files read as null', () {
    final short = File('${tmp.path}/short.sqlite')
      ..writeAsBytesSync(Uint8List(10));
    expect(readSqliteUserVersion(short), isNull);
    expect(readSqliteUserVersion(File('${tmp.path}/nope.sqlite')), isNull);
  });

  test('skips when no migration is pending', () async {
    final db = writeDb(12);
    expect(
        await snapshotBeforeMigrationIfNeeded(
            dbFile: db, snapshotDir: snapDir(), currentSchemaVersion: 12),
        isFalse,
        reason: 'same version — nothing to guard');
    expect(
        await snapshotBeforeMigrationIfNeeded(
            dbFile: db, snapshotDir: snapDir(), currentSchemaVersion: 11),
        isFalse,
        reason: 'file NEWER than code (downgrade) — snapshot would not help');
    expect(
        await snapshotBeforeMigrationIfNeeded(
            dbFile: File('${tmp.path}/absent.sqlite'),
            snapshotDir: snapDir(),
            currentSchemaVersion: 12),
        isFalse,
        reason: 'first run — no file yet');
    expect(snapDir().existsSync(), isFalse,
        reason: 'no snapshot folder appears when nothing was saved');
  });

  test('a pending migration snapshots the db and its wal sibling', () async {
    final db = writeDb(11);
    File('${db.path}-wal').writeAsBytesSync(Uint8List(32));

    final took = await snapshotBeforeMigrationIfNeeded(
        dbFile: db, snapshotDir: snapDir(), currentSchemaVersion: 12);

    expect(took, isTrue);
    final names = snapshotNames();
    expect(names, hasLength(1));
    expect(names.single, startsWith('cardboardpress-v11-'));
    expect(File('${snapDir().path}/${names.single}-wal').existsSync(), isTrue,
        reason: 'the WAL sibling rides along');
    expect(File('${snapDir().path}/README.txt').existsSync(), isTrue);
    // The copy is the old-schema bytes, not a mutation of them.
    expect(
        readSqliteUserVersion(File('${snapDir().path}/${names.single}')),
        equals(11));
  });

  test('retention keeps only the newest snapshots (by modified time)',
      () async {
    final db = writeDb(11);
    // Stage five existing snapshot groups directly, with staggered mtimes —
    // then one REAL snapshot call (keep: 3) adds a sixth (mtime = now) and
    // prunes. Survivors: the new one plus the two newest staged (run4, run3).
    snapDir().createSync(recursive: true);
    for (var i = 0; i < 5; i++) {
      final f = File('${snapDir().path}/cardboardpress-v11-run$i.sqlite')
        ..writeAsBytesSync(_fakeDb(11));
      f.setLastModifiedSync(DateTime(2026, 1, 1).add(Duration(minutes: i)));
      // Give one group a sibling to prove group deletion takes it too.
      if (i == 0) {
        File('${f.path}-wal').writeAsBytesSync(Uint8List(8));
      }
    }

    final took = await snapshotBeforeMigrationIfNeeded(
        dbFile: db, snapshotDir: snapDir(), currentSchemaVersion: 12, keep: 3);
    expect(took, isTrue);

    final names = snapshotNames()..sort();
    expect(names, hasLength(3));
    expect(names, contains('cardboardpress-v11-run3.sqlite'));
    expect(names, contains('cardboardpress-v11-run4.sqlite'));
    expect(names.where((n) => !n.contains('run')), hasLength(1),
        reason: 'the freshly taken snapshot survives as the newest');
    expect(names, isNot(contains('cardboardpress-v11-run0.sqlite')));
    expect(
        File('${snapDir().path}/cardboardpress-v11-run0.sqlite-wal')
            .existsSync(),
        isFalse,
        reason: 'pruning a group removes its siblings too');
  });
}
