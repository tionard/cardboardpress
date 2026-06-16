// lib/data/database.dart
//
// The drift database. You declare TABLES as Dart classes; the build_runner
// generator reads them and writes `database.g.dart` containing the real query
// code, the row type (`PaletteColor`), and insert helpers (`...Companion`).
//
// For a C# dev: this class is your EF Core `DbContext`, the Table classes are
// your entities, and `schemaVersion` + `migration` are explicit, hand-written
// migrations (no magic — you control exactly what runs when the schema changes).

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Links this file to the generated half. Until you run the generator, the
// editor will show errors about `_$AppDatabase` / `PaletteColor` — that's
// expected; they vanish once `database.g.dart` exists.
part 'database.g.dart';

/// A reusable palette colour (spec §3.1). Single colour => [c2] is null.
/// Colours are stored OPAQUE (alpha = FF); transparency is applied at the use
/// site, never stored here.
class PaletteColors extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get c1 => integer()(); // ARGB int, e.g. 0xFFD64545
  IntColumn get c2 => integer().nullable()(); // null => single colour
  TextColumn get orientation =>
      text().withDefault(const Constant('vertical'))(); // 'vertical'|'horizontal'
  RealColumn get mix => real().withDefault(const Constant(0.3))(); // 0..1
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [PaletteColors])
class AppDatabase extends _$AppDatabase {
  // drift_flutter's `driftDatabase` opens (or creates) a `cardboardpress.sqlite`
  // file in the app's documents directory, picking the right native engine per
  // platform. No path handling on our side.
  AppDatabase() : super(driftDatabase(name: 'cardboardpress'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultColors(); // only runs the first time the DB is made
        },
      );

  /// A live, ordered stream of the palette. drift re-emits whenever the table
  /// changes, which is what makes "edit a colour → everything updates" free.
  Stream<List<PaletteColor>> watchColors() {
    return (select(paletteColors)
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  }

  Future<void> _seedDefaultColors() async {
    final defaults = <PaletteColorsCompanion>[
      PaletteColorsCompanion.insert(
          id: 'c_ruby', name: 'Ruby', c1: 0xFFD64545, position: const Value(0)),
      PaletteColorsCompanion.insert(
          id: 'c_amber',
          name: 'Amber',
          c1: 0xFFE0A33A,
          position: const Value(1)),
      PaletteColorsCompanion.insert(
          id: 'c_leaf', name: 'Leaf', c1: 0xFF6FAE6F, position: const Value(2)),
      PaletteColorsCompanion.insert(
          id: 'c_sky', name: 'Sky', c1: 0xFF4F8FD6, position: const Value(3)),
      PaletteColorsCompanion.insert(
          id: 'c_plum', name: 'Plum', c1: 0xFF8A5CB0, position: const Value(4)),
      PaletteColorsCompanion.insert(
          id: 'c_ink', name: 'Ink', c1: 0xFF2C2B27, position: const Value(5)),
      PaletteColorsCompanion.insert(
          id: 'c_paper',
          name: 'Paper',
          c1: 0xFFF1EFE8,
          position: const Value(6)),
      // One double colour, to prove the split renders in the swatch.
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
}
