// lib/data/set_repository.dart
//
// Data API for sets. Maps rows to SetEntry; "Unassigned" is not a row (it's the
// null-setId bucket), so it's never returned here.

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import 'database.dart';

class SetRepository {
  final AppDatabase _db;
  SetRepository(this._db);

  Stream<List<SetEntry>> watch() => _db.watchSets().map((rows) => rows
      .map((r) => SetEntry(
            id: r.id,
            name: r.name,
            abbreviation: r.abbreviation,
            year: r.year,
            owner: r.owner,
            numbering: r.numbering,
            position: r.position,
          ))
      .toList());

  Future<String> create(String name, {String abbreviation = ''}) async {
    final id = 's_${DateTime.now().microsecondsSinceEpoch}';
    final pos = await _db.maxSetPosition() + 1;
    await _db.createSet(SetsCompanion.insert(
      id: id,
      name: name.trim().isEmpty ? 'New set' : name.trim(),
      abbreviation: Value(abbreviation.trim()),
      position: Value(pos),
    ));
    return id;
  }

  Future<void> delete(String id) => _db.deleteSet(id);
}
