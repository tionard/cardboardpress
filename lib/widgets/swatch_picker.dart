// lib/widgets/swatch_picker.dart
//
// A palette swatch grid that filters by a swatch's usage tags for the current
// context, with a "show all" escape hatch. Tags FILTER, never forbid — every
// picker can reveal the whole palette, so a colour is never hard-blocked.
//
// Each call site keeps its own tile look by passing a [tileBuilder] (and an
// optional [leading] tile, e.g. a None/Default cell); this widget owns only the
// filtering, the "show all" toggle, and its state.

import 'package:flutter/material.dart';

import '../model/card_model.dart';

/// The context a picker is opened in. Determines which tag filters the list.
enum SwatchUse { card, text, symbol }

class SwatchPicker extends StatefulWidget {
  final List<PaletteSwatch> swatches;
  final SwatchUse use;

  /// The currently selected swatch id (if any). Kept visible even when it isn't
  /// tagged for this context, so the selection never silently disappears.
  final String? selectedId;

  /// Builds the tile for a swatch — the site's own swatch widget.
  final Widget Function(PaletteSwatch swatch) tileBuilder;

  /// Optional first cell (a None / Default tile). Always shown.
  final Widget? leading;

  final double spacing;

  const SwatchPicker({
    super.key,
    required this.swatches,
    required this.use,
    required this.selectedId,
    required this.tileBuilder,
    this.leading,
    this.spacing = 10,
  });

  @override
  State<SwatchPicker> createState() => _SwatchPickerState();
}

class _SwatchPickerState extends State<SwatchPicker> {
  bool _showAll = false;

  bool _tagged(PaletteSwatch s) => switch (widget.use) {
        SwatchUse.card => s.tagCard,
        SwatchUse.text => s.tagText,
        SwatchUse.symbol => s.tagSymbol,
      };

  @override
  Widget build(BuildContext context) {
    final tagged = widget.swatches.where(_tagged).toList();
    final hidden = widget.swatches.length - tagged.length;

    List<PaletteSwatch> visible;
    if (_showAll || hidden == 0) {
      visible = widget.swatches;
    } else {
      visible = List.of(tagged);
      // Keep the current selection on screen even if it isn't tagged here.
      final sel = widget.selectedId;
      if (sel != null && !visible.any((s) => s.id == sel)) {
        final match = widget.swatches.where((s) => s.id == sel);
        if (match.isNotEmpty) visible = [match.first, ...visible];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: widget.spacing,
          runSpacing: widget.spacing,
          children: [
            if (widget.leading != null) widget.leading!,
            for (final s in visible) widget.tileBuilder(s),
          ],
        ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              icon: Icon(
                  _showAll
                      ? Icons.filter_alt_off_outlined
                      : Icons.filter_alt_outlined,
                  size: 16),
              label: Text(_showAll ? 'Show tagged only' : 'Show all (+$hidden)'),
            ),
          ),
      ],
    );
  }
}
