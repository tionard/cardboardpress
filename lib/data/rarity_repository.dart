// lib/data/rarity_repository.dart
//
// Data API for rarities (spec §3.4). The repository is the data layer's public
// surface: features talk to this, never to drift directly. It maps drift rows
// (Rarity / RaritiesCompanion) to the domain type (RarityEntry) and exposes the
// live list plus add / edit / delete / reorder for the Customization UI.
//
// Today a rarity is just name + 1–3-letter abbreviation (the footer renders the
// abbreviation). Its palette colour + transparency join later, alongside the
// set-symbol tint that is the colour's only render site.

import 'package:drift/drift.dart' show Value;

import '../model/card_model.dart';
import 'database.dart';

class RarityRepository {
  final AppDatabase _db;
  RarityRepository(this._db);

  /// Live, ordered rarities. Re-emits on any change to the table.
  Stream<List<RarityEntry>> watch() => _db.watchRarities().map((rows) => rows
      .map((r) => RarityEntry(
            id: r.id,
            name: r.name,
            abbreviation: r.abbreviation,
            position: r.position,
          ))
      .toList());

  /// Append a new rarity at the end of the list.
  Future<void> add({required String name, String abbreviation = ''}) async {
    final pos = await _db.maxRarityPosition() + 1;
    final clean = name.trim();
    await _db.insertRarity(RaritiesCompanion.insert(
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
      name: clean.isEmpty ? 'New Rarity' : clean,
      abbreviation: Value(normalizeAbbreviation(abbreviation)),
      position: Value(pos),
    ));
  }

  /// Persist edits to an existing rarity. Pass only the fields that changed;
  /// position is preserved unless you set it (see [swap]).
  Future<void> update(
    String id, {
    String? name,
    String? abbreviation,
  }) {
    final n = name?.trim();
    return _db.updateRarityRow(
      id,
      RaritiesCompanion(
        name: (n == null) ? const Value.absent() : Value(n.isEmpty ? 'Unnamed' : n),
        abbreviation: (abbreviation == null)
            ? const Value.absent()
            : Value(normalizeAbbreviation(abbreviation)),
      ),
    );
  }

  Future<void> delete(String id) => _db.deleteRarity(id);

  /// Swap the positions of two rarities (the up/down reorder in the UI).
  Future<void> swap(RarityEntry a, RarityEntry b) async {
    await _db
        .updateRarityRow(a.id, RaritiesCompanion(position: Value(b.position)));
    await _db
        .updateRarityRow(b.id, RaritiesCompanion(position: Value(a.position)));
  }
}

/// Spec §3.4: an abbreviation is 1–3 letters. Keep only letters, cap at 3, and
/// upper-case so the footer reads consistently (C / U / R / T …).
String normalizeAbbreviation(String input) {
  final letters = input.replaceAll(RegExp('[^A-Za-z]'), '');
  final capped = letters.length > 3 ? letters.substring(0, 3) : letters;
  return capped.toUpperCase();
}
