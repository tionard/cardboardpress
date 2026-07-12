// lib/data/backup_service.dart
//
// Backup & Restore for the whole library. A backup is a single .zip:
//
//   manifest.json     — what this is + schema version + counts (validated on import)
//   library.sqlite    — a clean, current-schema snapshot of the content tables
//   images/<id>...     — every stored art/symbol file, by its id (filename)
//
// WHY a real .sqlite inside, not a JSON dump: when a future app version bumps the
// schema, opening an OLD backup as a drift database auto-runs the migrations, so
// an old backup restores cleanly on a newer app. We never overwrite the live,
// open database file (that fights OS file locks); instead we read rows out of the
// snapshot and re-insert them into the live DB inside a transaction — which also
// makes the watching providers refresh on their own, no restart needed.
//
// Semantics are REPLACE: restore clears the content tables and inserts the
// backup's rows. App settings (theme, and notably the Pro entitlement) are NOT
// part of a backup — a backup must never carry someone's preferences over yours,
// and must never be a way to flip Pro on.

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';
import 'image_store.dart';

/// Bumped only if the zip layout itself changes (not for schema bumps — those
/// are handled by drift migrating the snapshot on open).
const int kBackupFormat = 1;
const String _kBackupApp = 'CardboardPress';

/// A problem the user should see plainly (bad file, newer-version backup, …).
class BackupError implements Exception {
  final String message;
  const BackupError(this.message);
  @override
  String toString() => message;
}

class BackupManifest {
  final String app;
  final int backupFormat;
  final int schemaVersion;
  final DateTime createdAt;
  final int cards;
  final int templates;
  final int images;

  const BackupManifest({
    required this.app,
    required this.backupFormat,
    required this.schemaVersion,
    required this.createdAt,
    required this.cards,
    required this.templates,
    required this.images,
  });

  Map<String, dynamic> toJson() => {
        'app': app,
        'backupFormat': backupFormat,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt.toIso8601String(),
        'counts': {'cards': cards, 'templates': templates, 'images': images},
      };

  factory BackupManifest.fromJson(Map<String, dynamic> j) {
    final counts = (j['counts'] as Map?) ?? const {};
    return BackupManifest(
      app: (j['app'] ?? '') as String,
      backupFormat: (j['backupFormat'] ?? 0) as int,
      schemaVersion: (j['schemaVersion'] ?? 0) as int,
      createdAt:
          DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime(2000),
      cards: (counts['cards'] ?? 0) as int,
      templates: (counts['templates'] ?? 0) as int,
      images: (counts['images'] ?? 0) as int,
    );
  }
}

/// A validated backup the UI can describe (in a confirm dialog) before the
/// destructive restore actually runs.
class PickedBackup {
  final Uint8List bytes;
  final BackupManifest manifest;
  const PickedBackup(this.bytes, this.manifest);
}

class RestoreSummary {
  final int cards;
  final int templates;
  final int images;
  const RestoreSummary(
      {required this.cards, required this.templates, required this.images});
}

class BackupService {
  final AppDatabase db;
  final ImageStore images;
  BackupService(this.db, this.images);

