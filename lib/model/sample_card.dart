// lib/model/sample_card.dart
//
// A hand-built demo card used by the Card Editor preview and the spike until
// the real Card Editor exists. Its base colour and field fills REFERENCE
// palette swatches by id, so editing those colours in Customize restyles this
// card live. Each reference also carries a snapshot, so deleting the colour
// leaves the card rendering with the fallback instead of breaking.

import 'dart:ui';

import 'card_model.dart';

CardData sampleCard({bool foil = true, bool border = true}) {
  const ink = Color(0xFF2C2B27);

  // Base references the seeded "Forest Fade" double colour (id 'c_forest').
  const baseRef = ColorRef(
    id: 'c_forest',
    snapshot: ColorValue.duo(
      Color(0xFF8FAE6F),
      Color(0xFF2E6E4E),
      orientation: MixOrientation.vertical,
      mix: 0.5,
    ),
  );

  // The text fields fill from the seeded "Paper" colour (id 'c_paper').
  const paperRef = ColorRef(id: 'c_paper', snapshot: ColorValue.single(Color(0xFFF1EFE8)));

  return CardData(
    cornerRadiusFrac: 0.055,
    baseColor: baseRef,
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
        fill: paperRef,
        fillAlpha: 0.7,
        outline: OutlineSpec(lighter: false, intensity: 0.45),
        text: TextStyleSpec(sizeFrac: 0.05, bold: true, color: ink),
      ),
      FieldSpec(
        type: FieldType.art,
        frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52),
      ),
      FieldSpec(
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: paperRef,
        fillAlpha: 0.7,
        text: TextStyleSpec(sizeFrac: 0.032, bold: true, color: ink),
      ),
      FieldSpec(
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: paperRef,
        fillAlpha: 0.55,
        outline: OutlineSpec(lighter: false, intensity: 0.3),
        text: TextStyleSpec(sizeFrac: 0.03, color: ink),
      ),
      FieldSpec(
        type: FieldType.footer,
        frac: Rect.fromLTRB(0.06, 0.905, 0.94, 0.96),
        text: TextStyleSpec(
            sizeFrac: 0.022, color: Color(0x99000000), align: TextAlign.left),
      ),
    ],
  );
}
