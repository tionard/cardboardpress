// lib/model/serialization.dart
//
// JSON encode/decode for the structured value objects we store as a single DB
// column (a template's whole layout). Pure Dart — no widgets, no drift.
//
// Two principles for resilient loading (spec §3, §8 "older saves load safely"):
//   * Every decoder supplies a SAFE DEFAULT for a missing/!invalid field, so an
//     older or partial save never throws.
//   * The map carries a 'v' (shape version) we can branch on if the JSON shape
//     ever changes — separate from drift's table-level schemaVersion.

import 'dart:convert';
import 'dart:ui';

import 'card_model.dart';
import 'layers.dart';

// Look up an enum by its .name with a fallback (never throws on bad data).
T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double _d(Object? v, double fallback) => (v is num) ? v.toDouble() : fallback;
int _i(Object? v, int fallback) => (v is num) ? v.toInt() : fallback;
bool _b(Object? v, bool fallback) => (v is bool) ? v : fallback;

// ---- ColorValue ----
Map<String, dynamic> _colorValueToMap(ColorValue v) => {
      'c1': v.c1.toARGB32(),
      if (v.c2 != null) 'c2': v.c2!.toARGB32(),
      'orientation': v.orientation.name,
      'mix': v.mix,
    };

ColorValue _colorValueFromMap(Map m) {
  final c1 = Color(_i(m['c1'], 0xFF000000));
  final c2 = m['c2'];
  if (c2 == null) return ColorValue.single(c1);
  return ColorValue.duo(
    c1,
    Color(_i(c2, 0xFF000000)),
    orientation: _byName(MixOrientation.values, m['orientation'], MixOrientation.vertical),
    mix: _d(m['mix'], 0.3),
  );
}

// ---- ColorRef ----
Map<String, dynamic> _colorRefToMap(ColorRef r) => {
      if (r.id != null) 'id': r.id,
      'snapshot': _colorValueToMap(r.snapshot),
    };

ColorRef _colorRefFromMap(Map m) => ColorRef(
      id: m['id'] as String?,
      snapshot: _colorValueFromMap((m['snapshot'] as Map?) ?? const {}),
    );

/// Public ColorRef <-> JSON string, for columns that store a single colour
/// reference (e.g. a rarity's tint colour).
String colorRefToJson(ColorRef r) => jsonEncode(_colorRefToMap(r));

ColorRef colorRefFromJson(String s) =>
    _colorRefFromMap(jsonDecode(s) as Map<String, dynamic>);

// ---- OutlineSpec ----
Map<String, dynamic> _outlineToMap(OutlineSpec o) =>
    {'lighter': o.lighter, 'intensity': o.intensity, 'thickness': o.thickness};

OutlineSpec _outlineFromMap(Map m) => OutlineSpec(
      lighter: _b(m['lighter'], false),
      intensity: _d(m['intensity'], 0.4),
      thickness: _d(m['thickness'], 0.004),
    );

// ---- TextStyleSpec ----
Map<String, dynamic> _textToMap(TextStyleSpec t) => {
      'sizeFrac': t.sizeFrac,
      'bold': t.bold,
      'italic': t.italic,
      'align': t.align.name,
      'vAlign': t.vAlign.name,
      'colorRef': _colorRefToMap(t.colorRef),
      'colorAlpha': t.colorAlpha,
      'fit': t.fit.name,
      'padX': t.padX,
      'padY': t.padY,
    };

TextStyleSpec _textFromMap(Map m) => TextStyleSpec(
      sizeFrac: _d(m['sizeFrac'], 0.03),
      bold: _b(m['bold'], false),
      italic: _b(m['italic'], false),
      align: _byName(TextAlign.values, m['align'], TextAlign.left),
      vAlign: _byName(VAlign.values, m['vAlign'], VAlign.top),
      colorRef: _colorRefFromMap((m['colorRef'] as Map?) ?? const {}),
      colorAlpha: _d(m['colorAlpha'], 1.0),
      fit: _byName(TextFit.values, m['fit'], TextFit.fixed),
      padX: _d(m['padX'], 0.04),
      padY: _d(m['padY'], 0.0),
    );

