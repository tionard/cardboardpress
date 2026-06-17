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
      .map((r) => TemplateEntry(id: r.id, name: r.name, data: r.spec))
      .toList());

  Future<String> create(String name, TemplateData data) async {
    final id = 't_${DateTime.now().microsecondsSinceEpoch}';
    final pos = await _db.maxTemplatePosition() + 1;
    await _db.insertTemplate(TemplatesCompanion.insert(
      id: id,
      name: name.trim().isEmpty ? 'New template' : name.trim(),
      spec: data,
      position: Value(pos),
    ));
    return id;
  }

  Future<void> save(TemplateEntry e) => _db.updateTemplateRow(
        e.id,
        TemplatesCompanion(name: Value(e.name), spec: Value(e.data)),
      );

  /// Delete the template. Cards referencing it have their templateId nulled by
  /// the foreign key and fall back to their retained snapshot.
  Future<void> delete(String id) => _db.deleteTemplate(id);
}
