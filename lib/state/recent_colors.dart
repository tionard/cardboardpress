// lib/state/recent_colors.dart
//
// A small most-recently-used list of *literal* colours, kept per SwatchUse
// (card / text / symbol) — the colours you reach for in text differ from card
// fills. Persisted in the same tiny key/value settings table as the theme and
// entitlement, so recents survive restarts and ride along in a library backup.
//
// Only literals are recorded: palette swatches already live in the palette, so
// re-listing them here would be noise. Duos are eligible — the whole ColorValue
// (both colours + blend) is stored, so a duo you just built is one tap to reuse.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/card_model.dart';
import '../model/serialization.dart';
import '../widgets/swatch_picker.dart';
import 'providers.dart';

const int _kRecentsMax = 8;

String _recentsKey(SwatchUse use) => switch (use) {
      SwatchUse.card => 'recents_card',
      SwatchUse.text => 'recents_text',
      SwatchUse.symbol => 'recents_symbol',
    };

// Stored as a JSON array of ColorRef JSON strings (each a literal snapshot).
// Reuses the public colorRef round-trip so there's no bespoke serialization.
String _encode(List<ColorValue> values) =>
    jsonEncode([for (final v in values) colorRefToJson(ColorRef.literal(v))]);

List<ColorValue> _decode(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final arr = jsonDecode(raw) as List;
    return [for (final s in arr) colorRefFromJson(s as String).snapshot];
  } catch (_) {
    return const []; // tolerate any legacy / malformed value
  }
}

// Prepend [add], drop an existing duplicate, cap at [_kRecentsMax]. Equality is
// by serialized form (ColorValue has no value equality), which also matches
// "same colour + same blend".
List<ColorValue> _mru(List<ColorValue> current, ColorValue add) {
  final addKey = colorRefToJson(ColorRef.literal(add));
  final out = <ColorValue>[add];
  for (final v in current) {
    if (colorRefToJson(ColorRef.literal(v)) == addKey) continue;
    out.add(v);
    if (out.length >= _kRecentsMax) break;
  }
  return out;
}

/// Per-tag recent literal colours. Hydrated lazily from the DB on first watch;
/// [add] is DB-authoritative so a commit during that initial load can't clobber
/// the persisted list.
class RecentColorsNotifier
    extends Notifier<Map<SwatchUse, List<ColorValue>>> {
  @override
  Map<SwatchUse, List<ColorValue>> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final map = await ref.read(databaseProvider).readSettings();
    state = {
      for (final use in SwatchUse.values) use: _decode(map[_recentsKey(use)]),
    };
  }

  /// Record a used literal colour at the front of [use]'s list.
  Future<void> add(SwatchUse use, ColorValue value) async {
    final db = ref.read(databaseProvider);
    final persisted = _decode((await db.readSettings())[_recentsKey(use)]);
    final next = _mru(persisted, value);
    await db.putSetting(_recentsKey(use), _encode(next));
    state = {...state, use: next};
  }
}

final recentColorsProvider =
    NotifierProvider<RecentColorsNotifier, Map<SwatchUse, List<ColorValue>>>(
        RecentColorsNotifier.new);
