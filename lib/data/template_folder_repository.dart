// lib/data/template_folder_repository.dart
//
// Data API for template-browser folders. Mirrors SetRepository: rows map to
// domain TemplateFolderEntry objects so features never see database types.
//
// Deleting a folder is deliberately NOT a cascade — the row goes away and the
// caller decides what happens to its templates (delete them, or keep them and
// unfile via TemplateRepository.setFolder(id, '')), the same three-way choice
// the Collection offers when deleting a set.

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import 'database.dart';

class TemplateFolderRepository {
  final AppDatabase _db;
  TemplateFolderRepository(this._db);

  Stream<List<TemplateFolderEntry>> watch() =>
      _db.watchTemplateFolders().map((rows) => rows
          .map((r) => TemplateFolderEntry(
              id: r.id, name: r.name, position: r.position))
          .toList());

  Future<String> create(String name) async {
    final id = 'tf_${DateTime.now().microsecondsSinceEpoch}';
    final pos = await _db.maxTemplateFolderPosition() + 1;
    await _db.insertTemplateFolder(TemplateFoldersCompanion.insert(
      id: id,
      name: name.trim().isEmpty ? 'New folder' : name.trim(),
      position: Value(pos),
    ));
    return id;
  }

  /// [create], de-duplicating the display name ("Basics" → "Basics (2)"),
  /// case-insensitively — same rule as template names.
  Future<String> createWithUniqueName(String name) async {
    final base = name.trim().isEmpty ? 'New folder' : name.trim();
    final existing = (await _db.watchTemplateFolders().first)
        .map((r) => r.name.trim().toLowerCase())
        .toSet();
    var candidate = base;
    for (var n = 2; existing.contains(candidate.toLowerCase()); n++) {
      candidate = '$base ($n)';
    }
    return create(candidate);
  }

  Future<void> rename(String id, String name) => _db.updateTemplateFolder(
        id,
        TemplateFoldersCompanion(
          name: Value(name.trim().isEmpty ? 'New folder' : name.trim()),
        ),
      );

  /// Removes the folder row ONLY. Its templates keep pointing at a folder id
  /// that no longer resolves, so callers must first delete them or unfile them
  /// — the browser's delete flow does exactly that.
  Future<void> delete(String id) => _db.deleteTemplateFolder(id);
}
