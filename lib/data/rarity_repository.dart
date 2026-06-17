// lib/data/rarity_repository.dart
//
// Data API for rarities. Read-only for now (defaults are seeded); create/edit
// arrives with a rarity editor.

import '../model/card_model.dart';
import 'database.dart';

class RarityRepository {
  final AppDatabase _db;
  RarityRepository(this._db);

  Stream<List<RarityEntry>> watch() => _db.watchRarities().map((rows) => rows
      .map((r) => RarityEntry(
            id: r.id,
            name: r.name,
            abbreviation: r.abbreviation,
            position: r.position,
          ))
      .toList());
}
