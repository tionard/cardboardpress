// lib/data/image_store.dart
//
// Stores picked art as files in the app's documents directory and refers to
// them by a generated id (the filename). Cards keep only the id in their JSON
// content, so the database stays small and images live on disk.

import 'dart:io';
import 'dart:typed_data';

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
  /// stable filename (e.g. for seeded defaults); otherwise one is generated.
  Future<String> save(Uint8List bytes, {String ext = 'png', String? id}) async {
    final name = id ?? 'img_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final file = File(p.join((await _dir()).path, name));
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
