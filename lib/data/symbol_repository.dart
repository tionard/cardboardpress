// lib/data/symbol_repository.dart
//
// Data API for standalone symbols (spec §3.3): the graphics used as a set
// symbol or a watermark. Managed in Customization → Symbols; this exposes the
// live list plus add / rename / replace-image / delete so that screen can bind
// to it. Unlike text symbols there is no {tag} — a standalone symbol is chosen
// from a list by name, not referenced inline, and never composed.
//
// A symbol is just a name + an image id (into the ImageStore). Colour tinting
// happens at the render site (rarity colour on a set symbol, palette colour on
// a watermark), so nothing colour-related is stored here.

import 'package:drift/drift.dart' show Value;

import '../model/card_model.dart';
import 'database.dart';

class SymbolRepository {
  final AppDatabase _db;
  SymbolRepository(this._db);

  /// Live, ordered symbols. Re-emits on any change to the table.
  Stream<List<SymbolEntry>> watch() => _db.watchSymbols().map((rows) => rows
      .map((r) => SymbolEntry(
            id: r.id,
            name: r.name,
            imageId: r.imageId,
            position: r.position,
          ))
      .toList());

  /// Add a new symbol. [imageId] must already be in the ImageStore.
  Future<void> add({required String name, required String imageId}) async {
    final pos = await _db.maxSymbolPosition() + 1;
    final clean = name.trim();
    await _db.insertSymbol(SymbolsCompanion.insert(
      id: 'sym_${DateTime.now().microsecondsSinceEpoch}',
      name: clean.isEmpty ? 'Untitled' : clean,
      imageId: imageId,
      position: Value(pos),
    ));
  }

  Future<void> rename(String id, String name) {
    final n = name.trim();
    return _db.updateSymbolRow(
        id, SymbolsCompanion(name: Value(n.isEmpty ? 'Untitled' : n)));
  }

  Future<void> replaceImage(String id, String imageId) =>
      _db.updateSymbolRow(id, SymbolsCompanion(imageId: Value(imageId)));

  Future<void> delete(String id) => _db.deleteSymbol(id);
}
