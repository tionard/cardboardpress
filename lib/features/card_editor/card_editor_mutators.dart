// lib/features/card_editor/card_editor_mutators.dart
//
// Every per-card WRITE operation: text, template switch, set/rarity/artist,
// art removal and transforms, and the full set of exposed layer-aspect
// overrides (fill / outline / foil / image / watermark / visibility). All of
// them funnel through `_markDirty` on the State (the one setState choke point
// — extensions can't call setState), so this file is pure "compute the next
// working copy" logic. Reading, composing, and layout stay in
// card_editor_screen.dart; the controls that CALL these live in
// card_editor_panels.dart.

part of 'card_editor_screen.dart';

extension _CardEditorMutators on _CardEditorBodyState {
  void _onTextChanged(String layerId, String value) {
    if (_suppressDirty) return;
    if ((_working.content.text[layerId] ?? '') == value) return;
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withText(layerId, value)));
  }


  void _changeTemplate(String? id) {
    if (id == null) return;
    final snapshot = widget.templatesMap[id] ?? _working.templateSnapshot;
    _markDirty(() => _working =
        _working.copyWith(templateId: id, templateSnapshot: snapshot));
    _syncArtImages();
  }


  void _removeArt(String artFieldId) {
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withArt(artFieldId, null)));
    // (The file is left on disk; orphan cleanup comes with Collection delete.)
  }


  void _setArtTransform(String fieldId, ArtTransform t) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withArtTransform(fieldId, t)));
  }


  // Tint and foil are ordinary exposed layer aspects now; there are no
  // dedicated mutators. Legacy per-card values (content.tint / entry.foil)
  // still render via the resolver shims — the setters below clear them when
  // the user reverts the matching layer override to “default”, so
  // “Use default” genuinely means the template value again.

  void _onArtistChanged() {
    if (_suppressDirty) return;
    if (_working.content.artist == _artist.text) return;
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withArtist(_artist.text)));
  }

  void _changeSet(String? setId) {
    _markDirty(() => _working = _working.copyWith(setId: setId));
  }

  void _setRarity(String? rarityId) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withRarity(rarityId)));
  }


  // ---- Phase 5: per-card layer-aspect mutators ----

  void _setLayerFill(String layerId, ColorRef? ref) {
    _markDirty(() {
      var content = _working.content.withFillColor(layerId, ref);
      // Reverting the TINT layer's fill to default also clears the legacy
      // per-card tint, or the shim would immediately re-apply it.
      if (ref == null && layerId == kTintLayerId && content.tint != null) {
        content = content.withTint(null);
      }
      _working = _working.copyWith(content: content);
    });
  }

  void _setLayerFillAlpha(String layerId, double? a) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withFillAlpha(layerId, a)));
  }

  void _setLayerImageAlpha(String layerId, double? a) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withImageAlpha(layerId, a)));
  }

  void _setLayerImageTint(String layerId, ColorRef? ref) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withImageTint(layerId, ref)));
  }

  void _setLayerWatermarkColor(String layerId, ColorRef? ref) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withWatermarkColor(layerId, ref)));
  }

  void _setLayerWatermarkAlpha(String layerId, double? a) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withWatermarkAlpha(layerId, a)));
  }

  /// Pick a per-card watermark symbol for an exposed watermark aspect, then
  /// re-run the image sync so the new glyph decodes into the preview.
  Future<void> _pickLayerWatermarkSymbol(Layer layer) async {
    final current = _working.content.watermarkSymbols[layer.id] ??
        layer.watermark?.symbolId;
    final choice = await pickSymbol(context, ref, currentId: current);
    if (choice == null) return; // cancelled
    // A picked symbol overrides the template's; \u201cNone\u201d stores an explicit
    // empty override (no watermark on this card). \u201cUse default\u201d elsewhere
    // removes the override entirely.
    _markDirty(() => _working = _working.copyWith(
        content:
            _working.content.withWatermarkSymbol(layer.id, choice.id ?? '')));
    _syncArtImages();
  }

  void _clearLayerWatermarkSymbol(String layerId) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withWatermarkSymbol(layerId, null)));
  }

  void _setLayerOutline(String layerId, ColorRef? ref) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withOutlineColor(layerId, ref)));
  }

  void _setLayerHidden(String layerId, bool hidden) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withLayerHidden(layerId, hidden)));
  }

  void _setLayerFoil(String layerId, FoilType? foil) {
    _markDirty(() {
      _working = _working.copyWith(
          content: _working.content.withLayerFoil(layerId, foil));
      // Reverting the FOIL layer to default also clears the legacy per-card
      // foil, or the shim would immediately re-apply it.
      if (foil == null &&
          layerId == kFoilLayerId &&
          _working.foil != FoilType.none) {
        _working = _working.copyWith(foil: FoilType.none);
      }
    });
  }

  /// Pick an image for a per-card image-aspect override, routed via [_pickArt]
  /// (same store/decoding path — the `art` map is keyed by layer id, matching
  /// the existing `art` bespoke kind).
  Future<void> _pickLayerImageOverride(String layerId) => _pickArt(layerId);
  void _removeLayerImageOverride(String layerId) => _removeArt(layerId);
}
