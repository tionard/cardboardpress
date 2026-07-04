// lib/model/layer_migration.dart
//
// LAYER REDESIGN — deriving a Layer list from the current model.
//
// The list is built in the EXACT current draw order so the layer-driven
// renderer reproduces `paintCardLegacy` pixel-for-pixel:
//
//   base -> [background image] -> tint -> fields (in order) -> set symbol
//        -> foil -> [outer border]
//
// Pure structure->layout. It moves NO per-card storage: chrome layers
// (base / bg / tint / set-symbol / foil / border) get reserved ids and carry
// only template-level styling; their per-card values (tint colour+alpha, foil
// type, resolved images, rarity tint) are read from the CardData at render time
// by the renderer, keyed on those reserved ids. Field layers KEEP the field's
// own id, so the per-card maps (textContent / artImageIds / artTransforms /
// watermarkImageIds) keep resolving with no re-keying.
//
// [templateToLayers] and [cardToLayers] share one builder, so both produce an
// identical list for the same layout — the live renderer uses [cardToLayers].

import 'dart:ui';

import 'card_model.dart';
import 'layers.dart';

// Reserved ids for card chrome that isn't a template field. The renderer
// recognises these to pull the matching per-card value.
const String kBaseLayerId = '_base';
const String kBgLayerId = '_bg';
const String kTintLayerId = '_tint';
const String kSetSymbolLayerId = '_setsymbol';
const String kFoilLayerId = '_foil';
const String kBorderLayerId = '_border';

const Rect _fullRect = Rect.fromLTRB(0, 0, 1, 1);

/// Ordered layers for a template, in current draw order (index 0 = bottom).
List<Layer> templateToLayers(TemplateData t) => _buildLayers(
      baseColor: t.baseColor,
      bgImageId: t.bgImageId,
      bgTransform: t.bgTransform,
      fields: t.fields,
      setSymbol: t.setSymbol,
      border: t.border,
    );

/// Ordered layers for a fully-composed card — the same structure as
/// [templateToLayers] for the card's template. This is what the live renderer
/// uses; it then reads per-card values from the CardData by the reserved ids.
List<Layer> cardToLayers(CardData c) => _buildLayers(
      baseColor: c.baseColor,
      bgImageId: c.bgImageId,
      bgTransform: c.bgTransform,
      fields: c.fields,
      setSymbol: c.setSymbolPlacement ?? const SetSymbolPlacement(),
      border: c.border,
    );

/// Apply the template's arrangement overlay to a derived layer list: hide the
/// ids in [hidden], then reorder by [order]. Ids in [order] that no longer exist
/// are ignored; layers not mentioned in [order] (e.g. a newly added field) keep
/// their derived position, appended after the ordered ones. Empty overlay =
/// [derived] unchanged (so existing cards render exactly as before).
List<Layer> applyLayerOverlay(
    List<Layer> derived, List<String> order, List<String> hidden) {
  final hiddenSet = hidden.toSet();
  final visApplied = hiddenSet.isEmpty
      ? derived
      : [
          for (final l in derived)
            hiddenSet.contains(l.id) ? l.copyWith(visible: false) : l,
        ];

  if (order.isEmpty) return visApplied;

  final byId = {for (final l in visApplied) l.id: l};
  final result = <Layer>[];
  final seen = <String>{};
  for (final id in order) {
    final l = byId[id];
    if (l != null && seen.add(id)) result.add(l);
  }
  for (final l in visApplied) {
    if (!seen.contains(l.id)) result.add(l);
  }
  return result;
}

/// The layer list to render/edit for a template. If [t] carries a persisted
/// [TemplateData.layers] (Phase 4: it's been authored into an explicit list),
/// that IS the truth — list order = z-order, per-layer visibility applies, and
/// the arrangement overlay is not consulted. Otherwise derive from the fields +
/// chrome and apply the lightweight `layerOrder`/`hiddenLayers` overlay (the
/// pre-Phase-4 behaviour). Existing templates (layers == null) are unchanged.
List<Layer> effectiveTemplateLayers(TemplateData t) =>
    t.layers ??
    applyLayerOverlay(templateToLayers(t), t.layerOrder, t.hiddenLayers);

/// The layer list to render for a composed card — the card-side twin of
/// [effectiveTemplateLayers]. This is what the renderer walks.
List<Layer> effectiveCardLayers(CardData c) {
  final base = c.layers ??
      applyLayerOverlay(cardToLayers(c), c.layerOrder, c.hiddenLayers);
  if (c.fillColors.isEmpty &&
      c.outlineColors.isEmpty &&
      c.cardHiddenLayers.isEmpty &&
      c.foilOverrides.isEmpty) {
    return base;
  }
  // Bake the card's exposed per-card overrides (fill / outline colour, and
  // per-card visibility) onto the layers here — so the renderer stays a single
  // untouched path that just draws whatever it's handed.
  return [for (final l in base) _applyCardOverrides(l, c)];
}