  String suggestedFileName({DateTime? now}) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'cardboardpress_backup_${two(d.day)}${two(d.month)}${d.year}.zip';
  }

  // ---- export ----

  /// Desktop Save-as. Returns the written path, or null if cancelled.
  Future<String?> exportToFile() async {
    final bytes = await _buildZip();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save CardboardPress backup',
      fileName: suggestedFileName(),
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes, // used on mobile; desktop returns a path to write
    );
    if (path == null) return null;
    final out = path.toLowerCase().endsWith('.zip') ? path : '$path.zip';
    await File(out).writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Android: write a temp zip and open the system share sheet (save to Files,
  /// Drive, etc.). Returns true if the user completed the share.
  Future<bool> shareBackup() async {
    final bytes = await _buildZip();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, suggestedFileName()));
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/zip')]),
    );
    return result.status == ShareResultStatus.success;
  }

  Future<Uint8List> _buildZip() async {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final snapFile = File(p.join(tmp.path, 'cbp_export_$stamp.sqlite'));
    if (await snapFile.exists()) await snapFile.delete();

    // A fresh drift file seeds its defaults on create; clear them so the
    // snapshot mirrors the live library exactly, then copy the content in.
    final snapshot = AppDatabase.forFile(snapFile);
    try {
      await _clearContent(snapshot);
      await _copyContent(db, snapshot);
      await snapshot.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      await snapshot.close();
    }
    final dbBytes = await snapFile.readAsBytes();
    try {
      await snapFile.delete();
    } catch (_) {}

    final imgFiles = await images.allFiles();
    final manifest = BackupManifest(
      app: _kBackupApp,
      backupFormat: kBackupFormat,
      schemaVersion: db.schemaVersion,
      createdAt: DateTime.now(),
      cards: await _count(db.select(db.cards)),
      templates: await _count(db.select(db.templates)),
      images: imgFiles.length,
    );

    final archive = Archive();
    final manifestBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    archive.addFile(ArchiveFile('library.sqlite', dbBytes.length, dbBytes));
    for (final f in imgFiles) {
      final b = await f.readAsBytes();
      archive.addFile(ArchiveFile('images/${p.basename(f.path)}', b.length, b));
    }
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) throw StateError('ZipEncoder produced no output.');
    return Uint8List.fromList(zipped);
  }

  // ---- import ----

  /// Opens a file picker, reads + validates the backup, and returns it for the
  /// UI to confirm. Returns null if the user cancelled. Throws [BackupError]
  /// for a file that isn't a usable CardboardPress backup.
  Future<PickedBackup?> pickBackup() async {
    final res = await FilePicker.pickFiles(type: FileType.any);
    if (res == null || res.files.isEmpty) return null;
    final picked = res.files.single;
    // PlatformFile.readAsBytes() works on both mobile (stream) and desktop
    // (path-backed). The old .bytes field is deprecated in file_picker 12.x.
    final bytes = picked.path != null
        ? await File(picked.path!).readAsBytes()
        : await picked.readAsBytes();
    final manifest = _readManifest(bytes);
    return PickedBackup(bytes, manifest);
  }

  /// REPLACES the library with the backup. Destructive — call only after the
  /// user has confirmed. Returns what was restored.
  Future<RestoreSummary> restore(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    BackupManifest? manifest;
    Uint8List? snapshotBytes;
    final imageEntries = <MapEntry<String, List<int>>>[];

    for (final f in archive) {
      if (!f.isFile) continue;
      final content = f.content as List<int>;
      if (f.name == 'manifest.json') {
        manifest = BackupManifest.fromJson(
            jsonDecode(utf8.decode(content)) as Map<String, dynamic>);
      } else if (f.name == 'library.sqlite') {
        snapshotBytes = Uint8List.fromList(content);
      } else if (f.name.startsWith('images/')) {
        imageEntries.add(MapEntry(p.basename(f.name), content));
      }
    }
    _validate(manifest, snapshotBytes);

    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final snapFile = File(p.join(tmp.path, 'cbp_restore_$stamp.sqlite'));
    await snapFile.writeAsBytes(snapshotBytes!, flush: true);

    // Opening the snapshot migrates it to the current schema if it's older.
    final src = AppDatabase.forFile(snapFile);
    try {
      // 1) Lay the backup's images down FIRST (alongside the current ones), so
      //    once the DB flips to the backup's ids every referenced file exists.
      for (final e in imageEntries) {
        await images.putRaw(e.key, e.value);
      }
      // 2) Atomically swap the content in ONE batch (clear + insert): if any
      //    part fails, drift rolls the whole batch back, so the library is
      //    never left empty or half-restored. Watching providers refresh after.
      await _replaceContentFrom(src);
    } finally {
      await src.close();
    }
    // 3) Now that the DB points only at the backup's images, drop the rest.
    await images.retainOnly(imageEntries.map((e) => e.key).toSet());

    try {
      await snapFile.delete();
    } catch (_) {}

    return RestoreSummary(
      cards: manifest!.cards,
      templates: manifest.templates,
      images: imageEntries.length,
    );
  }

  BackupManifest _readManifest(Uint8List zipBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const BackupError('This file is not a valid .zip backup.');
    }
    for (final f in archive) {
      if (f.isFile && f.name == 'manifest.json') {
        try {
          final m = BackupManifest.fromJson(
              jsonDecode(utf8.decode(f.content as List<int>))
                  as Map<String, dynamic>);
          _validate(m, Uint8List(0), checkSnapshot: false);
          return m;
        } catch (e) {
          if (e is BackupError) rethrow;
          throw const BackupError('This backup is damaged or unreadable.');
        }
      }
    }
    throw const BackupError('This file is not a CardboardPress backup.');
  }

  void _validate(BackupManifest? manifest, Uint8List? snapshotBytes,
      {bool checkSnapshot = true}) {
    if (manifest == null || manifest.app != _kBackupApp) {
      throw const BackupError('This file is not a CardboardPress backup.');
    }
    if (checkSnapshot && (snapshotBytes == null || snapshotBytes.isEmpty)) {
      throw const BackupError('This backup is missing its library data.');
    }
    if (manifest.schemaVersion > db.schemaVersion) {
      throw const BackupError(
          'This backup was made by a newer version of CardboardPress. '
          'Update the app, then import it again.');
    }
  }

  // ---- shared table copy/clear (content tables only; AppSettings excluded) ----

  Future<int> _count(dynamic selectable) async =>
      (await selectable.get() as List).length;

  /// Restore's atomic swap: read every content row from [src], then in a single
  /// batch delete all live content and insert the backup's rows.
  Future<void> _replaceContentFrom(AppDatabase src) async {
    final palette = await src.select(src.paletteColors).get();
    final templates = await src.select(src.templates).get();
    final cards = await src.select(src.cards).get();
    final sets = await src.select(src.sets).get();
    final rarities = await src.select(src.rarities).get();
    final textSymbols = await src.select(src.textSymbols).get();
    final symbols = await src.select(src.symbols).get();
    final frames = await src.select(src.frames).get();
    Expression<bool> all(dynamic _) => const Constant(true);
    await db.batch((b) {
      b.deleteWhere(db.cards, all);
      b.deleteWhere(db.templates, all);
      b.deleteWhere(db.paletteColors, all);
      b.deleteWhere(db.sets, all);
      b.deleteWhere(db.rarities, all);
      b.deleteWhere(db.textSymbols, all);
      b.deleteWhere(db.symbols, all);
      b.deleteWhere(db.frames, all);
      b.insertAll(db.paletteColors, palette.map((r) => r.toCompanion(false)));
      b.insertAll(db.templates, templates.map((r) => r.toCompanion(false)));
      b.insertAll(db.cards, cards.map((r) => r.toCompanion(false)));
      b.insertAll(db.sets, sets.map((r) => r.toCompanion(false)));
      b.insertAll(db.rarities, rarities.map((r) => r.toCompanion(false)));
      b.insertAll(db.textSymbols, textSymbols.map((r) => r.toCompanion(false)));
      b.insertAll(db.symbols, symbols.map((r) => r.toCompanion(false)));
      b.insertAll(db.frames, frames.map((r) => r.toCompanion(false)));
    });
  }

  Future<void> _copyContent(AppDatabase from, AppDatabase to) async {
    // Read first (typed via inference — we never name the row classes, which
    // also sidesteps the Set/Symbol data-class name clashes), then batch-insert
    // as companions so it's robust across schema shapes.
    final palette = await from.select(from.paletteColors).get();
    final templates = await from.select(from.templates).get();
    final cards = await from.select(from.cards).get();
    final sets = await from.select(from.sets).get();
    final rarities = await from.select(from.rarities).get();
    final textSymbols = await from.select(from.textSymbols).get();
    final symbols = await from.select(from.symbols).get();
    final frames = await from.select(from.frames).get();
    await to.batch((b) {
      b.insertAll(to.paletteColors, palette.map((r) => r.toCompanion(false)));
      b.insertAll(to.templates, templates.map((r) => r.toCompanion(false)));
      b.insertAll(to.cards, cards.map((r) => r.toCompanion(false)));
      b.insertAll(to.sets, sets.map((r) => r.toCompanion(false)));
      b.insertAll(to.rarities, rarities.map((r) => r.toCompanion(false)));
      b.insertAll(to.textSymbols, textSymbols.map((r) => r.toCompanion(false)));
      b.insertAll(to.symbols, symbols.map((r) => r.toCompanion(false)));
      b.insertAll(to.frames, frames.map((r) => r.toCompanion(false)));
    });
  }

  Future<void> _clearContent(AppDatabase d) async {
    await d.delete(d.cards).go();
    await d.delete(d.templates).go();
    await d.delete(d.paletteColors).go();
    await d.delete(d.sets).go();
    await d.delete(d.rarities).go();
    await d.delete(d.textSymbols).go();
    await d.delete(d.symbols).go();
    await d.delete(d.frames).go();
  }
}
