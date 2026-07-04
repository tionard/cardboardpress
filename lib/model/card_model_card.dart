part of 'card_model.dart';

// A single card: the composed render model (CardData) + its reference
// resolver (CardRefs), the authored content, and the persisted entry.

class CardData {
  final double widthInches;
  final double heightInches;
  final double cornerRadiusFrac; // card corner radius as fraction of width
  final ColorRef baseColor;
  final ColorRef? tint; // optional per-card tint over the base
  final double tintAlpha; // 0..1 opacity of the tint
  final BorderSpec? border;
  final List<FieldSpec> fields;
  final FoilType foil;
  final Map<String, String> textContent; // fieldId -> text
  final Map<String, String> artImageIds; // fieldId -> image id
  final Map<String, ArtTransform> artTransforms; // fieldId -> zoom/pan
  final String? bgImageId; // template background image, drawn under the tint
  final ArtTransform bgTransform; // cover-fit zoom/pan for the bg image
  final Map<String, String> symbolImageIds; // text-symbol tag (lower) -> imageId
  final String? setSymbolImageId; // resolved set-symbol image (from the set)
  final SetSymbolPlacement? setSymbolPlacement; // where/how it draws (template)
  final ColorRef? setSymbolTint; // rarity colour tinting the set symbol; null => none
  final Map<String, String> watermarkImageIds; // fieldId -> resolved watermark image
  final Map<FooterComponent, String> footerValues; // derived footer pieces (per card)
  final List<String> layerOrder; // z-order overlay (layer ids); [] = derived
  final List<String> hiddenLayers; // hidden layer ids; [] = all visible
  final List<Layer>? layers; // persisted layer list; null = derive from fields
  final Map<String, ColorRef> fillColors; // layerId -> per-card fill override
  final Map<String, ColorRef> outlineColors; // layerId -> per-card outline colour
  final Set<String> cardHiddenLayers; // layerIds this card hides (per-card)
  final Map<String, FoilType> foilOverrides; // layerId -> per-card foil

