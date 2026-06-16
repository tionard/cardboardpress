// lib/model/sample_card.dart
//
// A hand-built demo card used by the Card Editor preview and the spike until
// the real Card Editor exists. Its base colour, field fills, AND text colours
// all REFERENCE palette swatches by id, so editing those colours in Customize
// restyles this card live. Each reference also carries a snapshot, so deleting
// the colour leaves the card rendering with the fallback instead of breaking.

import 'dart:ui';

import 'card_model.dart';

// Shared references to seeded palette colours.
const _forestRef = ColorRef(
  id: 'c_forest',
  snapshot: ColorValue.duo(
    Color(0xFF8FAE6F),
    Color(0xFF2E6E4E),
    orientation: MixOrientation.vertical,
    mix: 0.5,
  ),
);
const _inkRef =
    ColorRef(id: 'c_ink', snapshot: ColorValue.single(Color(0xFF2C2B27)));
const _paperRef =
    ColorRef(id: 'c_paper', snapshot: ColorValue.single(Color(0xFFF1EFE8)));

CardData sampleCard({bool foil = true, bool border = true}) {
  return CardData(
    cornerRadiusFrac: 0.055,
    baseColor: _forestRef,
    border: border ? const BorderSpec(black: true, thickness: 0.022) : null,
    foil: foil ? FoilType.holo : FoilType.none,
    textContent: const {
      FieldType.name: 'Thornwood Stag',
      FieldType.type: 'Creature — Beast',
      FieldType.rules: 'Vigilance. When this enters, scry 2.',
      FieldType.footer: '001/120 · TWD · © 26',
    },
    fields: const [
      FieldSpec(
        type: FieldType.name,
        frac: Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        fill: _paperRef,
        fillAlpha: 0.85,
        outline: OutlineSpec(lighter: false, intensity: 0.45),
        // Double-colour title (references the same "Forest Fade" swatch) — this
        // is what double-colour text looks like rendered for real.
        text: TextStyleSpec(sizeFrac: 0.05, bold: true, colorRef: _forestRef),
      ),
      FieldSpec(
        type: FieldType.art,
        frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52),
      ),
      FieldSpec(
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: _paperRef,
        fillAlpha: 0.7,
        text: TextStyleSpec(sizeFrac: 0.032, bold: true, colorRef: _inkRef),
      ),
      FieldSpec(
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: _paperRef,
        fillAlpha: 0.55,
        outline: OutlineSpec(lighter: false, intensity: 0.3),
        text: TextStyleSpec(sizeFrac: 0.03, colorRef: _inkRef),
      ),
      FieldSpec(
        type: FieldType.footer,
        frac: Rect.fromLTRB(0.06, 0.905, 0.94, 0.96),
        text: TextStyleSpec(
            sizeFrac: 0.022, align: TextAlign.left, colorRef: _inkRef, colorAlpha: 0.6),
      ),
    ],
  );
}
