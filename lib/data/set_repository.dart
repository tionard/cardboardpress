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
            symbolId: r.symbolId,
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

  /// Update any subset of a set's footer-feeding fields. Only the arguments you
  /// pass are written (the rest stay `Value.absent()` so an update preserves
  /// them) — the same partial-update shape the card repository uses.
  Future<void> update(
    String id, {
    String? name,
    String? abbreviation,
    int? year,
    String? owner,
    bool? numbering,
  }) =>
      _db.updateSet(
        id,
        SetsCompanion(
          name: name == null
              ? const Value.absent()
              : Value(name.trim().isEmpty ? 'New set' : name.trim()),
          abbreviation: abbreviation == null
              ? const Value.absent()
              : Value(abbreviation.trim()),
          year: year == null ? const Value.absent() : Value(year),
          owner: owner == null ? const Value.absent() : Value(owner.trim()),
          numbering: numbering == null ? const Value.absent() : Value(numbering),
        ),
      );

  /// Choose (or clear, when [symbolId] is null) this set's set symbol.
  Future<void> setSymbol(String id, String? symbolId) =>
      _db.updateSet(id, SetsCompanion(symbolId: Value(symbolId)));

  Future<void> delete(String id) => _db.deleteSet(id);
}