// ---- BorderSpec ----
Map<String, dynamic> _borderToMap(BorderSpec b) =>
    {'black': b.black, 'thickness': b.thickness};

BorderSpec _borderFromMap(Map m) =>
    BorderSpec(black: _b(m['black'], true), thickness: _d(m['thickness'], 0.02));

// ---- FieldSpec ----
Map<String, dynamic> _fieldToMap(FieldSpec f) => {
      'id': f.id,
      'type': f.type.name,
      'frac': [f.frac.left, f.frac.top, f.frac.right, f.frac.bottom],
      'cornerRadius': f.cornerRadius,
      if (f.fill != null) 'fill': _colorRefToMap(f.fill!),
      'fillAlpha': f.fillAlpha,
      if (f.outline != null) 'outline': _outlineToMap(f.outline!),
      if (f.text != null) 'text': _textToMap(f.text!),
      if (f.watermark != null)
        'wm': {
          'sym': f.watermark!.symbolId,
          'color': _colorRefToMap(f.watermark!.color),
          'a': f.watermark!.alpha,
        },
      if (f.footer != null) 'footer': _footerToMap(f.footer!),
      if (f.frame != null)
        'frame': {
          'img': f.frame!.imageId,
          'slice': f.frame!.slice,
          'inset': f.frame!.inset,
          'center': f.frame!.drawCenter,
          if (f.frame!.tint != null) 'tint': _colorRefToMap(f.frame!.tint!),
        },
    };

FieldSpec _fieldFromMap(Map m) {
  final raw = (m['frac'] as List?) ?? const [0.0, 0.0, 1.0, 1.0];
  final f = raw.map((e) => _d(e, 0.0)).toList();
  final type = _byName(FieldType.values, m['type'], FieldType.name);
  // Legacy: 'sharp' used to force square corners regardless of cornerRadius.
  // It's gone now — fold it into cornerRadius so old square fields stay square.
  final cornerRadius = _b(m['sharp'], false) ? 0.0 : _d(m['cornerRadius'], 0.02);
  return FieldSpec(
    id: (m['id'] as String?) ?? 'f_${type.name}',
    type: type,
    frac: Rect.fromLTRB(f[0], f[1], f[2], f[3]),
    cornerRadius: cornerRadius,
    fill: m['fill'] == null ? null : _colorRefFromMap(m['fill'] as Map),
    fillAlpha: _d(m['fillAlpha'], 1.0),
    outline: m['outline'] == null ? null : _outlineFromMap(m['outline'] as Map),
    text: m['text'] == null ? null : _textFromMap(m['text'] as Map),
    watermark: m['wm'] == null ? null : _watermarkFromMap(m['wm'] as Map),
    footer: m['footer'] == null ? null : _footerFromMap(m['footer'] as Map),
    frame: m['frame'] == null ? null : _nineSliceFromMap(m['frame'] as Map),
  );
}

NineSliceSpec _nineSliceFromMap(Map m) => NineSliceSpec(
      imageId: (m['img'] as String?) ?? '',
      slice: _d(m['slice'], 0.33),
      inset: _d(m['inset'], 0.06),
      drawCenter: _b(m['center'], true),
      tint: m['tint'] == null ? null : _colorRefFromMap(m['tint'] as Map),
    );

WatermarkSpec _watermarkFromMap(Map m) => WatermarkSpec(
      symbolId: (m['sym'] as String?) ?? '',
      color: _colorRefFromMap((m['color'] as Map?) ?? const {}),
      alpha: _d(m['a'], 0.15),
    );

// ---- FooterSpec ----
Map<String, dynamic> _footerToMap(FooterSpec f) => {
      'mode': f.mode.name,
      'items': [
        for (final it in f.items) {'c': it.component.name, 'z': it.zone.name},
      ],
    };