  const CardData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.tint,
    this.tintAlpha = 1.0,
    this.border,
    required this.fields,
    this.foil = FoilType.none,
    this.textContent = const {},
    this.artImageIds = const {},
    this.artTransforms = const {},
    this.bgImageId,
    this.bgTransform = const ArtTransform(),
    this.symbolImageIds = const {},
    this.setSymbolImageId,
    this.setSymbolPlacement,
    this.setSymbolTint,
    this.watermarkImageIds = const {},
    this.footerValues = const {},
    this.layerOrder = const [],
    this.hiddenLayers = const [],
    this.layers,
    this.fillColors = const {},
    this.outlineColors = const {},
    this.cardHiddenLayers = const {},
    this.foilOverrides = const {},
  });

  /// Every image id the renderer needs decoded: card art, the template
  /// background, and the glyphs for any {tag} used in symbol-bearing fields.
  /// Render sites decode these into [CardRefs.images] before painting.
  Set<String> imageIdsToDecode() {
    final ids = <String>{
      ...artImageIds.values,
      ?bgImageId,
      ?setSymbolImageId,
      ...watermarkImageIds.values,
    };
    // Persisted generic layers can carry their own fixed template image (a
    // decorative picture or a tinted silhouette); decode those too.
    if (layers != null) {
      for (final l in layers!) {
        final img = l.image;
        if (img != null &&
            img.source == ImageSource.fixed &&
            img.imageId.isNotEmpty) {
          ids.add(img.imageId);
        }
        final b = l.border;
        if (b != null && b.imageId.isNotEmpty) ids.add(b.imageId);
      }
    }
    for (final f in fields) {
      final fr = f.frame;
      if (fr != null && fr.imageId.isNotEmpty) ids.add(fr.imageId);
      if (f.type != FieldType.cost && f.type != FieldType.rules) continue;
      final content = textContent[f.id];
      if (content == null) continue;
      for (final tag in referencedTags(content)) {
        final id = symbolImageIds[tag];
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }
}

/// Resolves references (palette colours today; template, rarity, symbols later)
/// to their live value *or a retained snapshot* if the target was deleted
/// (spec §1, §8).
///
/// This is a plain value object the UI builds from the current palette and
/// hands to `paintCard`. It keeps the renderer PURE — `paintCard` asks the
/// resolver for a value and never sees a dangling reference or touches storage.
class CardRefs {
  /// Current palette: colour id -> live value.
  final Map<String, ColorValue> palette;

  /// Decoded art images: image id -> ui.Image. Pre-decoded by the widget layer
  /// (paintCard is synchronous, so it never loads/decodes images itself).
  final Map<String, Image> images;

  /// Template-preview only: when true, a text aspect with no resolved content
  /// falls back to its [TextAspect.placeholder] so the author can size/position.
  /// Real card renders and exports leave this false.
  final bool showPlaceholders;

  const CardRefs(
      {this.palette = const {},
      this.images = const {},
      this.showPlaceholders = false});

  /// Live value if the referenced colour still exists, else the snapshot.
  ColorValue resolveColor(ColorRef ref) {
    final id = ref.id;
    if (id != null) {
      final live = palette[id];
      if (live != null) return live;
    }
    return ref.snapshot;
  }

  /// The decoded image for [imageId], or null if absent / not yet loaded.
  Image? resolveImage(String? imageId) =>
      imageId == null ? null : images[imageId];
}

/// A card's authored content, keyed by field id. Today it's just per-field
/// text; art images, artist credit, stat values, etc. join later.
class CardContent {
  final Map<String, String> text; // fieldId -> text value
  final Map<String, String> art; // fieldId -> image id
  final Map<String, ArtTransform> artTransforms; // fieldId -> zoom/pan
  final ColorRef? tint; // optional per-card base-colour override
  final double tintAlpha; // 0..1 opacity of the tint over the base
  final String artist; // per-card; rendered by the Footer
  final String? rarityId; // live rarity reference (footer abbreviation)
  final Map<String, ColorRef> fillColors; // layerId -> per-card fill override
  final Map<String, ColorRef> outlineColors; // layerId -> per-card outline colour
  final Set<String> cardHiddenLayers; // layerIds this card hides (per-card)
  final Map<String, FoilType> foilOverrides; // layerId -> per-card foil

  const CardContent({
    this.text = const {},
    this.art = const {},
    this.artTransforms = const {},
    this.tint,
    this.tintAlpha = 1.0,
    this.artist = '',
    this.rarityId,
    this.fillColors = const {},
    this.outlineColors = const {},
    this.cardHiddenLayers = const {},
    this.foilOverrides = const {},
  });

  CardContent _copy({
    Map<String, String>? text,
    Map<String, String>? art,
    Map<String, ArtTransform>? artTransforms,
    Object? tint = _sentinel,
    double? tintAlpha,
    String? artist,
    Object? rarityId = _sentinel,
    Map<String, ColorRef>? fillColors,
    Map<String, ColorRef>? outlineColors,
    Set<String>? cardHiddenLayers,
    Map<String, FoilType>? foilOverrides,
  }) =>
      CardContent(
        text: text ?? this.text,
        art: art ?? this.art,
        artTransforms: artTransforms ?? this.artTransforms,
        tint: identical(tint, _sentinel) ? this.tint : tint as ColorRef?,
        tintAlpha: tintAlpha ?? this.tintAlpha,
        artist: artist ?? this.artist,
        rarityId:
            identical(rarityId, _sentinel) ? this.rarityId : rarityId as String?,
        fillColors: fillColors ?? this.fillColors,
        outlineColors: outlineColors ?? this.outlineColors,
        cardHiddenLayers: cardHiddenLayers ?? this.cardHiddenLayers,
        foilOverrides: foilOverrides ?? this.foilOverrides,
      );

  /// Set (or clear, when [foil] is null) the per-card foil for a layer.
  CardContent withLayerFoil(String layerId, FoilType? foil) {
    final next = Map<String, FoilType>.from(foilOverrides);
    (foil == null || foil == FoilType.none)
        ? next.remove(layerId)
        : next[layerId] = foil;
    return _copy(foilOverrides: next);
  }

  /// Show/hide a layer on this card only (per-card visibility override).
  CardContent withLayerHidden(String layerId, bool hidden) {
    final next = Set<String>.from(cardHiddenLayers);
    hidden ? next.add(layerId) : next.remove(layerId);
    return _copy(cardHiddenLayers: next);
  }

  /// Set (or clear, when [ref] is null) the per-card fill colour for a layer.
  CardContent withFillColor(String layerId, ColorRef? ref) {
    final next = Map<String, ColorRef>.from(fillColors);
    ref == null ? next.remove(layerId) : next[layerId] = ref;
    return _copy(fillColors: next);
  }

  /// Set (or clear, when [ref] is null) the per-card outline colour for a layer.
  CardContent withOutlineColor(String layerId, ColorRef? ref) {
    final next = Map<String, ColorRef>.from(outlineColors);
    ref == null ? next.remove(layerId) : next[layerId] = ref;
    return _copy(outlineColors: next);
  }

  CardContent withText(String fieldId, String value) {
    final next = Map<String, String>.from(text);
    next[fieldId] = value;
    return _copy(text: next);
  }

  /// Set (or clear, when [imageId] is null) the art image for a field. Clearing
  /// also drops any zoom/pan for that field.
  CardContent withArt(String fieldId, String? imageId) {
    final next = Map<String, String>.from(art);
    final nextT = Map<String, ArtTransform>.from(artTransforms);
    if (imageId == null) {
      next.remove(fieldId);
      nextT.remove(fieldId);
    } else {
      next[fieldId] = imageId;
    }
    return _copy(art: next, artTransforms: nextT);
  }

  /// Set the zoom/pan for a field's art.
  CardContent withArtTransform(String fieldId, ArtTransform t) {
    final next = Map<String, ArtTransform>.from(artTransforms);
    if (t.isIdentity) {
      next.remove(fieldId);
    } else {
      next[fieldId] = t;
    }
    return _copy(artTransforms: next);
  }

  /// Set (or clear, when [ref] is null) the card's tint.
  CardContent withTint(ColorRef? ref) => _copy(tint: ref);

  CardContent withTintAlpha(double a) => _copy(tintAlpha: a);

  CardContent withArtist(String value) => _copy(artist: value);

  /// Set (or clear, when [id] is null) the card's rarity reference.
  CardContent withRarity(String? id) => _copy(rarityId: id);
}

/// A persisted card as the UI/state layer sees it. The template is a reference:
/// [templateId] is the live link; [templateSnapshot] is the retained fallback
/// (spec §1, §8) so deleting a template never breaks the card.
class CardEntry {
  final String id;
  final String? templateId;
  final TemplateData templateSnapshot;
  final CardContent content;
  final FoilType foil;
  final String? setId; // null => Unassigned

  const CardEntry({
    required this.id,
    required this.templateId,
    required this.templateSnapshot,
    required this.content,
    this.foil = FoilType.none,
    this.setId,
  });

  /// The layout to draw with: the live template if it still exists, else the
  /// snapshot. (Mirrors ColorRef resolution, at the template level.)
  TemplateData effectiveTemplate(Map<String, TemplateData> liveTemplates) {
    final id = templateId;
    if (id != null) {
      final live = liveTemplates[id];
      if (live != null) return live;
    }
    return templateSnapshot;
  }

  CardEntry copyWith({
    String? templateId,
    TemplateData? templateSnapshot,
    CardContent? content,
    FoilType? foil,
    Object? setId = _sentinel,
  }) =>
      CardEntry(
        id: id,
        templateId: templateId ?? this.templateId,
        templateSnapshot: templateSnapshot ?? this.templateSnapshot,
        content: content ?? this.content,
        foil: foil ?? this.foil,
        setId: identical(setId, _sentinel) ? this.setId : setId as String?,
      );
}
