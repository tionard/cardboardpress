// lib/widgets/decoded_card_preview.dart
//
// A CardPreview that decodes the images a card references — its art AND the
// template's background — before drawing. paintCard is synchronous and never
// loads files itself, so SOMETHING must pre-decode and hand the images in via
// CardRefs.images. The editors do that inside their own State; this widget does
// it for read-only display sites (Collection thumbnails today, export-from-tile
// later) so they don't each reinvent the decode/cache dance.
//
// Two efficiency choices for thumbnails:
//   * Images are decoded at THUMBNAIL resolution (targetWidth), not full source
//     size — a 92px tile never needs a 4000px decode. (Export still decodes at
//     full res in the Card Editor; that path is untouched.)
//   * A process-wide cache keyed by (imageId, target) means the same image is
//     decoded once, not once per tile or per scroll rebuild.
// The cache is not evicted — fine for Collection v1; v2 (virtualised grid,
// density) can add eviction if a very large collection makes it matter.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../data/image_store.dart';
import '../model/card_model.dart';
import 'card_preview.dart';

class DecodedCardPreview extends StatefulWidget {
  final CardData card;
  final Map<String, ColorValue> palette;
  final ImageStore imageStore;
  final double width;

  const DecodedCardPreview({
    super.key,
    required this.card,
    required this.palette,
    required this.imageStore,
    this.width = 92,
  });

  @override
  State<DecodedCardPreview> createState() => _DecodedCardPreviewState();
}

class _DecodedCardPreviewState extends State<DecodedCardPreview> {
  // Shared across every instance: the same image is decoded once, not per tile.
  static final Map<String, ui.Image> _cache = {};

  // The images this tile has resolved so far (subset of _cache, keyed by id).
  final Map<String, ui.Image> _images = {};

  int get _target => (widget.width * 3).round().clamp(1, 4096);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DecodedCardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(); // cheap: ids already resolved are skipped
  }

  // Every image the renderer may need for this card.
  Iterable<String> get _neededIds sync* {
    yield* widget.card.artImageIds.values;
    final bg = widget.card.bgImageId;
    if (bg != null) yield bg;
  }

  Future<void> _sync() async {
    for (final id in _neededIds) {
      if (_images.containsKey(id)) continue;

      final cacheKey = '$id@$_target';
      final cached = _cache[cacheKey];
      if (cached != null) {
        if (!mounted) return;
        setState(() => _images[id] = cached);
        continue;
      }

      final bytes = await widget.imageStore.load(id);
      if (bytes == null) continue;
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: _target);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      _cache[cacheKey] = img;
      if (!mounted) return;
      setState(() => _images[id] = img);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardPreview(
      card: widget.card,
      refs: CardRefs(palette: widget.palette, images: _images),
      width: widget.width,
    );
  }
}
