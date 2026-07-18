// lib/data/symbol_seeder.dart
//
// Seeds the bundled text-symbol pack (the mana pips users type as {tag} in
// Cost/Rules text) at app startup. The PNGs ship as assets under
// assets/seed/symbols/tagged/ and are copied into the ImageStore under stable
// ids, then one TextSymbols row is inserted per pip.
//
// Versioned, not one-shot: a pack version stored in AppSettings
// ('seed.textSymbols.packVersion') gates the work. Launching with a stored
// version below _packVersion (re-)runs the seed; matching or newer skips it
// entirely. That is what lets the pack GROW across releases — bump
// _packVersion, append entries, and every install tops itself up on next
// launch. Re-running is harmless by construction: images overwrite with
// identical bytes and rows insert with insertOrIgnore, so user edits to a
// seeded symbol's tag or position survive (same id → ignored), while a
// default the user deleted only returns on a version bump.
//
// v0 → v1 also retires the original four programmatically-rendered letter
// pips (coloured circles): their rows are deleted here, and the startup image
// GC sweeps their now-unreferenced glyph files the same launch. The sample
// card's {R}{R} cost keeps resolving — the Roots pip takes the R tag.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'database.dart';
import 'image_store.dart';

/// Bump when the bundled pack changes (new pips, replaced art, retirements).
const _packVersion = 1;
const _packVersionKey = 'seed.textSymbols.packVersion';

/// Where the pack's PNGs live. Must match the pubspec asset entry (folder
/// entries need the trailing slash and cover only direct children).
const _assetDir = 'assets/seed/symbols/tagged';

class _SeedSymbol {
  /// PNG basename under [_assetDir], e.g. 'Arcane.png'.
  final String file;

  /// What users type inside braces — {F} for Fire. Matched as typed.
  final String tag;

  const _SeedSymbol(this.file, this.tag);
}

// Display order in Customize → Symbols → Text {tag} = list order (position
// column): the eight elements first, then the life/death and sun/moon pairs,
// then mind-and-magic, then the odd ones out.
const _pack = <_SeedSymbol>[
  // Elements.
  _SeedSymbol('Fire.png', 'F'),
  _SeedSymbol('Water.png', 'W'),
  _SeedSymbol('Earth.png', 'E'),
  _SeedSymbol('Wind.png', 'Y'),
  _SeedSymbol('Lightning.png', 'B'),
  _SeedSymbol('Nature.png', 'N'),
  _SeedSymbol('Roots.png', 'R'),
  _SeedSymbol('Iron.png', 'I'),
  // Opposing pairs.
  _SeedSymbol('Life.png', 'L'),
  _SeedSymbol('Death.png', 'D'),
  _SeedSymbol('Sun.png', 'S'),
  _SeedSymbol('Moon.png', 'M'),
  // Mind and magic.
  _SeedSymbol('Arcane.png', 'A'),
  _SeedSymbol('Psychic.png', 'P'),
  _SeedSymbol('Knowledge.png', 'K'),
  _SeedSymbol('Essence.png', 'U'),
  _SeedSymbol('Void.png', 'V'),
  // Everything else.
  _SeedSymbol('Money.png', 'G'),
  _SeedSymbol('Colorless.png', 'C'),
];

/// Row ids of the retired v0 placeholder circles (see header comment).
const _legacyIds = ['ts_r', 'ts_g', 'ts_b', 'ts_y'];

/// Filename → the stable, filesystem-safe stem used for both the row id
/// ('ts_seed_arcane') and the stored image id ('sym_seed_arcane.png').
/// Distinct from every legacy id, so old and new can never collide.
String _stem(String file) {
  final dot = file.lastIndexOf('.');
  final base = dot > 0 ? file.substring(0, dot) : file;
  return base.toLowerCase();
}

/// Seeds/tops-up the bundled text-symbol pack. Called from main() before
/// runApp; must never throw, so a missing/corrupt asset is logged, skipped,
/// and retried next launch (the version key is only written when the whole
/// pack landed).
Future<void> seedDefaultTextSymbols(AppDatabase db, ImageStore store) async {
  final settings = await db.readSettings();
  final have = int.tryParse(settings[_packVersionKey] ?? '') ?? 0;
  if (have >= _packVersion) return;

  // v0 → v1: retire the placeholder circles. Their glyph files become
  // unreferenced and the startup GC deletes them this same launch.
  for (final id in _legacyIds) {
    await db.deleteTextSymbol(id);
  }

  var allOk = true;
  for (var i = 0; i < _pack.length; i++) {
    final s = _pack[i];
    try {
      final data = await rootBundle.load('$_assetDir/${s.file}');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final stem = _stem(s.file);
      final imageId = await store.save(bytes, id: 'sym_seed_$stem.png');
      await db.insertTextSymbol(TextSymbolsCompanion.insert(
        id: 'ts_seed_$stem',
        tag: s.tag,
        imageId: imageId,
        position: Value(i),
      ));
    } catch (e) {
      // Typically a filename/pubspec mismatch. Never block launch over it.
      allOk = false;
      debugPrint('symbol_seeder: failed to seed ${s.file}: $e');
    }
  }

  if (allOk) {
    await db.putSetting(_packVersionKey, '$_packVersion');
  }
}
