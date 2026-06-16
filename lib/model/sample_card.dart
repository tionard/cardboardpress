// lib/model/sample_card.dart
//
// Default templates + sample content, and the compose step that turns a
// TemplateData (layout) plus content into a CardData (the render model that
// paintCard consumes). The field layout is defined ONCE here and shared.

import 'dart:ui';

import 'card_model.dart';

// Seeded palette references reused across the default templates.
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

// The shared field layout. Only the Name text colour varies between templates.
List<FieldSpec> _fields({required ColorRef nameTextRef}) => [
      FieldSpec(
        type: FieldType.name,
        frac: const Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        fill: _paperRef,
        fillAlpha: 0.85,
        outline: const OutlineSpec(intensity: 0.45),
        text: TextStyleSpec(sizeFrac: 0.05, bold: true, colorRef: nameTextRef),
      ),
      const FieldSpec(
          type: FieldType.art, frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52)),
      const FieldSpec(
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: _paperRef,
        fillAlpha: 0.7,
        text: TextStyleSpec(sizeFrac: 0.032, bold: true, colorRef: _inkRef),
      ),
      const FieldSpec(
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: _paperRef,
        fillAlpha: 0.55,
        outline: OutlineSpec(intensity: 0.3),
        text: TextStyleSpec(sizeFrac: 0.03, colorRef: _inkRef),
      ),
      const FieldSpec(
        type: FieldType.footer,
        frac: Rect.fromLTRB(0.06, 0.905, 0.94, 0.96),
        text: TextStyleSpec(
            sizeFrac: 0.022, align: TextAlign.left, colorRef: _inkRef, colorAlpha: 0.6),
      ),
    ];

TemplateData _thornwood({bool border = true}) => TemplateData(
      cornerRadiusFrac: 0.055,
      baseColor: _forestRef,
      border: border ? const BorderSpec(black: true, thickness: 0.022) : null,
      fields: _fields(nameTextRef: _forestRef), // double-colour title
    );

TemplateData _parchment() => TemplateData(
      cornerRadiusFrac: 0.055,
      baseColor: _paperRef,
      border: null,
      fields: _fields(nameTextRef: _inkRef), // single ink title, no border
    );

/// The templates seeded into the database on first run / first upgrade.
List<TemplateEntry> defaultTemplates() => [
      TemplateEntry(id: 't_thornwood', name: 'Thornwood', data: _thornwood()),
      TemplateEntry(id: 't_parchment', name: 'Parchment', data: _parchment()),
    ];

/// Placeholder card content until cards become real entities next turn.
Map<FieldType, String> sampleContent() => const {
      FieldType.name: 'Thornwood Stag',
      FieldType.type: 'Creature — Beast',
      FieldType.rules: 'Vigilance. When this enters, scry 2.',
      FieldType.footer: '001/120 · TWD · © 26',
    };

/// Compose a template + content (+ foil) into the render model.
CardData composeCard(
  TemplateData t, {
  required Map<FieldType, String> textContent,
  FoilType foil = FoilType.none,
}) =>
    CardData(
      widthInches: t.widthInches,
      heightInches: t.heightInches,
      cornerRadiusFrac: t.cornerRadiusFrac,
      baseColor: t.baseColor,
      border: t.border,
      fields: t.fields,
      foil: foil,
      textContent: textContent,
    );

/// Convenience used by the spike: the Thornwood template + sample content.
CardData sampleCard({bool foil = true, bool border = true}) => composeCard(
      _thornwood(border: border),
      textContent: sampleContent(),
      foil: foil ? FoilType.holo : FoilType.none,
    );
