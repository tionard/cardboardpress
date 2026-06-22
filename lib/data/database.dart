// lib/data/database.dart
//
// The drift database (your EF Core DbContext). Table classes are entities;
// schemaVersion + migration are explicit, hand-written migrations.

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../model/card_model.dart';
import '../model/sample_card.dart';
import 'converters.dart';

part 'database.g.dart';

/// A reusable palette colour (spec §3.1). Single colour => [c2] is null.
class PaletteColors extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get c1 => integer()();
  IntColumn get c2 => integer().nullable()();
  TextColumn get orientation =>
      text().withDefault(const Constant('vertical'))();
  RealColumn get mix => real().withDefault(const Constant(0.3))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  // Usage tags: which contexts a colour picker shows this swatch in by default.
  // They filter, never forbid — every picker offers "show all". Default all-on,
  // so existing swatches behave exactly as before until a user curates them.
  BoolColumn get tagCard => boolean().withDefault(const Constant(true))();
  BoolColumn get tagText => boolean().withDefault(const Constant(true))();
  BoolColumn get tagSymbol => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A template: identity + ordered layout stored as one JSON column.
class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get spec => text().map(const TemplateSpecConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// A card (spec §3). The template is a reference: [templateId] is a real FK
/// (nulled if the template is deleted), and [templateSnapshot] retains the last
/// layout so the card always renders. [content] is the authored per-field data.
class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()
      .nullable()
      .references(Templates, #id, onDelete: KeyAction.setNull)();
  TextColumn get templateSnapshot =>
      text().map(const TemplateSpecConverter())();
  TextColumn get content => text().map(const CardContentConverter())();
  TextColumn get foil => text().withDefault(const Constant('none'))();
  TextColumn get setId => text().nullable()(); // null => Unassigned
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A set / Collection folder (spec §3, §4). Unassigned is not stored.
@DataClassName('CardSet')
class Sets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get abbreviation => text().withDefault(const Constant(''))();
  IntColumn get year => integer().withDefault(const Constant(2026))();
  TextColumn get owner => text().withDefault(const Constant(''))();
  BoolColumn get numbering => boolean().withDefault(const Constant(true))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get symbolId => text().nullable()(); // chosen set symbol; null => none

  @override
  Set<Column> get primaryKey => {id};
}

/// A rarity (spec §3). Name + abbreviation (the footer uses the abbreviation),
/// fully editable in Customization → Rarities. Palette colour + transparency +
/// snapshot ref arrive alongside the set-symbol tint (its only render site).
@DataClassName('Rarity')
class Rarities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get abbreviation => text().withDefault(const Constant(''))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get color => text().nullable()(); // serialized ColorRef; null => none

  @override
  Set<Column> get primaryKey => {id};
}

