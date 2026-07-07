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
      cornerRadiusFrac: t.cornerRadiusFrac,
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
      cornerRadiusFrac: c.cornerRadiusFrac,
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

/// The layer id that holds the card's NAME, or null when the template has no
/// name-bearing layer. Prefers the layer derived from the template's Name
/// field (id-stable across promotion); otherwise the first free (unbound) text
/// layer exposed to the Card tab — the closest thing a from-scratch layered
/// template has to a "name". Used by [composeCard] (TextSource.cardName) and
/// the Collection / Card Editor display name, replacing hardcoded field ids.
String? nameTextLayerIdIn(List<Layer> layers, List<FieldSpec> fields) {
  for (final f in fields) {
    if (f.type != FieldType.name) continue;
    for (final l in layers) {
      if (l.id == f.id && l.text != null) return l.id;
    }
  }
  for (final l in layers) {
    final ta = l.text;
    if (ta != null &&
        !ta.isBound &&
        l.exposed[ExposedAspect.text] == EditorTab.card) {
      return l.id;
    }
  }
  return null;
}

/// Convenience over [nameTextLayerIdIn] for a template.
String? nameTextLayerId(TemplateData t) =>
    nameTextLayerIdIn(effectiveTemplateLayers(t), t.fields);

/// The layer list to render for a composed card — the card-side twin of
/// [effectiveTemplateLayers]. This is what the renderer walks. Per-card values
/// are baked onto the layers here so the renderer stays a single untouched path:
/// chrome slots (tint) read the CardData fields, and authored generic layers get
/// their per-card overrides (fill/outline colour, visibility, foil).
List<Layer> effectiveCardLayers(CardData c) {
  final base = c.layers ??
      applyLayerOverlay(cardToLayers(c), c.layerOrder, c.hiddenLayers);
  return [for (final l in base) _resolveCardLayer(l, c)];
}

Layer _resolveCardLayer(Layer l, CardData c) {
  var out = l;

  // Chrome baked from per-card CardData fields. Tint: a full-card fill whose
  // colour+alpha are the card's tint; absent tint hides the slot (nothing drawn,
  // matching the old special-case that only filled when a tint was set).
  if (l.id == kTintLayerId) {
    final tint = c.tint;
    return tint == null
        ? out.copyWith(visible: false)
        : out.copyWith(fill: FillAspect(color: tint, alpha: c.tintAlpha));
  }
  if (l.id == kFoilLayerId) {
    // The card-level foil (Color tab) baked onto the foil slot; none draws
    // nothing, exactly like the old special-case.
    return out.copyWith(foil: c.foil);
  }

  // Per-card overrides on authored generic layers.
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
  required double cornerRadiusFrac,
  required String? bgImageId,
  required ArtTransform bgTransform,
  required List<FieldSpec> fields,
  required SetSymbolPlacement setSymbol,
  required BorderSpec? border,
}) {
  final layers = <Layer>[];

  // base — full-card fill, opaque, bottom. Its corner radius matches the card's
  // so the generic fill draws the same rounded rect the old chrome did (a square
  // clipped to the card would differ in edge antialiasing).
  layers.add(Layer(
    id: kBaseLayerId,
    name: 'Base',
    frac: _fullRect,
    cornerRadius: cornerRadiusFrac,
    fill: FillAspect(color: baseColor),
  ));

  // background image (optional) — over base, under tint; as-is cover-fit.
  if (bgImageId != null) {
    layers.add(Layer(
      id: kBgLayerId,
      name: 'Background',
      frac: _fullRect,
      cornerRadius: cornerRadiusFrac,
      image: ImageAspect(
        source: ImageSource.fixed,
        imageId: bgImageId,
        transform: bgTransform,
      ),
    ));
  }

  // tint — full-card fill slot; value + alpha are PER-CARD (baked in
  // effectiveCardLayers from card.tint). cornerRadius matches the card for exact
  // AA. Not exposed: the per-card tint stays the Color-tab control, so the
  // editable layer here governs placement/presence without a duplicate control.
  layers.add(Layer(
    id: kTintLayerId,
    name: 'Tint',
    frac: _fullRect,
    cornerRadius: cornerRadiusFrac,
    fill: FillAspect(color: baseColor),
  ));

  // fields — each becomes generic layer(s), KEEPING the field id (zero per-card
  // re-key). Footer decomposes into one bound-text layer per live zone.
  for (final f in fields) {
    if (f.type == FieldType.footer) {
      layers.addAll(_footerToLayers(f));
    } else {
      layers.add(_fieldToLayer(f));
    }
  }

  // set symbol — template-placed image, source=setSymbol (rarity-tinted per
  // card, resolved from the card's set). Not exposed: the picture comes from the
  // set, not per-card. Editable as a normal generic layer (placement/size).
  layers.add(Layer(
    id: kSetSymbolLayerId,
    name: 'Set symbol',
    visible: setSymbol.enabled,
    frac: setSymbol.frac,
    image: ImageAspect(
      source: ImageSource.setSymbol,
      alpha: setSymbol.alpha,
    ),
  ));

  // foil — full-card overlay slot; the FoilType is PER-CARD (renderer reads
  // card.foil for this slot).
  layers.add(Layer(
    id: kFoilLayerId,
    name: 'Foil',
    frac: _fullRect,
    cornerRadius: cornerRadiusFrac,
  ));

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
  // Art becomes a generic layer with a per-card image (source=cardArt). It's NOT
  // exposed — the card editor's dedicated Art panel (keyed by the art field id =
  // this layer id) drives the per-card image + transform, so exposing it too
  // would double the control. Other text fields expose text to the Card tab.
  final isArt = f.type == FieldType.art;

  final exposed = <ExposedAspect, EditorTab>{};
  if (!isArt && f.text != null) {
    exposed[ExposedAspect.text] = EditorTab.card;
  }

  return Layer(
    id: f.id, // KEEP the field id (per-card content stays keyed by it)
    name: _fieldName(f.type),
    frac: f.frac,
    cornerRadius: f.cornerRadius,
    fill: f.fill == null ? null : FillAspect(color: f.fill!, alpha: f.fillAlpha),
    image: isArt
        ? const ImageAspect(source: ImageSource.cardArt)
        : null,
    outline: f.outline,
    border: f.frame,
    text: f.text == null
        ? null
        : TextAspect(
            style: f.text!,
            placeholder: _samplePlaceholder(f.type),
            inline: f.type == FieldType.cost || f.type == FieldType.rules,
            multiline: f.type == FieldType.rules || f.type == FieldType.flavor,
          ),
    watermark: f.watermark,
    exposed: exposed,
  );
}

