// lib/data/template_repository.dart
//
// Data API for templates. Maps drift rows to domain TemplateEntry objects so
// features never see the database types. Read-only for now; create/edit lands
// with the Template Editor.

import '../model/card_model.dart';
import 'database.dart';

class TemplateRepository {
  final AppDatabase _db;
  TemplateRepository(this._db);

  Stream<List<TemplateEntry>> watch() => _db.watchTemplates().map((rows) => rows
      .map((r) => TemplateEntry(id: r.id, name: r.name, data: r.spec))
      .toList());
}
