// lib/data/image_store.dart
//
// Stores picked art as files in the app's documents directory and refers to
// them by a generated id (the filename). Cards keep only the id in their JSON
// content, so the database stays small and images live on disk.
//
// Uploads are CONTENT-ADDRESSED: the generated id is the SHA-256 of the bytes,
// so uploading the same artwork twice — on two cards, or after a delete —
// lands on the SAME file and the second upload costs nothing. Two rules keep
// this sound: ids are immutable (an edited image is a new upload → new hash →
// new id), and nothing may delete a file just because one owner released it —
// files are shared, so cleanup is the startup garbage collector's job
// (image_gc.dart → [sweepUnreferenced]). Explicit-id saves (seeded defaults,
// backup restore) bypass hashing to keep their stable names.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStore {
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cardboardpress', 'images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Write [bytes] and return the image id (filename). Pass [id] to use a
  /// stable filename (e.g. for seeded defaults); otherwise the id is the
  /// SHA-256 of the bytes, so identical content dedups to one file — if the
  /// hash is already stored, the existing id is returned without writing.
  Future<String> save(Uint8List bytes, {String ext = 'png', String? id}) async {
    final dir = await _dir();
    if (id != null) {
      final file = File(p.join(dir.path, id));
      await file.writeAsBytes(bytes, flush: true);
      return id;
    }
    final hash = sha256.convert(bytes).toString();
    final name = 'img_$hash.$ext';
    final file = File(p.join(dir.path, name));
    if (await file.exists()) return name;
    // Same content can arrive labelled with a different extension; the hash
    // is what identifies it, so an existing sibling still counts as a hit.
    final prefix = 'img_$hash.';
    await for (final e in dir.list()) {
      if (e is File && p.basename(e.path).startsWith(prefix)) {
        return p.basename(e.path);
      }
    }
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<Uint8List?> load(String id) async {
    final file = File(p.join((await _dir()).path, id));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String id) async {
    final file = File(p.join((await _dir()).path, id));
    if (await file.exists()) await file.delete();
  }

  // ---- backup / restore helpers ----

  /// Every stored image file (for backup).
  Future<List<File>> allFiles() async {
    final dir = await _dir();
    final entries = await dir.list().toList();
    return entries.whereType<File>().toList();
  }

  /// Write [bytes] under an exact [name] — restore preserves image ids.
  Future<void> putRaw(String name, List<int> bytes) async {
    final file = File(p.join((await _dir()).path, name));
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Garbage-collection sweep: delete stored images whose filename is not in
  /// [keep] — EXCEPT files modified within the last hour. The recency guard
  /// closes the race where an upload lands between the caller computing its
  /// keep-set and this sweep running; a genuinely orphaned file is simply
  /// collected on a later run instead. Returns how many files were deleted.
  Future<int> sweepUnreferenced(Set<String> keep) async {
    final dir = await _dir();
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    var removed = 0;
    for (final e in await dir.list().toList()) {
      if (e is! File || keep.contains(p.basename(e.path))) continue;
      try {
        if ((await e.stat()).modified.isAfter(cutoff)) continue;
        await e.delete();
        removed++;
      } catch (_) {
        // A locked/vanished file is skipped, never fatal.
      }
    }
    return removed;
  }

  /// Delete every stored image whose filename is not in [keep] (restore's
  /// replace step, run only after the DB already points at the kept ids).
  Future<void> retainOnly(Set<String> keep) async {
    final dir = await _dir();
    for (final e in await dir.list().toList()) {
      if (e is File && !keep.contains(p.basename(e.path))) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }
}