// Footer -> one bound-text layer per live zone. Each zone shares the footer's
// rect and text style; only alignment changes (matching the old zone painter).
List<Layer> _footerToLayers(FieldSpec f) {
  final spec = f.footer ?? const FooterSpec.defaults();
  final ts = f.text;
  if (ts == null) return const [];
  final out = <Layer>[];
  for (final zone in spec.zones) {
    final parts = <TextSource>[
      for (final item in spec.items)
        if (item.zone == zone) _componentToSource(item.component),
    ];
    if (parts.isEmpty) continue;
    final (align, vAlign) = _footerZoneAnchor(zone, ts.align);
    out.add(Layer(
      id: '${f.id}__${zone.name}',
      name: 'Footer ${zone.name}',
      frac: f.frac,
      text: TextAspect(
        style: ts.copyWith(align: align, vAlign: vAlign),
        parts: parts,
        separator: '·',
      ),
    ));
  }
  return out;
}

TextSource _componentToSource(FooterComponent c) => switch (c) {
      FooterComponent.number => TextSource.collectorNumber,
      FooterComponent.set => TextSource.setAbbrev,
      FooterComponent.rarity => TextSource.rarityAbbrev,
      FooterComponent.artist => TextSource.artist,
      FooterComponent.copyright => TextSource.copyright,
    };

// Zone -> (horizontal, vertical) anchor, mirroring the old footer-zone painter.
(TextAlign, VAlign) _footerZoneAnchor(FooterZone zone, TextAlign dflt) =>
    switch (zone) {
      FooterZone.line => (dflt, VAlign.middle),
      FooterZone.left => (TextAlign.left, VAlign.middle),
      FooterZone.right => (TextAlign.right, VAlign.middle),
      FooterZone.topLeft => (TextAlign.left, VAlign.top),
      FooterZone.topRight => (TextAlign.right, VAlign.top),
      FooterZone.bottomLeft => (TextAlign.left, VAlign.bottom),
      FooterZone.bottomRight => (TextAlign.right, VAlign.bottom),
    };

// Representative dummy text so a migrated text layer has something to show in the
// template preview (placeholders are preview-only; never on a real card).
String _samplePlaceholder(FieldType t) => switch (t) {
      FieldType.name => 'Card Name',
      FieldType.alias => 'Alias',
      FieldType.cost => '{G}{G}',
      FieldType.type => 'Type — Subtype',
      FieldType.rules => 'Rules text goes here.',
      FieldType.flavor => 'Flavor text.',
      FieldType.stat => '0/0',
      _ => '',
    };

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
