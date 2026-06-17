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

  /// Write [bytes] and return the generated image id (filename).
  Future<String> save(Uint8List bytes, {String ext = 'png'}) async {
    final id = 'img_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final file = File(p.join((await _dir()).path, id));
    await file.writeAsBytes(bytes, flush: true);
    return id;
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
}
