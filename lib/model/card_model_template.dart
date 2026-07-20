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

  // Layer redesign (Phase 3): a lightweight arrangement overlay applied to the
  // derived layer list. [layerOrder] is the explicit z-order of layer ids (empty
  // = the derived/default order); [hiddenLayers] is the ids the user has hidden
  // (empty = all visible per their derived default). Field content/styling still
  // lives in [fields]; this only controls arrangement, keyed by stable layer ids.
  final List<String> layerOrder;
  final List<String> hiddenLayers;

  // Layer redesign (Phase 4): the persisted, editable layer list — the source
  // of truth once the template has been authored in the Layers/Fields tabs.
  // NULL means "derive from [fields] (+ the [layerOrder]/[hiddenLayers] overlay)"
  // — the pre-Phase-4 behaviour every existing template keeps until it's first
  // edited into an explicit list. When non-null, list order IS the z-order and
  // each layer carries its own visibility, so the overlay no longer applies.
  // Resolve via `effectiveTemplateLayers` / `effectiveCardLayers` (never read
  // this raw in the renderer). Serialises inside the `spec` JSON — no schema bump.
  final List<Layer>? layers;

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
    this.layerOrder = const [],
    this.hiddenLayers = const [],
    this.layers,
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
    List<String>? layerOrder,
    List<String>? hiddenLayers,
    Object? layers = _sentinel, // pass null to clear back to derived
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
        layerOrder: layerOrder ?? this.layerOrder,
        hiddenLayers: hiddenLayers ?? this.hiddenLayers,
        layers: identical(layers, _sentinel)
            ? this.layers
            : layers as List<Layer>?,
      );
}

/// A persisted template as the UI/state layer sees it: identity + name + the
/// layout. (The drift row is mapped into this so features never import db types.)
/// A template-browser folder. The Collection's sets are the analogue: real
/// rows, so a folder can be created empty and renamed without touching its
/// members. Deleting one is a decision about its templates (delete them, or
/// keep them and unfile), never a cascade — see the browser's delete flow.
class TemplateFolderEntry {
  final String id;
  final String name;
  final int position;

  const TemplateFolderEntry({
    required this.id,
    required this.name,
    this.position = 0,
  });
}

class TemplateEntry {
  final String id;
  final String name;
  final TemplateData data;

  /// Optional folder for browser grouping: a [TemplateFolderEntry] id, or ''
  /// for ungrouped (the default until the user files it). Purely
  /// organisational — nothing in rendering or composition reads this.
  final String folder;

  const TemplateEntry({
    required this.id,
    required this.name,
    required this.data,
    this.folder = '',
  });

  TemplateEntry copyWith({String? name, TemplateData? data, String? folder}) =>
      TemplateEntry(
        id: id,
        name: name ?? this.name,
        data: data ?? this.data,
        folder: folder ?? this.folder,
      );
}
