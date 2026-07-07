// lib/model/sample_card.dart
//
// Default templates + sample content, and the compose step that merges a
// TemplateData (layout) with CardContent into a CardData (the render model that
// paintCard consumes). The field layout is defined ONCE here and shared; each
// field carries a stable id, and content is keyed by those ids.

import 'dart:ui';

import 'card_model.dart';
import 'layers.dart';
import 'layer_migration.dart';

// Stable field ids for the default layout.
const fNameId = 'f_name';
const fCostId = 'f_cost';
const fArtId = 'f_art';
const fTypeId = 'f_type';
const fRulesId = 'f_rules';
const fStatId = 'f_stat';
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
// List order = draw order (later fields paint on top):
//   Art → Name → Cost → Type → Rules → Stat → Footer.
// Anchors: every field is middle-anchored except Rules, which stays top-anchored
// so multi-line rules text reads top-down. (padX/padY are left at their
// defaults pending the padding-scale decision.)
List<FieldSpec> _fields({required ColorRef nameTextRef}) => [
      const FieldSpec(
          id: fArtId,
          type: FieldType.art,
          frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52)),
      FieldSpec(
        id: fNameId,
        type: FieldType.name,
        frac: const Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        fill: _paperRef,
        fillAlpha: 0.85,
        outline: const OutlineSpec(intensity: 0.45),
        text: TextStyleSpec(
            sizeFrac: 0.05,
            bold: true,
            vAlign: VAlign.middle,
            padX: 0.025,
            colorRef: nameTextRef),
      ),
      // Cost overlays the Name bar: same box, transparent fill, right-aligned —
      // the MTG-style mana cost tucked into the top-right of the title.
      const FieldSpec(
        id: fCostId,
        type: FieldType.cost,
        frac: Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        text: TextStyleSpec(
          sizeFrac: 0.045,
          align: TextAlign.right,
          vAlign: VAlign.middle,
          padX: 0.025,
          colorRef: _inkRef,
        ),
      ),
      const FieldSpec(
        id: fTypeId,
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: _paperRef,
        fillAlpha: 0.7,
        outline: OutlineSpec(intensity: 0.45),
        text: TextStyleSpec(
            sizeFrac: 0.032,
            bold: true,
            vAlign: VAlign.middle,
            padX: 0.025,
            colorRef: _inkRef),
      ),
      const FieldSpec(
        id: fRulesId,
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: _paperRef,
        fillAlpha: 0.55,
        outline: OutlineSpec(intensity: 0.3),
        text: TextStyleSpec(
            sizeFrac: 0.03,
            vAlign: VAlign.top,
            padX: 0.025,
            padY: 0.015,
            colorRef: _inkRef),
      ),
      // Stat (power/toughness) plate in the bottom-right corner of the Rules box.
      const FieldSpec(
        id: fStatId,
        type: FieldType.stat,
        frac: Rect.fromLTRB(0.74, 0.80, 0.94, 0.895),
        fill: _paperRef,
        fillAlpha: 1.0,
        outline: OutlineSpec(intensity: 0.45),
        text: TextStyleSpec(
          sizeFrac: 0.045,
          bold: true,
          align: TextAlign.center,
          vAlign: VAlign.middle,
          padX: 0.025,
          colorRef: _inkRef,
          colorAlpha: 1.0,
        ),
      ),
      const FieldSpec(
        id: fFooterId,
        type: FieldType.footer,
        frac: Rect.fromLTRB(0.06, 0.905, 0.94, 0.96),
        footer: FooterSpec.defaults(),
        text: TextStyleSpec(
            sizeFrac: 0.022,
            align: TextAlign.left,
            vAlign: VAlign.middle,
            padX: 0.025,
            colorRef: _inkRef,
            colorAlpha: 0.6),
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

/// The Thornwood sample template (border on by default). Public so the layer
/// parity test can render the same template through both render paths.
TemplateData sampleTemplate({bool border = true}) => _thornwood(border: border);

/// Sample card content, keyed by field id.
CardContent sampleContent() => const CardContent(text: {
      fNameId: 'Thornwood Stag',
      fCostId: '{R}',
      fTypeId: 'Creature — Beast',
      fRulesId: 'Vigilance. When this enters, scry 2.',
      fStatId: '3/4',
      fFooterId: '001/120 · TWD · © 26',
    });

/// Builds the Footer's derived text (spec §3): collector number, set
/// abbreviation, rarity abbreviation, artist, copyright — joined in a fixed
/// arrangement for now. Only present parts are shown.
/// The per-card string for a bound [TextSource]. Empty when unresolved (e.g. no
/// set assigned yet); in [preview] mode, representative placeholders fill in so
/// the author can position bound layers. Reuses the footer-derivation rules.
String _resolveTextSource(
  TextSource src, {
  required String cardName,
  required String artist,
  SetEntry? set,
  RarityEntry? rarity,
  int? number,
  int? total,
  bool preview = false,
}) {
  String orPreview(String v, String sample) =>
      v.isNotEmpty ? v : (preview ? sample : '');
  switch (src) {
    case TextSource.cardName:
      return orPreview(cardName, 'Card Name');
    case TextSource.setName:
      return orPreview(set?.name ?? '', 'Core Set');
    case TextSource.setAbbrev:
      return orPreview(set?.abbreviation ?? '', 'CORE');
    case TextSource.collectorNumber:
      return (set != null && set.numbering && number != null && total != null)
          ? '${number.toString().padLeft(3, '0')}/$total'
          : (preview ? '001/XXX' : '');
    case TextSource.rarityName:
      return orPreview(rarity?.name ?? '', 'Rare');
    case TextSource.rarityAbbrev:
      return orPreview(rarity?.abbreviation ?? '', 'R');
    case TextSource.artist:
      return artist.isNotEmpty ? 'Illus. $artist' : (preview ? 'Illus. Name' : '');
    case TextSource.copyright:
      if (set == null) return preview ? '© 2026' : '';
      return set.owner.isEmpty ? '© ${set.year}' : '© ${set.year} ${set.owner}';
  }
}

/// The footer's individual pieces, derived per-card. An empty string means
/// there's nothing to show for that component (e.g. no set assigned yet).
Map<FooterComponent, String> deriveFooterValues({  required String artist,
  SetEntry? set,
  RarityEntry? rarity,
  int? number,
  int? total,
}) {
  return {
    FooterComponent.number:
        (set != null && set.numbering && number != null && total != null)
            ? '${number.toString().padLeft(3, '0')}/$total'
            : '',
    FooterComponent.set:
        (set != null && set.abbreviation.isNotEmpty) ? set.abbreviation : '',
    FooterComponent.rarity: (rarity != null && rarity.abbreviation.isNotEmpty)
        ? rarity.abbreviation
        : '',
    FooterComponent.artist: artist.isNotEmpty ? 'Illus. $artist' : '',
    FooterComponent.copyright: set == null
        ? ''
        : (set.owner.isEmpty
            ? '© ${set.year}'
            : '© ${set.year} ${set.owner}'),
  };
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
  String? footerPlaceholder,
}) {
  var footerValues = deriveFooterValues(
    artist: content.artist,
    set: set,
    rarity: rarity,
    number: number,
    total: total,
  );
  // Template preview: when nothing has resolved, fill representative pieces so
  // the configured footer zones can be seen and positioned. Real cards (no
  // footerPlaceholder) keep empty pieces and render blank until data exists.
  if (footerPlaceholder != null &&
      footerValues.values.every((s) => s.isEmpty)) {
    footerValues = const {
      FooterComponent.number: '001/XXX',
      FooterComponent.set: 'CORE',
      FooterComponent.rarity: 'R',
      FooterComponent.artist: '',
      FooterComponent.copyright: '',
    };
  }
  final text = Map<String, String>.from(content.text);
  // Resolve bound text (decomposed footer parts, or any bound layer) over the
  // EFFECTIVE layers, so it works whether or not the template is promoted.
  // Keyed by layer id — exactly what the renderer reads. The card's name is
  // looked up via the name layer (Name field id, or the first free text layer
  // on the Card tab) — never a hardcoded default-template id.
  final layers = effectiveTemplateLayers(t);
  final nameId = nameTextLayerIdIn(layers, t.fields);
  final cardName = nameId == null ? '' : (content.text[nameId] ?? '');
  for (final l in layers) {
    final ta = l.text;
    if (ta == null || ta.parts.isEmpty) continue;
    final joiner = ta.separator.isEmpty ? ' ' : ' ${ta.separator} ';
    final resolved = [
      for (final p in ta.parts)
        _resolveTextSource(
          p,
          cardName: cardName,
          artist: content.artist,
          set: set,
          rarity: rarity,
          number: number,
          total: total,
          preview: footerPlaceholder != null,
        ),
    ].where((s) => s.isNotEmpty);
    text[l.id] = resolved.join(joiner);
  }

  // Resolve the set's chosen set symbol to its image id (null if the set has
  // none, or the symbol was deleted — the renderer then simply skips it).
  final setSymbolImageId =
      (set?.symbolId == null) ? null : symbolsById[set!.symbolId]?.imageId;

  // Resolve each layer's watermark symbol to an image id, keyed by layer id.
  // Walked over the effective layers (not t.fields) so watermarks added or
  // edited on promoted layers resolve too; for derived layers the ids match
  // the old field-keyed map exactly.
  final watermarkImageIds = <String, String>{};
  for (final l in layers) {
    final wm = l.watermark;
    if (wm == null) continue;
    // Per-card symbol override (exposed watermark) wins over the template's.
    final symbolId = content.watermarkSymbols[l.id] ?? wm.symbolId;
    if (symbolId.isEmpty) continue;
    final img = symbolsById[symbolId]?.imageId;
    if (img != null) watermarkImageIds[l.id] = img;
  }

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
    watermarkImageIds: watermarkImageIds,
    footerValues: footerValues,
    layerOrder: t.layerOrder,
    hiddenLayers: t.hiddenLayers,
    layers: t.layers,
    fillColors: content.fillColors,
    outlineColors: content.outlineColors,
    cardHiddenLayers: content.cardHiddenLayers,
    foilOverrides: content.foilOverrides,
    fillAlphas: content.fillAlphas,
    imageAlphas: content.imageAlphas,
    imageTints: content.imageTints,
    watermarkColors: content.watermarkColors,
    watermarkAlphas: content.watermarkAlphas,
  );
}

/// Convenience used by the spike: Thornwood template + sample content.
CardData sampleCard({bool foil = true, bool border = true}) => composeCard(
      _thornwood(border: border),
      content: sampleContent(),
      foil: foil ? FoilType.holo : FoilType.none,
    );
