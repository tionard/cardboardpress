part of 'card_model.dart';

// Standalone domain entities surfaced to the UI: palette swatch, rarity,
// text symbol, standalone symbol, and set.

/// A palette entry as the UI/state layer sees it: identity + name + the colour
/// value. This is the domain shape; the drift row is mapped into this so
/// features never import database types directly.
class PaletteSwatch {
  final String id;
  final String name;
  final ColorValue value;
  // Usage tags — which picker contexts show this swatch by default. Filter,
  // not forbid: pickers always offer "show all". Default all-on.
  final bool tagCard;
  final bool tagText;
  final bool tagSymbol;

  const PaletteSwatch({
    required this.id,
    required this.name,
    required this.value,
    this.tagCard = true,
    this.tagText = true,
    this.tagSymbol = true,
  });

  PaletteSwatch copyWith({
    String? name,
    ColorValue? value,
    bool? tagCard,
    bool? tagText,
    bool? tagSymbol,
  }) =>
      PaletteSwatch(
        id: id,
        name: name ?? this.name,
        value: value ?? this.value,
        tagCard: tagCard ?? this.tagCard,
        tagText: tagText ?? this.tagText,
        tagSymbol: tagSymbol ?? this.tagSymbol,
      );
}

/// A rarity (spec §3): name + 1–3-letter abbreviation. (Its palette colour and
/// snapshot-on-delete ref are added when a rarity editor exists.)
class RarityEntry {
  final String id;
  final String name;
  final String abbreviation;
  final int position;
  final ColorRef? color; // tints the set symbol (single or double); null => none

  const RarityEntry({
    required this.id,
    required this.name,
    this.abbreviation = '',
    this.position = 0,
    this.color,
  });
}

/// An inline text symbol (spec §3.2): a `{tag}` that renders as a glyph image.
/// Tags are matched case-insensitively; [imageId] points into the ImageStore.
class TextSymbolEntry {
  final String id;
  final String tag;
  final String imageId;
  final int position;

  const TextSymbolEntry({
    required this.id,
    required this.tag,
    required this.imageId,
    this.position = 0,
  });
}

/// A standalone symbol (spec §3.3): a graphic used only as a set symbol or a
/// watermark — not inline, not composable. Just a name + image; any colour tint
/// (rarity colour for a set symbol, palette colour for a watermark) is applied
/// at the render site, never stored here.
class SymbolEntry {
  final String id;
  final String name;
  final String imageId;
  final int position;

  const SymbolEntry({
    required this.id,
    required this.name,
    required this.imageId,
    this.position = 0,
  });
}

/// A set (Collection folder): name + footer-feeding metadata + numbering.
/// "Unassigned" is not stored — it's the null-setId bucket, always shown first.
class SetEntry {
  final String id;
  final String name;
  final String abbreviation;
  final int year;
  final String owner;
  final bool numbering;
  final int position;
  final String? symbolId; // chosen standalone symbol (set symbol); null => none

  const SetEntry({
    required this.id,
    required this.name,
    this.abbreviation = '',
    this.year = 2026,
    this.owner = '',
    this.numbering = true,
    this.position = 0,
    this.symbolId,
  });
}

/// A Frames-library entry: a 9-slice sprite plus its slicing definition (per-
/// edge source cuts + tile modes). The library OWNS the slicing — templates
/// reference a frame by id and keep only use-site properties (thickness,
/// drawCenter, tint) on their border aspect. Editing a frame here updates
/// every referencing template live; deleting one leaves referencing templates
/// rendering from the snapshot they took when the frame was picked.
class FrameEntry {
  final String id;
  final String name;
  final String imageId;
  final double insetL; // source cut, fraction of source WIDTH, 0..0.49
  final double insetT; // source cut, fraction of source HEIGHT, 0..0.49
  final double insetR; // source cut, fraction of source WIDTH, 0..0.49
  final double insetB; // source cut, fraction of source HEIGHT, 0..0.49
  final SliceFillMode edgeMode;
  final SliceFillMode centerMode;
  final int position;

  const FrameEntry({
    required this.id,
    required this.name,
    required this.imageId,
    this.insetL = 0.33,
    this.insetT = 0.33,
    this.insetR = 0.33,
    this.insetB = 0.33,
    this.edgeMode = SliceFillMode.stretch,
    this.centerMode = SliceFillMode.stretch,
    this.position = 0,
  });

  /// Overlays this frame's library-owned values (reference id + image + cuts +
  /// modes) onto a use-site spec, preserving the spec's own thickness,
  /// drawCenter, and tint. THE single overlay definition — used both when a
  /// frame is picked in the template editor (baking the snapshot) and when the
  /// live library value resolves at compose time.
  NineSliceSpec applyTo(NineSliceSpec use) => use.copyWith(
        frameId: id,
        imageId: imageId,
        insetL: insetL,
        insetT: insetT,
        insetR: insetR,
        insetB: insetB,
        edgeMode: edgeMode,
        centerMode: centerMode,
      );

  /// A ready-to-paint spec for library previews (grid tiles, the slicing
  /// editor). [thickness] is representative only — the real value is per-use.
  NineSliceSpec previewSpec({double thickness = 0.08}) =>
      applyTo(NineSliceSpec(thickness: thickness));
}
