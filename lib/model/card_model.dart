// lib/model/card_model.dart
//
// PURE value objects describing a card. No Flutter widgets, no Riverpod, no
// platform calls — only `dart:ui` for the plain value types Color/Rect/etc.
// Keeping this layer pure is what lets the SAME data feed the on-screen
// preview, the collection thumbnails, and the print-DPI PNG export.
//
// (For a C# dev: think of these as immutable records / POCOs. `final` fields +
// `const` constructors ≈ readonly value types.)
//
// Split across parts (one library): this root holds the enums + colour types +
// the copyWith _sentinel; the field/positioning specs, template types, card
// types, and standalone entities live in the card_model_{fields,template,card,
// entities}.dart parts. Everything stays one library, so all types see each
// other regardless of file.

import 'dart:ui';

import 'markup.dart';
part 'card_model_fields.dart';
part 'card_model_template.dart';
part 'card_model_card.dart';
part 'card_model_entities.dart';

/// How the two colours of a *double* colour are split across an area.
enum MixOrientation { vertical, horizontal }

/// The nine fixed field types a template can hold (spec §3.6).
/// Note the label is always "art", never "artwork".
enum FieldType { name, alias, cost, type, rules, flavor, stat, art, footer }

/// Foil treatments (spec §3.11). "none" is a first-class option.
enum FoilType { none, holo, gold }

/// A palette colour. Either a single RGB, or two RGB blended along an axis.
///
/// IMPORTANT (spec §3.1): transparency is NOT stored here. Opacity is applied
/// at the *use site* (a tint at 88%, a fill at 70%, …), because the same
/// swatch can be used at different opacities in different places.
class ColorValue {
  final Color c1;
  final Color? c2; // null => single colour
  final MixOrientation orientation;
  final double mix; // 0 = hard edge, 1 = fully soft blend across the span

  const ColorValue.single(this.c1)
      : c2 = null,
        orientation = MixOrientation.vertical,
        mix = 0;

  const ColorValue.duo(
    this.c1,
    Color this.c2, {
    this.orientation = MixOrientation.vertical,
    this.mix = 0.3,
  });

  bool get isDouble => c2 != null;
}

/// A reference to a palette colour (spec §1, §8). Models "live id + retained
/// snapshot": while the referenced palette colour exists, the live value wins;
/// once it's deleted, the [snapshot] keeps dependents rendering. So deleting a
/// palette colour never breaks a card.
class ColorRef {
  final String? id; // palette colour id, or null for a one-off literal value
  final ColorValue snapshot; // last-known value; the fallback after deletion

  const ColorRef({required this.id, required this.snapshot});

  /// A non-referencing literal colour (no palette link).
  const ColorRef.literal(this.snapshot) : id = null;
}

const Object _sentinel = Object();