/// An inline text symbol (spec §3.2): a {tag} mapped to a glyph image stored in
/// the ImageStore. Managed in Customization; referenced from Cost/Rules content.
class TextSymbols extends Table {
  TextColumn get id => text()();
  TextColumn get tag => text()();
  TextColumn get imageId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A standalone symbol (spec §3.3): a graphic used ONLY as a set symbol or a
/// watermark. Not inline, not composable — just a name + image. Any colour tint
/// is applied at the render site, never stored here. Managed in Customization →
/// Symbols. (Data class is named SymbolRow to avoid clashing with dart:core's
/// Symbol type, the same trick Sets uses with CardSet.)
@DataClassName('SymbolRow')
class Symbols extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get imageId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
    tables: [PaletteColors, Templates, Cards, Sets, Rarities, TextSymbols, Symbols])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cardboardpress'));

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultColors();
          await _seedDefaultTemplates();
          await _seedSampleCards();
          await _seedDefaultSets();
          await _seedDefaultRarities();
          // Default text symbols are image-backed, so they're seeded at startup
          // (see seedDefaultTextSymbols) rather than here in the DB layer.
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(templates);
            await _seedDefaultTemplates();
          }
          if (from < 3) {
            // v?→v3: add Cards. Also re-seed the default templates so their
            // stored layout includes the new per-field ids (safe: no template
            // editor exists yet, so only the defaults are present).
            await m.createTable(cards);
            await delete(templates).go();
            await _seedDefaultTemplates();
            await _seedSampleCards();
          }
          if (from < 4) {
            await m.createTable(sets);
            await _seedDefaultSets();
          }
          if (from < 5) {
            await m.createTable(rarities);
            await _seedDefaultRarities();
          }
          if (from < 6) {
            await m.createTable(textSymbols);
            // Rows + glyph images are seeded at startup, not here.
          }
          if (from < 7) {
            // v6→v7: add standalone Symbols (set symbol / watermark library).
            // Starts empty; any image-backed defaults would seed at startup
            // (like text symbols), never inside a migration.
            await m.createTable(symbols);
          }
          if (from < 8) {
            // v7→v8: a Set can now point at one of those symbols (its set
            // symbol). Existing sets default to none (null).
            await m.addColumn(sets, sets.symbolId);
          }
          if (from < 9) {
            // v8→v9: a rarity can carry a palette colour that tints the set
            // symbol. Existing rarities default to none (null).
            await m.addColumn(rarities, rarities.color);
          }
          if (from < 10) {
            // v9→v10: per-swatch usage tags (card / text / symbol). They filter
            // pickers, never forbid. Existing swatches default to all-on, so
            // nothing changes until a user curates them.
            await m.addColumn(paletteColors, paletteColors.tagCard);
            await m.addColumn(paletteColors, paletteColors.tagText);
            await m.addColumn(paletteColors, paletteColors.tagSymbol);
          }
        },
        beforeOpen: (details) async {
          // Enforce the card→template foreign key (SQLite needs this per-conn).
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---- palette colours ----

  Stream<List<PaletteColor>> watchColors() =>
      (select(paletteColors)
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<void> insertColor(PaletteColorsCompanion c) =>
      into(paletteColors).insert(c);

  Future<void> updateColor(String id, PaletteColorsCompanion c) =>
      (update(paletteColors)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteColor(String id) =>
      (delete(paletteColors)..where((t) => t.id.equals(id))).go();

  Future<int> maxColorPosition() async {
    final rows = await select(paletteColors).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _seedDefaultColors() async {
    final defaults = <PaletteColorsCompanion>[
      PaletteColorsCompanion.insert(
          id: 'c_ruby', name: 'Ruby', c1: 0xFFD64545, position: const Value(0)),
      PaletteColorsCompanion.insert(
          id: 'c_amber', name: 'Amber', c1: 0xFFE0A33A, position: const Value(1)),
      PaletteColorsCompanion.insert(
          id: 'c_leaf', name: 'Leaf', c1: 0xFF6FAE6F, position: const Value(2)),
      PaletteColorsCompanion.insert(
          id: 'c_sky', name: 'Sky', c1: 0xFF4F8FD6, position: const Value(3)),
      PaletteColorsCompanion.insert(
          id: 'c_plum', name: 'Plum', c1: 0xFF8A5CB0, position: const Value(4)),
      PaletteColorsCompanion.insert(
          id: 'c_ink', name: 'Ink', c1: 0xFF2C2B27, position: const Value(5)),
      PaletteColorsCompanion.insert(
          id: 'c_paper', name: 'Paper', c1: 0xFFF1EFE8, position: const Value(6)),
      PaletteColorsCompanion.insert(
        id: 'c_forest',
        name: 'Forest Fade',
        c1: 0xFF8FAE6F,
        c2: const Value(0xFF2E6E4E),
        orientation: const Value('vertical'),
        mix: const Value(0.5),
        position: const Value(7),
      ),
    ];
    await batch((b) => b.insertAll(paletteColors, defaults));
  }

  // ---- templates ----

  Stream<List<Template>> watchTemplates() =>
      (select(templates)
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<void> insertTemplate(TemplatesCompanion c) =>
      into(templates).insert(c);

  Future<void> updateTemplateRow(String id, TemplatesCompanion c) =>
      (update(templates)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteTemplate(String id) =>
      (delete(templates)..where((t) => t.id.equals(id))).go();

  Future<int> maxTemplatePosition() async {
    final rows = await select(templates).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _seedDefaultTemplates() async {
    final defaults = defaultTemplates();
    await batch((b) {
      for (var i = 0; i < defaults.length; i++) {
        b.insert(
          templates,
          TemplatesCompanion.insert(
            id: defaults[i].id,
            name: defaults[i].name,
            spec: defaults[i].data,
            position: Value(i),
          ),
        );
      }
    });
  }

  // ---- cards ----

  Stream<List<Card>> watchCards() =>
      (select(cards)..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<void> upsertCard(CardsCompanion c) =>
      into(cards).insertOnConflictUpdate(c);

  Future<void> updateCardSet(String id, String? setId) =>
      (update(cards)..where((t) => t.id.equals(id)))
          .write(CardsCompanion(setId: Value(setId)));

  Future<void> deleteCard(String id) =>
      (delete(cards)..where((t) => t.id.equals(id))).go();

  Future<void> _seedSampleCards() async {
    final thornwood =
        defaultTemplates().firstWhere((t) => t.id == 't_thornwood').data;
    await into(cards).insert(
      CardsCompanion.insert(
        id: 'card_sample',
        templateId: const Value('t_thornwood'),
        templateSnapshot: thornwood,
        content: sampleContent(),
        foil: const Value('holo'),
        position: const Value(0),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  // ---- sets ----

  Stream<List<CardSet>> watchSets() =>
      (select(sets)..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<void> createSet(SetsCompanion c) => into(sets).insert(c);

  Future<void> updateSet(String id, SetsCompanion c) =>
      (update(sets)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteSet(String id) =>
      (delete(sets)..where((t) => t.id.equals(id))).go();

  Future<int> maxSetPosition() async {
    final rows = await select(sets).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _seedDefaultSets() async {
    await into(sets).insert(
      SetsCompanion.insert(
        id: 's_core',
        name: 'Core Set',
        abbreviation: const Value('CORE'),
        year: const Value(2026),
        position: const Value(0),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  // ---- rarities ----

  Stream<List<Rarity>> watchRarities() =>
      (select(rarities)..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<void> insertRarity(RaritiesCompanion c) =>
      into(rarities).insert(c, mode: InsertMode.insertOrIgnore);

  Future<void> updateRarityRow(String id, RaritiesCompanion c) =>
      (update(rarities)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteRarity(String id) =>
      (delete(rarities)..where((t) => t.id.equals(id))).go();

  Future<int> maxRarityPosition() async {
    final rows = await select(rarities).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _seedDefaultRarities() async {
    const defaults = [
      ('r_common', 'Common', 'C', 0),
      ('r_uncommon', 'Uncommon', 'U', 1),
      ('r_rare', 'Rare', 'R', 2),
      ('r_token', 'Token', 'T', 3),
    ];
    await batch((b) {
      for (final (id, name, abbr, pos) in defaults) {
        b.insert(
          rarities,
          RaritiesCompanion.insert(
            id: id,
            name: name,
            abbreviation: Value(abbr),
            position: Value(pos),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  // ---- text symbols ----

  Stream<List<TextSymbol>> watchTextSymbols() => (select(textSymbols)
        ..orderBy([(t) => OrderingTerm(expression: t.position)]))
      .watch();

  Future<int> countTextSymbols() async =>
      (await select(textSymbols).get()).length;

  Future<void> insertTextSymbol(TextSymbolsCompanion c) =>
      into(textSymbols).insert(c, mode: InsertMode.insertOrIgnore);

  Future<void> updateTextSymbolRow(String id, TextSymbolsCompanion c) =>
      (update(textSymbols)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteTextSymbol(String id) =>
      (delete(textSymbols)..where((t) => t.id.equals(id))).go();

  Future<int> maxTextSymbolPosition() async {
    final rows = await select(textSymbols).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }

  // ---- standalone symbols ----

  Stream<List<SymbolRow>> watchSymbols() => (select(symbols)
        ..orderBy([(t) => OrderingTerm(expression: t.position)]))
      .watch();

  Future<void> insertSymbol(SymbolsCompanion c) =>
      into(symbols).insert(c, mode: InsertMode.insertOrIgnore);

  Future<void> updateSymbolRow(String id, SymbolsCompanion c) =>
      (update(symbols)..where((t) => t.id.equals(id))).write(c);

  Future<void> deleteSymbol(String id) =>
      (delete(symbols)..where((t) => t.id.equals(id))).go();

  Future<int> maxSymbolPosition() async {
    final rows = await select(symbols).get();
    if (rows.isEmpty) return -1;
    return rows.map((r) => r.position).reduce((a, b) => a > b ? a : b);
  }
}
