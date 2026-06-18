// lib/model/sample_card.dart
//
// Default templates + sample content, and the compose step that merges a
// TemplateData (layout) with CardContent into a CardData (the render model that
// paintCard consumes). The field layout is defined ONCE here and shared; each
// field carries a stable id, and content is keyed by those ids.

import 'dart:ui';

import 'card_model.dart';

// Stable field ids for the default layout.
const fNameId = 'f_name';
const fArtId = 'f_art';
const fTypeId = 'f_type';
const fRulesId = 'f_rules';
const fFooterId = 'f_footer';

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
        id: fNameId,
        type: FieldType.name,
        frac: const Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        fill: _paperRef,
        fillAlpha: 0.85,
        outline: const OutlineSpec(intensity: 0.45),
        text: TextStyleSpec(sizeFrac: 0.05, bold: true, colorRef: nameTextRef),
      ),
      const FieldSpec(
          id: fArtId, type: FieldType.art, frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52)),
      const FieldSpec(
        id: fTypeId,
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: _paperRef,
        fillAlpha: 0.7,
        text: TextStyleSpec(sizeFrac: 0.032, bold: true, colorRef: _inkRef),
      ),
      const FieldSpec(
        id: fRulesId,
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: _paperRef,
        fillAlpha: 0.55,
        outline: OutlineSpec(intensity: 0.3),
        text: TextStyleSpec(sizeFrac: 0.03, colorRef: _inkRef),
      ),
      const FieldSpec(
        id: fFooterId,
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

/// The templates seeded into the database.
List<TemplateEntry> defaultTemplates() => [
      TemplateEntry(id: 't_thornwood', name: 'Thornwood', data: _thornwood()),
      TemplateEntry(id: 't_parchment', name: 'Parchment', data: _parchment()),
    ];

/// A reasonable default layout for a newly-created template.
TemplateData starterTemplate() => _parchment();

/// Sample card content, keyed by field id.
CardContent sampleContent() => const CardContent(text: {
      fNameId: 'Thornwood Stag',
      fTypeId: 'Creature — Beast',
      fRulesId: 'Vigilance. When this enters, scry 2.',
      fFooterId: '001/120 · TWD · © 26',
    });

/// Builds the Footer's derived text (spec §3): collector number, set
/// abbreviation, rarity abbreviation, artist, copyright — joined in a fixed
/// arrangement for now. Only present parts are shown.
String deriveFooterText({
  required String artist,
  SetEntry? set,
  RarityEntry? rarity,
  int? number,
  int? total,
}) {
  final parts = <String>[];
  if (set != null && set.numbering && number != null && total != null) {
    parts.add('${number.toString().padLeft(3, '0')}/$total');
  }
  if (set != null && set.abbreviation.isNotEmpty) parts.add(set.abbreviation);
  if (rarity != null && rarity.abbreviation.isNotEmpty) {
    parts.add(rarity.abbreviation);
  }
  if (artist.isNotEmpty) parts.add('Illus. $artist');
  if (set != null) {
    parts.add(set.owner.isEmpty ? '© ${set.year}' : '© ${set.year} ${set.owner}');
  }
  return parts.join('  ·  ');
}

/// Compose a template + content (+ foil, + derived footer inputs) into the
/// render model. Footer fields are filled with derived text, not authored text.
CardData composeCard(
  TemplateData t, {
  required CardContent content,
  FoilType foil = FoilType.none,
  SetEntry? set,
  RarityEntry? rarity,
  int? number,
  int? total,
  Map<String, String> symbolImageIds = const {},
  Map<String, SymbolEntry> symbolsById = const {},
}) {
  final footer = deriveFooterText(
    artist: content.artist,
    set: set,
    rarity: rarity,
    number: number,
    total: total,
  );
  final text = Map<String, String>.from(content.text);
  for (final f in t.fields) {
    if (f.type == FieldType.footer) text[f.id] = footer;
  }

  // Resolve the set's chosen set symbol to its image id (null if the set has
  // none, or the symbol was deleted — the renderer then simply skips it).
  final setSymbolImageId =
      (set?.symbolId == null) ? null : symbolsById[set!.symbolId]?.imageId;

  return CardData(
    widthInches: t.widthInches,
    heightInches: t.heightInches,
    cornerRadiusFrac: t.cornerRadiusFrac,
    baseColor: t.baseColor,
    tint: content.tint,
    tintAlpha: content.tintAlpha,
    border: t.border,
    fields: t.fields,
    foil: foil,
    textContent: text,
    artImageIds: content.art,
    artTransforms: content.artTransforms,
    bgImageId: t.bgImageId,
    bgTransform: t.bgTransform,
    symbolImageIds: symbolImageIds,
    setSymbolImageId: setSymbolImageId,
    setSymbolPlacement: t.setSymbol,
    setSymbolTint: rarity?.color,
  );
}

/// Convenience used by the spike: Thornwood template + sample content.
CardData sampleCard({bool foil = true, bool border = true}) => composeCard(
      _thornwood(border: border),
      content: sampleContent(),
      foil: foil ? FoilType.holo : FoilType.none,
    );
