part of 'card_model.dart';

// A template's layout (geometry, base colour, border, fields, background,
// set-symbol placement) and its persisted entry.

/// A template's layout (spec §3): card geometry, base colour, optional border,
/// and the ordered fields. It holds NO text content — that's per-card. A card
/// composes a TemplateData with its content into a [CardData] for rendering.
class TemplateData {
  final double widthInches;
  final double heightInches;
  final double cornerRadiusFrac;
  final ColorRef baseColor;
  final BorderSpec? border;
  final List<FieldSpec> fields;
  final String? bgImageId; // optional background image, drawn UNDER the tint
  final ArtTransform bgTransform; // cover-fit zoom/pan for the bg image
  final SetSymbolPlacement setSymbol; // where the set symbol draws (layout)

  const TemplateData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.border,
    required this.fields,
    this.bgImageId,
    this.bgTransform = const ArtTransform(),
    this.setSymbol = const SetSymbolPlacement(),
  });

  TemplateData copyWith({
    double? widthInches,
    double? heightInches,
    double? cornerRadiusFrac,
    ColorRef? baseColor,
    Object? border = _sentinel, // pass null to clear the border
    List<FieldSpec>? fields,
    Object? bgImageId = _sentinel, // pass null to clear the bg image
    ArtTransform? bgTransform,
    SetSymbolPlacement? setSymbol,
  }) =>
      TemplateData(
        widthInches: widthInches ?? this.widthInches,
        heightInches: heightInches ?? this.heightInches,
        cornerRadiusFrac: cornerRadiusFrac ?? this.cornerRadiusFrac,
        baseColor: baseColor ?? this.baseColor,
        border: identical(border, _sentinel) ? this.border : border as BorderSpec?,
        fields: fields ?? this.fields,
        bgImageId:
            identical(bgImageId, _sentinel) ? this.bgImageId : bgImageId as String?,
        bgTransform: bgTransform ?? this.bgTransform,
        setSymbol: setSymbol ?? this.setSymbol,
      );
}

/// A persisted template as the UI/state layer sees it: identity + name + the
/// layout. (The drift row is mapped into this so features never import db types.)
class TemplateEntry {
  final String id;
  final String name;
  final TemplateData data;

  const TemplateEntry({
    required this.id,
    required this.name,
    required this.data,
  });

  TemplateEntry copyWith({String? name, TemplateData? data}) => TemplateEntry(
        id: id,
        name: name ?? this.name,
        data: data ?? this.data,
      );
}
