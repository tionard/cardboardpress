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
      'colorRef': _colorRefToMap(t.colorRef),
      'colorAlpha': t.colorAlpha,
    };

TextStyleSpec _textFromMap(Map m) => TextStyleSpec(
      sizeFrac: _d(m['sizeFrac'], 0.03),
      bold: _b(m['bold'], false),
      italic: _b(m['italic'], false),
      align: _byName(TextAlign.values, m['align'], TextAlign.left),
      colorRef: _colorRefFromMap((m['colorRef'] as Map?) ?? const {}),
      colorAlpha: _d(m['colorAlpha'], 1.0),
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
  );
}

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
    );

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

// ---- FoilType <-> stored string ----
String foilToName(FoilType f) => f.name;

FoilType foilFromName(Object? name) =>
    _byName(FoilType.values, name, FoilType.none);