Layer _applyCardOverrides(Layer l, CardData c) {
  var out = l;
  final fc = c.fillColors[l.id];
  if (fc != null && out.fill != null) {
    out = out.copyWith(fill: out.fill!.copyWith(color: fc));
  }
  final oc = c.outlineColors[l.id];
  if (oc != null && out.outline != null) {
    out = out.copyWith(outline: out.outline!.copyWith(color: oc));
  }
  if (out.visible && c.cardHiddenLayers.contains(l.id)) {
    out = out.copyWith(visible: false);
  }
  final fo = c.foilOverrides[l.id];
  if (fo != null) out = out.copyWith(foil: fo);
  return out;
}

List<Layer> _buildLayers({
  required ColorRef baseColor,
  required String? bgImageId,
  required ArtTransform bgTransform,
  required List<FieldSpec> fields,
  required SetSymbolPlacement setSymbol,
  required BorderSpec? border,
}) {
  final layers = <Layer>[];

  // base — full-card fill, opaque, bottom.
  layers.add(Layer(
    id: kBaseLayerId,
    name: 'Base',
    frac: _fullRect,
    fill: FillAspect(color: baseColor),
  ));

  // background image (optional) — over base, under tint; as-is cover-fit.
  if (bgImageId != null) {
    layers.add(Layer(
      id: kBgLayerId,
      name: 'Background',
      frac: _fullRect,
      image: ImageAspect(
        source: ImageSource.fixed,
        imageId: bgImageId,
        transform: bgTransform,
      ),
    ));
  }

  // tint — full-card fill slot; value + alpha are PER-CARD (read at render).
  layers.add(Layer(
    id: kTintLayerId,
    name: 'Tint',
    frac: _fullRect,
    fill: FillAspect(color: baseColor),
    exposed: const {ExposedAspect.fill: EditorTab.color},
  ));

  // fields — each becomes one layer, KEEPING the field id (zero per-card re-key).
  for (final f in fields) {
    layers.add(_fieldToLayer(f));
  }

  // set symbol — template-placed image, source=setSymbol (rarity-tinted per
  // card). visible mirrors the placement's enabled flag.
  layers.add(Layer(
    id: kSetSymbolLayerId,
    name: 'Set symbol',
    visible: setSymbol.enabled,
    frac: setSymbol.frac,
    image: ImageAspect(
      source: ImageSource.setSymbol,
      alpha: setSymbol.alpha,
    ),
    exposed: const {ExposedAspect.image: EditorTab.set},
  ));

  // foil — full-card overlay slot; the FoilType is PER-CARD (renderer reads
  // card.foil for this slot).
  layers.add(const Layer(id: kFoilLayerId, name: 'Foil', frac: _fullRect));

  // outer border — pure white/black chrome, drawn OUTSIDE the rounded clip, on
  // top. Present as a top slot so it shows in the Layers list; the renderer
  // special-cases it and reads the template BorderSpec. Not freely reorderable
  // below content yet (outside-clip special case).
  if (border != null) {
    layers.add(const Layer(id: kBorderLayerId, name: 'Border', frac: _fullRect));
  }

  return layers;
}

Layer _fieldToLayer(FieldSpec f) {
  final kind = switch (f.type) {
    FieldType.art => LayerKind.art,
    FieldType.rules => LayerKind.rules,
    FieldType.footer => LayerKind.footer,
    _ => LayerKind.generic,
  };

  // Per-card exposure (drives the Card Editor; does NOT affect rendering). Art
  // exposes its image to the art tab; other text-bearing fields expose text to
  // the card tab. Footer text is derived, not exposed.
  final exposed = <ExposedAspect, EditorTab>{};
  if (f.type == FieldType.art) {
    exposed[ExposedAspect.image] = EditorTab.art;
  } else if (f.text != null && f.type != FieldType.footer) {
    exposed[ExposedAspect.text] = EditorTab.card;
  }

  return Layer(
    id: f.id, // KEEP the field id
    name: _fieldName(f.type),
    kind: kind,
    frac: f.frac,
    cornerRadius: f.cornerRadius,
    fill: f.fill == null ? null : FillAspect(color: f.fill!, alpha: f.fillAlpha),
    outline: f.outline,
    // 9-slice frame; when present the renderer suppresses fill + outline exactly
    // as `spriteMode` does today (fill kept dormant, not dropped).
    border: f.frame,
    text: f.text == null
        ? null
        : TextAspect(
            style: f.text!,
            inline: f.type == FieldType.cost || f.type == FieldType.rules,
          ),
    watermark: f.watermark,
    footer: f.footer,
    exposed: exposed,
  );
}

String _fieldName(FieldType t) => switch (t) {
      FieldType.name => 'Name',
      FieldType.alias => 'Alias',
      FieldType.cost => 'Cost',
      FieldType.type => 'Type',
      FieldType.rules => 'Rules',
      FieldType.flavor => 'Flavor',
      FieldType.stat => 'Stat',
      FieldType.art => 'Art',
      FieldType.footer => 'Footer',
    };
