// lib/data/card_repository.dart
//
// Data API for cards. Maps drift rows <-> domain CardEntry, hiding companions,
// converters, and the foil<->string encoding from features.

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import '../model/serialization.dart' show foilFromName, foilToName;
import 'database.dart';

class CardRepository {
  final AppDatabase _db;
  CardRepository(this._db);

  Stream<List<CardEntry>> watch() =>
      _db.watchCards().map((rows) => rows.map(_toEntry).toList());

  /// Insert-or-update the card. Only the columns we set are written; position
  /// and setId are left absent so an update preserves them.
  Future<void> save(CardEntry e) => _db.upsertCard(
        CardsCompanion(
          id: Value(e.id),
          templateId: Value(e.templateId),
          templateSnapshot: Value(e.templateSnapshot),
          content: Value(e.content),
          foil: Value(foilToName(e.foil)),
        ),
      );

  CardEntry _toEntry(Card r) => CardEntry(
        id: r.id,
        templateId: r.templateId,
        templateSnapshot: r.templateSnapshot, // TemplateData (via converter)
        content: r.content, // CardContent (via converter)
        foil: foilFromName(r.foil),
      );
}
