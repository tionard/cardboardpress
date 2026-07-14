// lib/model/card_json.dart
//
// Card DATA export for people building digital games on top of their sets:
// the card-edit surface as structured JSON — text values (name, cost, rules,
// flavor, any exposed free-text layer), artist, foil, rarity, set, collector
// number. Deliberately EXCLUDED: template names, layer/geometry JSON, art
// image ids, frames, symbols — anything about how the card LOOKS rather than
// what it SAYS (per the export spec agreed for v1).
//
// Text keys are human labels, not internal ids: a legacy field's value is
// keyed by its semantic type ('name', 'cost', 'rules', …) and a free-text
// layer's by the layer's display name, resolved through the card's effective
// template. Unresolvable ids (layer deleted after text was written) keep the
// raw id rather than dropping data. Duplicate labels get ' #2', ' #3', …

import 'dart:convert';

import 'card_model.dart';
import 'layers.dart';

/// One card as a JSON-ready map. [template] is the card's EFFECTIVE template
/// (live if it exists, else the snapshot — CardEntry.effectiveTemplate);
/// [number]/[total] come from the caller since collector numbers are
/// positional within the set.
Map<String, dynamic> cardToJsonMap(
  CardEntry card, {
  required TemplateData template,
  RarityEntry? rarity,
  int? number,
  int? total,
}) {
  // id -> human label, from both binding surfaces.
  final labels = <String, String>{
    for (final f in template.fields) f.id: f.type.name,
    for (final l in template.layers ?? const <Layer>[]) l.id: l.name,
  };

  final text = <String, String>{};
  for (final e in card.content.text.entries) {
    if (e.value.trim().isEmpty) continue;
    var label = labels[e.key] ?? e.key;
    var candidate = label;
    var i = 2;
    while (text.containsKey(candidate)) {
      candidate = '$label #${i++}';
    }
    text[candidate] = e.value;
  }

  return {
    'name': text['name'] ?? '',
    'number': ?number,
    'total': ?total,
    if (rarity != null)
      'rarity': {
        'name': rarity.name,
        if (rarity.abbreviation.isNotEmpty)
          'abbreviation': rarity.abbreviation,
      },
    if (card.foil != FoilType.none) 'foil': card.foil.name,
    if (card.content.artist.trim().isNotEmpty)
      'artist': card.content.artist.trim(),
    'text': text,
  };
}

/// A whole selection as one pretty-printed JSON document:
/// `{set?, exported, cards: [...]}`. Cards must be passed in collection
/// order — [numbered] adds 1-based collector numbers over that order (pass
/// the set's `numbering` flag).
String cardsToJson(
  List<CardEntry> cards, {
  required Map<String, TemplateData> liveTemplates,
  Map<String, RarityEntry> rarities = const {},
  SetEntry? set,
  bool numbered = false,
  DateTime? now,
}) {
  final doc = <String, dynamic>{
    if (set != null)
      'set': {
        'name': set.name,
        if (set.abbreviation.isNotEmpty) 'abbreviation': set.abbreviation,
      },
    'exported': (now ?? DateTime.now()).toIso8601String(),
    'cards': [
      for (var i = 0; i < cards.length; i++)
        cardToJsonMap(
          cards[i],
          template: cards[i].effectiveTemplate(liveTemplates),
          rarity: rarities[cards[i].content.rarityId],
          number: numbered ? i + 1 : null,
          total: numbered ? cards.length : null,
        ),
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(doc);
}
