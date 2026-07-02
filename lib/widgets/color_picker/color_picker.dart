// lib/widgets/color_picker/color_picker.dart
//
// The colour picker popup. Launch it with [showColorPicker]; it resolves to the
// chosen colour as a ColorRef (a palette pick keeps its id + snapshot so it
// stays a live reference; a hand-built colour comes back as a ColorRef.literal),
// or null if the user backs out.
//
// The colour-authoring controls (wheel, sliders, chips, blend, hex) live in the
// reusable [ColorComposer] widget, which this popup embeds and the Customize
// tab's colour editor also uses. The popup adds what's specific to *choosing*:
// the palette grid, the per-tag recents strip, Save-to-palette, and the
// palette-vs-literal tracking that shapes the returned ColorRef.
//
// Presentation-agnostic: a bottom sheet on phone and a dialog on desktop.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../state/providers.dart';
import '../../state/recent_colors.dart';
import '../labeled_slider.dart';
import '../swatch_picker.dart';

part 'color_wheel.dart';
part 'color_controls.dart';
part 'color_composer.dart';

/// Opens the colour picker and resolves to the chosen [ColorRef], or null if the
/// user dismissed it (null means "no change" — clearing / "use default" is a
/// per-site concern the caller handles, not this popup). [use] scopes the
/// palette grid's tag filter and pre-tags a saved swatch; [initial] seeds the
/// popup with the colour currently in use. Set [allowAlpha] false where baked
/// translucency isn't wanted (e.g. rarity colour) — the alpha slider is hidden
/// and the result is always opaque.
Future<ColorRef?> showColorPicker(
  BuildContext context, {
  required SwatchUse use,
  ColorRef? initial,
  bool allowAlpha = true,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<ColorRef>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 680),
          child: _ColorPickerView(
              use: use, initial: initial, allowAlpha: allowAlpha),
        ),
      ),
    );
  }
  return showModalBottomSheet<ColorRef>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: _ColorPickerView(
            use: use, initial: initial, allowAlpha: allowAlpha),
      ),
    ),
  );
}

class _ColorPickerView extends ConsumerStatefulWidget {
  final SwatchUse use;
  final ColorRef? initial;
  final bool allowAlpha;
  const _ColorPickerView({
    required this.use,
    this.initial,
    this.allowAlpha = true,
  });

  @override
  ConsumerState<_ColorPickerView> createState() => _ColorPickerViewState();
}

class _ColorPickerViewState extends ConsumerState<_ColorPickerView> {
  // The working colour (single or duo), owned here and edited via ColorComposer.
  late ColorValue _working;

  // When non-null the working value still equals this palette swatch (picked and
  // untouched). Any composer edit forks to a literal and this goes null.
  String? _paletteId;

  bool _saving = false;
  final _name = TextEditingController(text: 'New Color');

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _paletteId = init.id;
      _working = init.snapshot;
    } else {
      _working = const ColorValue.single(Color(0xFF9E9E9E)); // neutral grey
    }
    if (!widget.allowAlpha) _working = _opaqueValue(_working);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isLiteral => _paletteId == null;

  ColorRef get _result => _paletteId != null
      ? ColorRef(id: _paletteId, snapshot: _working)
      : ColorRef.literal(_working);

  static ColorValue _opaqueValue(ColorValue v) => v.c2 == null
      ? ColorValue.single(v.c1.withValues(alpha: 1))
      : ColorValue.duo(v.c1.withValues(alpha: 1), v.c2!.withValues(alpha: 1),
          orientation: v.orientation, mix: v.mix);

  // Composer edits fork to a literal.
  void _onComposerChanged(ColorValue v) {
    setState(() {
      _working = v;
      _paletteId = null;
    });
  }

  void _pickSwatch(PaletteSwatch s) {
    setState(() {
      _working = widget.allowAlpha ? s.value : _opaqueValue(s.value);
      _paletteId = s.id;
      _saving = false;
    });
  }

  // Tapping a recent loads it as a literal (recents are always literals).
  void _pickRecent(ColorValue v) {
    setState(() {
      _working = widget.allowAlpha ? v : _opaqueValue(v);
      _paletteId = null;
      _saving = false;
    });
  }

  Future<void> _saveToPalette() async {
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    final name = _name.text.trim().isEmpty ? 'Unnamed' : _name.text.trim();
    // Save-to-palette bakes everything (c1 + alpha, c2 + alpha, orientation,
    // mix). Tags default all-on (filter-not-forbid), so the current use is in.
    await ref
        .read(paletteRepositoryProvider)
        .add(PaletteSwatch(id: id, name: name, value: _working));
    if (!mounted) return;
    setState(() {
      _paletteId = id; // literal -> live palette reference
      _saving = false;
    });
  }

  // Commit: record a literal in this tag's recents, then return it. Awaited so
  // the write finishes while the notifier is still watched.
  Future<void> _commit() async {
    final result = _result;
    if (result.id == null) {
      await ref
          .read(recentColorsProvider.notifier)
          .add(widget.use, result.snapshot);
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paletteAsync = ref.watch(paletteProvider);
    final recents =
        ref.watch(recentColorsProvider)[widget.use] ?? const <ColorValue>[];

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Text('Pick a colour', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                ColorComposer(
                  value: _working,
                  allowAlpha: widget.allowAlpha,
                  onChanged: _onComposerChanged,
                ),
                const SizedBox(height: 12),
                _saveSection(theme),
                const Divider(height: 20),
                if (recents.isNotEmpty) _recentsStrip(theme, recents),
                Text('Palette', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                paletteAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Text('Palette unavailable.\n$e',
                      style: theme.textTheme.bodySmall),
                  data: (swatches) => SwatchPicker(
                    swatches: swatches,
                    use: widget.use,
                    selectedId: _paletteId,
                    tileBuilder: _gridCell,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _commit,
                  child: const Text('Use colour'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveSection(ThemeData theme) {
    if (!_isLiteral) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text('This colour is in your palette.',
                style: theme.textTheme.bodySmall),
          ),
        ],
      );
    }
    if (!_saving) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _saving = true),
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('Save to palette'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _saveToPalette, child: const Text('Save')),
        IconButton(
          onPressed: () => setState(() => _saving = false),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _recentsStrip(ThemeData theme, List<ColorValue> recents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _recentCell(theme, recents[i]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _recentCell(ThemeData theme, ColorValue v) {
    return InkWell(
      onTap: () => _pickRecent(v),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: _previewDecoration(
          v,
          radius: 8,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );
  }

  Widget _gridCell(PaletteSwatch s) {
    final scheme = Theme.of(context).colorScheme;
    final selected = s.id == _paletteId;
    return InkWell(
      onTap: () => _pickSwatch(s),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: _previewDecoration(
          s.value,
          radius: 8,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