FooterSpec _footerFromMap(Map m) => FooterSpec(
      mode: _byName(FooterMode.values, m['mode'], FooterMode.singleLine),
      items: [
        for (final raw in (m['items'] as List? ?? const []))
          FooterItem(
            _byName(FooterComponent.values, (raw as Map)['c'],
                FooterComponent.number),
            _byName(FooterZone.values, raw['z'], FooterZone.line),
          ),
      ],
    );

// ---- TemplateData ----
Map<String, dynamic> templateToMap(TemplateData t) => {
      'v': 1,
      'widthInches': t.widthInches,
      'heightInches': t.heightInches,
      'cornerRadiusFrac': t.cornerRadiusFrac,
      'baseColor': _colorRefToMap(t.baseColor),
      if (t.border != null) 'border': _borderToMap(t.border!),
      'fields': t.fields.map(_fieldToMap).toList(),
      if (t.bgImageId != null) 'bgImage': t.bgImageId,
      if (!t.bgTransform.isIdentity)
        'bgT': {
          'z': t.bgTransform.zoom,
          'x': t.bgTransform.panX,
          'y': t.bgTransform.panY,
        },
      if (!t.setSymbol.isDefault)
        'setSym': {
          'on': t.setSymbol.enabled,
          'f': [
            t.setSymbol.frac.left,
            t.setSymbol.frac.top,
            t.setSymbol.frac.right,
            t.setSymbol.frac.bottom,
          ],
          'a': t.setSymbol.alpha,
        },
      if (t.layerOrder.isNotEmpty) 'layerOrder': t.layerOrder,
      if (t.hiddenLayers.isNotEmpty) 'hidden': t.hiddenLayers,
      // Persisted layer list (Phase 4). Absent key = null = derive from fields,
      // so every existing template's JSON is unchanged and reloads identically.
      if (t.layers != null)
        'layers': [for (final l in t.layers!) _layerToMap(l)],
    };

TemplateData templateFromMap(Map m) => TemplateData(
      widthInches: _d(m['widthInches'], 2.5),
      heightInches: _d(m['heightInches'], 3.5),
      cornerRadiusFrac: _d(m['cornerRadiusFrac'], 0.05),
      baseColor: _colorRefFromMap((m['baseColor'] as Map?) ?? const {}),
      border: m['border'] == null ? null : _borderFromMap(m['border'] as Map),
      fields: ((m['fields'] as List?) ?? const [])
          .map((e) => _fieldFromMap(e as Map))
          .toList(),
      bgImageId: m['bgImage'] as String?,
      bgTransform: m['bgT'] == null
          ? const ArtTransform()
          : ArtTransform(
              zoom: _d((m['bgT'] as Map)['z'], 1.0),
              panX: _d((m['bgT'] as Map)['x'], 0.0),
              panY: _d((m['bgT'] as Map)['y'], 0.0),
            ),
      setSymbol: _setSymbolFromMap(m['setSym'] as Map?),
      layerOrder: _strList(m['layerOrder']),
      hiddenLayers: _strList(m['hidden']),
      layers: m['layers'] == null
          ? null
          : [for (final e in (m['layers'] as List)) _layerFromMap(e as Map)],
    );

List<String> _strList(Object? v) =>
    v is List ? [for (final e in v) '$e'] : const [];

SetSymbolPlacement _setSymbolFromMap(Map? m) {
  if (m == null) return const SetSymbolPlacement();
  final raw = (m['f'] as List?) ?? const [];
  final f = raw.map((e) => _d(e, 0.0)).toList();
  final frac = f.length == 4
      ? Rect.fromLTRB(f[0], f[1], f[2], f[3])
      : SetSymbolPlacement.defaultFrac;
  return SetSymbolPlacement(
    enabled: _b(m['on'], false),
    frac: frac,
    alpha: _d(m['a'], 1.0),
  );
}

