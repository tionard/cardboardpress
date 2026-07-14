// lib/data/migration_snapshot.dart
//
// Safety net for schema migrations: BEFORE the database is first opened, if
// the file on disk carries an older schema version than the code, the raw
// file is copied to a snapshots folder — so a botched migration is a file
// swap away from recovery instead of data loss. Images need no snapshot;
// migrations never touch them.
//
// Why file-level and why before opening (not inside drift's onUpgrade):
// migrations run inside a transaction where `VACUUM INTO` can't run, and
// reading old-schema rows through new-schema Dart code is exactly the failure
// mode this guards against. Out here the file is closed and inert. The stored
// schema version is read straight from the SQLite header — offset 60, 4 bytes
// big-endian, the `user_version` pragma drift writes — no database library
// involved. The `-wal`/`-shm` siblings are copied too when present (a crashed
// previous run can leave a live WAL; the trio restores together).
//
// Path contract: drift_flutter names the file `<documents>/<name>.sqlite`
// (verified against drift_flutter source). If that package ever changes its
// scheme, [liveDatabaseFile] is the one place to update — a wrong path here
// degrades to "no snapshot taken", never to a wrong file being copied over.
//
// Failure posture: best-effort. A failed snapshot logs and lets the app
// launch — blocking startup on a disk-full device would brick the app the
// snapshot exists to protect.

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The live database file as drift_flutter names it.
Future<File> liveDatabaseFile() async {
  final docs = await getApplicationDocumentsDirectory();
  return File(p.join(docs.path, 'cardboardpress.sqlite'));
}

/// The schema version stored in a SQLite file's header (offset 60, 4 bytes
/// big-endian — the `user_version` pragma). Null when the file is missing,
/// too short to be a database, or unreadable. Advisory by design: a crashed
/// mid-migration WAL could hold a newer value, which at worst takes one
/// unnecessary snapshot.
int? readSqliteUserVersion(File file) {
  try {
    final raf = file.openSync();
    try {
      if (raf.lengthSync() < 64) return null;
      raf.setPositionSync(60);
      final b = raf.readSync(4);
      if (b.length < 4) return null;
      return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

/// Copies [dbFile] (and any `-wal`/`-shm` siblings) into [snapshotDir] when
/// its stored schema version is older than [currentSchemaVersion], then
/// prunes to the [keep] most recent snapshots. Returns whether a snapshot was
/// taken. Never throws.
Future<bool> snapshotBeforeMigrationIfNeeded({
  required File dbFile,
  required Directory snapshotDir,
  required int currentSchemaVersion,
  int keep = 3,
}) async {
  try {
    if (!await dbFile.exists()) return false; // first run — nothing to guard
    final stored = readSqliteUserVersion(dbFile);
    if (stored == null || stored == 0 || stored >= currentSchemaVersion) {
      return false; // unreadable, brand new, or no migration pending
    }

    await snapshotDir.create(recursive: true);
    final ts = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    final base = 'cardboardpress-v$stored-$ts';
    await dbFile.copy(p.join(snapshotDir.path, '$base.sqlite'));
    for (final suffix in const ['-wal', '-shm']) {
      final side = File('${dbFile.path}$suffix');
      if (await side.exists()) {
        await side.copy(p.join(snapshotDir.path, '$base.sqlite$suffix'));
      }
    }

    final readme = File(p.join(snapshotDir.path, 'README.txt'));
    if (!await readme.exists()) {
      await readme.writeAsString(
          'Automatic pre-migration database snapshots.\n'
          '\n'
          'One is taken whenever the app is about to upgrade the database\n'
          'schema. To roll back after a bad upgrade: close the app, replace\n'
          'cardboardpress.sqlite (one folder up) with a snapshot — renamed to\n'
          'exactly cardboardpress.sqlite, together with its .sqlite-wal /\n'
          '.sqlite-shm files if present — then reinstall the matching older\n'
          'app version. Only the newest few snapshots are kept.\n');
    }

    await _prune(snapshotDir, keep);
    debugPrint('migration snapshot: saved $base (v$stored -> '
        'v$currentSchemaVersion pending)');
    return true;
  } catch (e) {
    debugPrint('migration snapshot failed (continuing): $e');
    return false;
  }
}

/// Keeps the [keep] most recently modified snapshot groups; deletes the rest
/// (each group = the .sqlite plus its -wal/-shm siblings).
Future<void> _prune(Directory snapshotDir, int keep) async {
  final mains = <File>[];
  for (final e in await snapshotDir.list().toList()) {
    if (e is File &&
        p.basename(e.path).startsWith('cardboardpress-v') &&
        e.path.endsWith('.sqlite')) {
      mains.add(e);
    }
  }
  if (mains.length <= keep) return;
  // Modified-time ordering, newest first — filename order would break the
  // moment version numbers reach two digits ('v9' sorts after 'v11').
  final stats = <File, DateTime>{
    for (final f in mains) f: (await f.stat()).modified,
  };
  mains.sort((a, b) => stats[b]!.compareTo(stats[a]!));
  for (final old in mains.skip(keep)) {
    for (final path in [old.path, '${old.path}-wal', '${old.path}-shm']) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }
}

/// Startup entry point: resolves the live database path and the snapshots
/// folder next to it, then delegates. Call BEFORE anything opens the
/// database.
Future<bool> runStartupMigrationSnapshot(
    {required int currentSchemaVersion}) async {
  try {
    final dbFile = await liveDatabaseFile();
    return snapshotBeforeMigrationIfNeeded(
      dbFile: dbFile,
      snapshotDir:
          Directory(p.join(dbFile.parent.path, 'cardboardpress_db_snapshots')),
      currentSchemaVersion: currentSchemaVersion,
    );
  } catch (e) {
    debugPrint('migration snapshot failed (continuing): $e');
    return false;
  }
}
