// lib/data/text_symbol_repository.dart
//
// Data API for inline text symbols (spec §3.2). Management UI lives in
// Customization; this exposes the live list plus add/rename/replace/delete so
// that screen can bind to it. The renderer reads the tag -> imageId map
// (textSymbolMapProvider) and decodes the images like any other art.

import 'package:drift/drift.dart' show Value;

import '../model/card_model.dart';
import 'database.dart';

class TextSymbolRepository {
  final AppDatabase _db;
  TextSymbolRepository(this._db);

  Stream<List<TextSymbolEntry>> watch() => _db.watchTextSymbols().map((rows) =>
      rows
          .map((r) => TextSymbolEntry(
                id: r.id,
                tag: r.tag,
                imageId: r.imageId,
                position: r.position,
              ))
          .toList());

  /// Add a new symbol. [imageId] must already be in the ImageStore.
  Future<void> add({required String tag, required String imageId}) async {
    final pos = await _db.maxTextSymbolPosition() + 1;
    await _db.insertTextSymbol(TextSymbolsCompanion.insert(
      id: 'ts_${DateTime.now().microsecondsSinceEpoch}',
      tag: tag.trim(),
      imageId: imageId,
      position: Value(pos),
    ));
  }

  Future<void> rename(String id, String tag) => _db.updateTextSymbolRow(
      id, TextSymbolsCompanion(tag: Value(tag.trim())));

  Future<void> replaceImage(String id, String imageId) => _db
      .updateTextSymbolRow(id, TextSymbolsCompanion(imageId: Value(imageId)));

  Future<void> delete(String id) => _db.deleteTextSymbol(id);
}
