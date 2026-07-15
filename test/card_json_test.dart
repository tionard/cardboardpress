// Card data JSON tests (model/card_json.dart): text keys resolve to human
// labels through the effective template, look-only data (template names, art,
// layers) never leaks in, and absent-by-default keys stay absent.

import 'dart:convert';
import 'dart:ui';

import 'package:cardboardpress/model/card_json.dart';
import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:flutter_test/flutter_test.dart';

TemplateData _template() => TemplateData(
      baseColor: ColorRef.literal(const ColorValue.single(Color(0xFF222222))),
      fields: const [
        FieldSpec(
            id: 'f_name',
            type: FieldType.name,
            frac: Rect.fromLTRB(0, 0, 1, 0.1)),
        FieldSpec(
            id: 'f_cost',
            type: FieldType.cost,
            frac: Rect.fromLTRB(0.8, 0, 1, 0.1)),
      ],
      layers: const [
        Layer(
            id: 'l_flavor1',
            name: 'Flavor',
            frac: Rect.fromLTRB(0, 0.7, 1, 0.8)),
        Layer(
            id: 'l_flavor2',
            name: 'Flavor',
            frac: Rect.fromLTRB(0, 0.8, 1, 0.9)),
      ],
    );

CardEntry _card({
  Map<String, String> text = const {},
  String artist = '',
  String? rarityId,
  FoilType foil = FoilType.none,
}) =>
    CardEntry(
      id: 'card1',
      templateId: null, // deleted template — the snapshot resolves labels
      templateSnapshot: _template(),
      content: CardContent(text: text, artist: artist, rarityId: rarityId),
      foil: foil,
    );

void main() {
  test('text keys resolve to field types and layer names, duplicates suffixed',
      () {
    final card = _card(text: {
      'f_name': 'Dragon',
      'f_cost': '{R}{R}',
      'l_flavor1': 'It burns.',
      'l_flavor2': 'It burns again.',
      'l_gone': 'Orphaned text', // layer deleted later — raw id kept
      'f_blank': '   ', // whitespace-only is dropped
    });
    final map = cardToJsonMap(card, template: card.effectiveTemplate(const {}));

    expect(map['name'], equals('Dragon'));
    final text = map['text'] as Map<String, String>;
    expect(text['name'], equals('Dragon'));
    expect(text['cost'], equals('{R}{R}'), reason: 'mana cost rides as cost');
    expect(text['Flavor'], equals('It burns.'));
    expect(text['Flavor #2'], equals('It burns again.'));
    expect(text['l_gone'], equals('Orphaned text'));
    expect(text.containsKey('f_blank'), isFalse);
  });

  test('look-only data never leaks in; absent-by-default keys stay absent',
      () {
    final map = cardToJsonMap(_card(text: {'f_name': 'Plain'}),
        template: _card().effectiveTemplate(const {}));
    final encoded = jsonEncode(map);
    expect(encoded, isNot(contains('template')));
    expect(encoded, isNot(contains('art')));
    expect(encoded, isNot(contains('image')));
    expect(map.containsKey('foil'), isFalse, reason: 'foil none is omitted');
    expect(map.containsKey('artist'), isFalse);
    expect(map.containsKey('rarity'), isFalse);
    expect(map.containsKey('number'), isFalse);
  });

  test('foil, artist, rarity, and numbering appear when present', () {
    final map = cardToJsonMap(
      _card(text: {'f_name': 'Shiny'}, artist: 'Tio', foil: FoilType.holo),
      template: _card().effectiveTemplate(const {}),
      rarity: const RarityEntry(id: 'r1', name: 'Rare', abbreviation: 'R'),
      number: 3,
      total: 60,
    );
    expect(map['foil'], equals('holo'));
    expect(map['artist'], equals('Tio'));
    expect(map['rarity'], equals({'name': 'Rare', 'abbreviation': 'R'}));
    expect((map['number'], map['total']), equals((3, 60)));
  });

  test('explicit numbers override the index fallback (partial selections)',
      () {
    final json = cardsToJson(
      [
        _card(text: {'f_name': 'Seventh'}),
        _card(text: {'f_name': 'Unnumbered'}),
      ],
      liveTemplates: const {},
      numbers: [7, null],
      total: 60,
      now: DateTime(2026, 7, 14),
    );
    final cards = (jsonDecode(json) as Map<String, dynamic>)['cards'] as List;
    expect(cards[0]['number'], equals(7),
        reason: 'position within the FULL set, not the selection');
    expect(cards[0]['total'], equals(60));
    expect((cards[1] as Map).containsKey('number'), isFalse);
    expect(cards[1]['total'], equals(60));
  });

  test('cardsToJson wraps the set and numbers cards in collection order', () {
    final json = cardsToJson(
      [
        _card(text: {'f_name': 'First'}, rarityId: 'r1'),
        _card(text: {'f_name': 'Second'}),
      ],
      liveTemplates: const {},
      rarities: const {
        'r1': RarityEntry(id: 'r1', name: 'Common', abbreviation: 'C')
      },
      set: const SetEntry(id: 's1', name: 'Core Set', abbreviation: 'CORE'),
      numbered: true,
      now: DateTime(2026, 7, 14),
    );
    final doc = jsonDecode(json) as Map<String, dynamic>;
    expect(doc['set'], equals({'name': 'Core Set', 'abbreviation': 'CORE'}));
    expect(doc['exported'], startsWith('2026-07-14'));
    final cards = doc['cards'] as List;
    expect(cards, hasLength(2));
    expect(cards[0]['name'], equals('First'));
    expect(cards[0]['rarity']['abbreviation'], equals('C'));
    expect(cards[1]['number'], equals(2));
    expect(cards[1]['total'], equals(2));
  });
}
