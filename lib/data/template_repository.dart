// lib/data/template_repository.dart
//
// Data API for templates. Maps drift rows to domain TemplateEntry objects so
// features never see the database types.

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import 'database.dart';

class TemplateRepository {
  final AppDatabase _db;
  TemplateRepository(this._db);

  Stream<List<TemplateEntry>> watch() => _db.watchTemplates().map((rows) => rows
      .map((r) => TemplateEntry(
          id: r.id, name: r.name, data: r.spec, folder: r.folder))
      .toList());

  Future<String> create(String name, TemplateData data,
      {String folder = ''}) async {
    final id = 't_${DateTime.now().microsecondsSinceEpoch}';
    final pos = await _db.maxTemplatePosition() + 1;
    await _db.insertTemplate(TemplatesCompanion.insert(
      id: id,
      name: name.trim().isEmpty ? 'New template' : name.trim(),
      spec: data,
      position: Value(pos),
      folder: Value(folder.trim()),
    ));
    return id;
  }

  /// [create], but de-duplicating the display name against existing templates:
  /// "Wings" → "Wings (2)" → "Wings (3)"… (trimmed, case-insensitive compare).
  /// Used by template-JSON import and by Duplicate, where colliding names are
  /// expected rather than exceptional.
  Future<String> createWithUniqueName(String name, TemplateData data,
      {String folder = ''}) async {
    final base = name.trim().isEmpty ? 'New template' : name.trim();
    // One-shot read: a drift watch stream emits the current rows immediately.
    final existing = (await _db.watchTemplates().first)
        .map((r) => r.name.trim().toLowerCase())
        .toSet();
    var candidate = base;
    for (var n = 2; existing.contains(candidate.toLowerCase()); n++) {
      candidate = '$base ($n)';
    }
    return create(candidate, data, folder: folder);
  }

  /// Save name + layout. Deliberately does NOT write `folder` — filing is
  /// changed only through [setFolder], so an editor save can never clobber it.
  Future<void> save(TemplateEntry e) => _db.updateTemplateRow(
        e.id,
        TemplatesCompanion(name: Value(e.name), spec: Value(e.data)),
      );

  /// File a template into [folder] ('' = ungrouped). A folder needs no
  /// creation step and disappears when its last template leaves.
  Future<void> setFolder(String id, String folder) => _db.updateTemplateRow(
        id,
        TemplatesCompanion(folder: Value(folder.trim())),
      );

  /// Delete the template. Cards referencing it have their templateId nulled by
  /// the foreign key and fall back to their retained snapshot.
  Future<void> delete(String id) => _db.deleteTemplate(id);
}