String templateToJson(TemplateData t) => jsonEncode(templateToMap(t));

TemplateData templateFromJson(String s) =>
    templateFromMap(jsonDecode(s) as Map<String, dynamic>);

// ---- CardContent ----
Map<String, dynamic> cardContentToMap(CardContent c) => {
      'v': 1,
      'text': c.text,
      'art': c.art,
      if (c.artTransforms.isNotEmpty)
        'artT': {
          for (final e in c.artTransforms.entries)
            e.key: {'z': e.value.zoom, 'x': e.value.panX, 'y': e.value.panY},
        },
      if (c.tint != null) 'tint': _colorRefToMap(c.tint!),
      if (c.tintAlpha != 1.0) 'tintA': c.tintAlpha,
      if (c.artist.isNotEmpty) 'artist': c.artist,
      if (c.rarityId != null) 'rarityId': c.rarityId,
    };

CardContent cardContentFromMap(Map m) {
  final t = (m['text'] as Map?) ?? const {};
  final a = (m['art'] as Map?) ?? const {};
  final at = (m['artT'] as Map?) ?? const {};
  return CardContent(
    text: {for (final e in t.entries) e.key.toString(): '${e.value}'},
    art: {for (final e in a.entries) e.key.toString(): '${e.value}'},
    artTransforms: {
      for (final e in at.entries)
        e.key.toString(): ArtTransform(
          zoom: _d((e.value as Map)['z'], 1.0),
          panX: _d((e.value as Map)['x'], 0.0),
          panY: _d((e.value as Map)['y'], 0.0),
        ),
    },
    tint: m['tint'] == null ? null : _colorRefFromMap(m['tint'] as Map),
    tintAlpha: _d(m['tintA'], 1.0),
    artist: (m['artist'] as String?) ?? '',
    rarityId: m['rarityId'] as String?,
  );
}

String cardContentToJson(CardContent c) => jsonEncode(cardContentToMap(c));

CardContent cardContentFromJson(String s) =>
    cardContentFromMap(jsonDecode(s) as Map<String, dynamic>);

// ---- Layer (layer redesign) ----
// A template's layer list stored as one JSON column (schema v12). Aspects reuse
// the same encoders as FieldSpec, so the shapes match the proven ones.

T? _byNameOrNull<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

Map<String, dynamic> _layerToMap(Layer l) => {
      'id': l.id,
      'name': l.name,
      if (!l.visible) 'hidden': true,
      'kind': l.kind.name,
      'frac': [l.frac.left, l.frac.top, l.frac.right, l.frac.bottom],
      'cr': l.cornerRadius,
      if (l.fill != null)
        'fill': {'color': _colorRefToMap(l.fill!.color), 'a': l.fill!.alpha},
      if (l.image != null)
        'image': {
          'src': l.image!.source.name,
          if (l.image!.imageId.isNotEmpty) 'img': l.image!.imageId,
          if (l.image!.tint != null) 'tint': _colorRefToMap(l.image!.tint!),
          'a': l.image!.alpha,
          if (!l.image!.transform.isIdentity)
            't': {
              'z': l.image!.transform.zoom,
              'x': l.image!.transform.panX,
              'y': l.image!.transform.panY,
            },
        },
      if (l.border != null)
        'border': {
          'img': l.border!.imageId,
          'slice': l.border!.slice,
          'inset': l.border!.inset,
          'center': l.border!.drawCenter,
          if (l.border!.tint != null) 'tint': _colorRefToMap(l.border!.tint!),
        },
      if (l.outline != null) 'outline': _outlineToMap(l.outline!),
      if (l.foil != FoilType.none) 'foil': l.foil.name,
      if (l.text != null)
        'text': {
          'style': _textToMap(l.text!.style),
          if (l.text!.literal != null) 'lit': l.text!.literal,
          if (l.text!.inline) 'inline': true,
        },
      if (l.watermark != null)
        'wm': {
          'sym': l.watermark!.symbolId,
          'color': _colorRefToMap(l.watermark!.color),
          'a': l.watermark!.alpha,
        },
      if (l.footer != null) 'footer': _footerToMap(l.footer!),
      if (l.exposed.isNotEmpty)
        'exposed': {
          for (final e in l.exposed.entries) e.key.name: e.value.name,
        },
    };

