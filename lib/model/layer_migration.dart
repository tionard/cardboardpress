// lib/model/layer_migration.dart
//
// LAYER REDESIGN — Phase 1b-i: the pure migration TemplateData -> List<Layer>.
//
// It derives the ordered layer list in the EXACT current draw order, so the
// parallel renderer (paintCardFromLayers, 1b-ii) reproduces `paintCard`
// pixel-for-pixel:
//
//   base -> [background image] -> tint -> fields (in order) -> set symbol
//        -> foil -> [outer border]
//
// This function is pure template->layout. It moves NO per-card storage: chrome
// layers (base / bg / tint / set-symbol / foil / border) get reserved ids and
// carry only what the template knows; their per-card values (tint colour+alpha,
// foil type, resolved images, rarity tint) are read from the CardData at render
// time. Field layers KEEP the field's own id, so the per-card maps
// (textContent, artImageIds, artTransforms, watermarkImageIds) keep resolving
// with no re-keying.
//
// Nothing calls this yet except the 1b parity harness.

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
List<Layer> templateToLayers(TemplateData t) {
  final layers = <Layer>[];

  // base — full-card fill, opaque, bottom.
  layers.add(Layer(
    id: kBaseLayerId,
    name: 'Base',
    frac: _fullRect,
    fill: FillAspect(color: t.baseColor),
  ));

  // background image (optional) — over base, under tint; as-is cover-fit.
  if (t.bgImageId != null) {
    layers.add(Layer(
      id: kBgLayerId,
      name: 'Background',
      frac: _fullRect,
      image: ImageAspect(
        source: ImageSource.fixed,
        imageId: t.bgImageId!,
        transform: t.bgTransform,
      ),
    ));
  }

  // tint — full-card fill slot; the value + alpha are PER-CARD (read at render).
  // Exposed to the colour tab. The placeholder colour is ignored by the renderer
  // for this slot (it uses the card's tint).
  layers.add(Layer(
    id: kTintLayerId,
    name: 'Tint',
    frac: _fullRect,
    fill: FillAspect(color: t.baseColor),
    exposed: const {ExposedAspect.fill: EditorTab.color},
  ));

  // fields — each becomes one layer, KEEPING the field id (zero per-card re-key).
  for (final f in t.fields) {
    layers.add(_fieldToLayer(f));
  }

  // set symbol — template-placed image, source=setSymbol (rarity-tinted per
  // card). visible mirrors the placement's enabled flag.
  layers.add(Layer(
    id: kSetSymbolLayerId,
    name: 'Set symbol',
    visible: t.setSymbol.enabled,
    frac: t.setSymbol.frac,
    image: ImageAspect(
      source: ImageSource.setSymbol,
      alpha: t.setSymbol.alpha,
    ),
    exposed: const {ExposedAspect.image: EditorTab.set},
  ));

  // foil — full-card overlay slot; the FoilType is PER-CARD (renderer reads
  // card.foil for this slot).
  layers.add(const Layer(
    id: kFoilLayerId,
    name: 'Foil',
    frac: _fullRect,
  ));

  // outer border — pure white/black chrome, drawn OUTSIDE the rounded clip, on
  // top. Present as a top slot so it shows in the Layers list; the renderer
  // special-cases it and reads the template BorderSpec. Not freely reorderable
  // below content in Phase 1 (outside-clip special case).
  if (t.border != null) {
    layers.add(const Layer(
      id: kBorderLayerId,
      name: 'Border',
      frac: _fullRect,
    ));
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
    text: f.text == null ? null : TextAspect(style: f.text!),
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
