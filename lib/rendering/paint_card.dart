// lib/rendering/paint_card.dart
//
// THE single render path. This is the ONLY place a card is ever drawn.
// The on-screen preview, the collection thumbnails, and the exported PNG all
// call this exact function — that's the architectural promise of the app
// (spec §6, §8): what you see is what you export.
//
// Rules for this file:
//   * It is PURE: it reads a CardData (+ a CardRefs resolver) and draws. It
//     never touches storage, app state, or platform APIs.
//   * Every dimension is derived from `size` (via the 0..1 fractions on the
//     model), never a hard-coded pixel. That's why the same code is correct at
//     thumbnail size and at print resolution.
//
// If you ever find card-drawing logic living somewhere OTHER than here, that's
// the bug this architecture exists to prevent.
//
// Split across parts (one library): paintCard + the per-field dispatcher live
// here; colour fills, the text/inline-symbol engine, and the image/foil helpers
// live in paint_colors.dart / paint_text.dart / paint_images.dart. They're all
// plain top-level functions in the same library, so paintCard reaches them
// directly — no behaviour change, just navigation.

import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/card_model.dart';
import '../model/layers.dart';
import '../model/layer_migration.dart';
import '../model/markup.dart';

part 'paint_colors.dart';
part 'paint_text.dart';
part 'paint_images.dart';
part 'paint_card_layers.dart';
part 'frame_preview.dart';

/// Draws one card into [canvas], filling a card of [size]. THE single public
/// render entry — the preview, collection thumbnails, and PNG export all call
/// this. It now renders through the layer path: it derives the card's ordered
/// layers and draws them. The result is pixel-identical to the legacy direct
/// renderer below (guarded by the layer render parity test); the layer path is
/// what the rest of the redesign builds on.
void paintCard(ui.Canvas canvas, ui.Size size, CardData card, CardRefs refs) {
  paintCardFromLayers(canvas, size, card, effectiveCardLayers(card), refs);
}


// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------


