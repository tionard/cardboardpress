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

  /// Create a new, empty card on [templateId]/[templateSnapshot] in [setId]
  /// (null => Unassigned). Returns the new card id.
  Future<String> create({
    required String? templateId,
    required TemplateData templateSnapshot,
    String? setId,
  }) async {
    final id = 'card_${DateTime.now().microsecondsSinceEpoch}';
    await _db.upsertCard(CardsCompanion.insert(
      id: id,
      templateId: Value(templateId),
      templateSnapshot: templateSnapshot,
      content: const CardContent(),
      foil: const Value('none'),
      setId: Value(setId),
    ));
    return id;
  }

  /// Duplicate [e] (into [setId], defaulting to the original's set).
  Future<String> duplicate(CardEntry e, {String? setId}) async {
    final id = 'card_${DateTime.now().microsecondsSinceEpoch}';
    await _db.upsertCard(CardsCompanion.insert(
      id: id,
      templateId: Value(e.templateId),
      templateSnapshot: e.templateSnapshot,
      content: e.content,
      foil: Value(foilToName(e.foil)),
      setId: Value(setId ?? e.setId),
    ));
    return id;
  }

  Future<void> delete(String id) => _db.deleteCard(id);

  /// Delete a batch of cards atomically.
  Future<void> deleteMany(List<String> ids) => _db.deleteCards(ids);

  Future<void> setSet(String id, String? setId) => _db.updateCardSet(id, setId);

  /// Persist a new order for the cards in [setId] (null => Unassigned).
  /// [idsInNewOrder] is that set's cards in the order they should appear; the
  /// renderer's collector numbers follow this order when the set has numbering on.
  Future<void> reorderInSet(String? setId, List<String> idsInNewOrder) =>
      _db.reorderCardsInSet(setId, idsInNewOrder);

  CardEntry _toEntry(Card r) => CardEntry(
        id: r.id,
        templateId: r.templateId,
        templateSnapshot: r.templateSnapshot, // TemplateData (via converter)
        content: r.content, // CardContent (via converter)
        foil: foilFromName(r.foil),
        setId: r.setId,
      );
}