Layer _layerFromMap(Map m) {
  final raw = (m['frac'] as List?) ?? const [0.0, 0.0, 1.0, 1.0];
  final f = raw.map((e) => _d(e, 0.0)).toList();
  final img = m['image'] as Map?;
  final txt = m['text'] as Map?;
  final fillM = m['fill'] as Map?;
  return Layer(
    id: (m['id'] as String?) ?? 'l_${DateTime.now().microsecondsSinceEpoch}',
    name: (m['name'] as String?) ?? '',
    visible: !_b(m['hidden'], false),
    kind: _byName(LayerKind.values, m['kind'], LayerKind.generic),
    frac: Rect.fromLTRB(f[0], f[1], f[2], f[3]),
    cornerRadius: _d(m['cr'], 0.02),
    fill: fillM == null
        ? null
        : FillAspect(
            color: _colorRefFromMap((fillM['color'] as Map?) ?? const {}),
            alpha: _d(fillM['a'], 1.0),
          ),
    image: img == null
        ? null
        : ImageAspect(
            source: _byName(ImageSource.values, img['src'], ImageSource.fixed),
            imageId: (img['img'] as String?) ?? '',
            tint: img['tint'] == null
                ? null
                : _colorRefFromMap(img['tint'] as Map),
            alpha: _d(img['a'], 1.0),
            transform: img['t'] == null
                ? const ArtTransform()
                : ArtTransform(
                    zoom: _d((img['t'] as Map)['z'], 1.0),
                    panX: _d((img['t'] as Map)['x'], 0.0),
                    panY: _d((img['t'] as Map)['y'], 0.0),
                  ),
          ),
    border: m['border'] == null ? null : _nineSliceFromMap(m['border'] as Map),
    outline: m['outline'] == null ? null : _outlineFromMap(m['outline'] as Map),
    foil: _byName(FoilType.values, m['foil'], FoilType.none),
    text: txt == null
        ? null
        : TextAspect(
            style: _textFromMap((txt['style'] as Map?) ?? const {}),
            literal: txt['lit'] as String?,
            inline: _b(txt['inline'], false),
          ),
    watermark: m['wm'] == null ? null : _watermarkFromMap(m['wm'] as Map),
    footer: m['footer'] == null ? null : _footerFromMap(m['footer'] as Map),
    exposed: _exposedFromMap(m['exposed'] as Map?),
  );
}

Map<ExposedAspect, EditorTab> _exposedFromMap(Map? m) {
  if (m == null) return const {};
  final out = <ExposedAspect, EditorTab>{};
  for (final e in m.entries) {
    final aspect = _byNameOrNull(ExposedAspect.values, e.key);
    if (aspect == null) continue; // drop unknown aspects rather than throw
    out[aspect] = _byName(EditorTab.values, e.value, EditorTab.card);
  }
  return out;
}

/// A template's layer list <-> JSON (one column in schema v12).
String layersToJson(List<Layer> layers) =>
    jsonEncode({'v': 1, 'layers': layers.map(_layerToMap).toList()});

List<Layer> layersFromJson(String s) {
  final m = jsonDecode(s) as Map<String, dynamic>;
  return ((m['layers'] as List?) ?? const [])
      .map((e) => _layerFromMap(e as Map))
      .toList();
}

// ---- FoilType <-> stored string ----
String foilToName(FoilType f) => f.name;

FoilType foilFromName(Object? name) =>
    _byName(FoilType.values, name, FoilType.none);
