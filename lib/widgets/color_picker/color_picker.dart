// lib/widgets/color_picker/color_picker.dart
//
// A self-contained colour picker popup. Launch it with [showColorPicker]; it
// resolves to the chosen colour as a ColorRef (a palette pick keeps its
// id + snapshot so it stays a live reference; a hand-built colour comes back as
// a ColorRef.literal), or null if the user backs out.
//
// PHASE 1 — single colour: the palette grid (embeds the existing SwatchPicker) +
// a hue/saturation wheel, brightness + alpha sliders, an R/G/B row, an 8-digit
// (RRGGBBAA) hex field, and Save-to-palette. Per-colour alpha is automatic here:
// the alpha slider just edits the working colour. Duo chips + blend controls
// land in Phase 3; per-tag recents in Phase 4 — the palette-vs-literal state is
// already tracked so they slot in additively.
//
// Presentation-agnostic: a bottom sheet on phone and a dialog on desktop
// (branch in the launcher), matching the app's responsive editors. The
// customization screen keeps its own colour editor for now; consolidating the
// two onto these controls is a later, deliberate pass.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../state/providers.dart';
import '../labeled_slider.dart';
import '../swatch_picker.dart';

part 'color_wheel.dart';
part 'color_controls.dart';

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
  // Working colour held as 8-bit channels (matches storage: ARGB32).
  late int _a, _r, _g, _b;

  // When non-null the current selection IS this palette swatch, passed through
  // unmodified (so a duo swatch survives being picked). Any manual edit flips to
  // a single-colour literal and these go null.
  String? _paletteId;
  ColorValue? _paletteValue;

  final _hex = TextEditingController();
  final _hexFocus = FocusNode();
  bool _saving = false;
  final _name = TextEditingController(text: 'New Color');

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _paletteId = init.id;
      _paletteValue = init.id != null ? init.snapshot : null;
      _setChannelsFrom(init.snapshot.c1);
    } else {
      _a = 255;
      _r = 0x9E;
      _g = 0x9E;
      _b = 0x9E; // neutral grey, like the customization editor's new colour
    }
    if (!widget.allowAlpha) _a = 255;
    _hex.text = _hexString(_a, _r, _g, _b);
    _hexFocus.addListener(_resyncHex);
  }

  @override
  void dispose() {
    _hexFocus.removeListener(_resyncHex);
    _hex.dispose();
    _hexFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  // --- working-colour derivations ---

  Color get _c1 => Color.fromARGB(_a, _r, _g, _b);
  HSVColor get _hsv => HSVColor.fromColor(_c1);
  bool get _isLiteral => _paletteId == null;
  ColorValue get _previewValue => _paletteValue ?? ColorValue.single(_c1);

  ColorRef get _result => _paletteId != null
      ? ColorRef(id: _paletteId, snapshot: _paletteValue ?? ColorValue.single(_c1))
      : ColorRef.literal(ColorValue.single(_c1));

  void _setChannelsFrom(Color c) {
    _a = (c.a * 255).round();
    _r = (c.r * 255).round();
    _g = (c.g * 255).round();
    _b = (c.b * 255).round();
  }

  // --- mutations ---

  // A manual edit -> becomes a single-colour literal (drops any duo passthrough).
  void _editChannels({int? a, int? r, int? g, int? b, bool fromHex = false}) {
    setState(() {
      _a = widget.allowAlpha ? (a ?? _a) : 255;
      _r = r ?? _r;
      _g = g ?? _g;
      _b = b ?? _b;
      _paletteId = null;
      _paletteValue = null;
    });
    // Keep the hex field in step, unless the edit CAME from it (don't fight the
    // user's cursor mid-type).
    if (!fromHex) _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _setColor(Color c) => _editChannels(
        a: (c.a * 255).round(),
        r: (c.r * 255).round(),
        g: (c.g * 255).round(),
        b: (c.b * 255).round(),
      );

  // Wheel: new hue + saturation, keeping the current brightness and alpha.
  void _setHueSat(double hue, double sat) {
    final v = _hsv.value;
    _setColor(HSVColor.fromAHSV(_a / 255.0, hue, sat, v).toColor());
  }

  // Brightness slider: new value, keeping hue + saturation + alpha.
  void _setValue(double value) {
    final h = _hsv;
    _setColor(HSVColor.fromAHSV(_a / 255.0, h.hue, h.saturation, value).toColor());
  }

  // Picking a palette swatch keeps it whole (id + snapshot) — no flattening.
  void _pickSwatch(PaletteSwatch s) {
    setState(() {
      _paletteId = s.id;
      _paletteValue = s.value;
      _setChannelsFrom(s.value.c1);
      _saving = false;
    });
    _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _resyncHex() {
    if (!_hexFocus.hasFocus && mounted) {
      _hex.text = _hexString(_a, _r, _g, _b);
    }
  }

  Future<void> _saveToPalette() async {
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    final value = ColorValue.single(_c1);
    final name = _name.text.trim().isEmpty ? 'Unnamed' : _name.text.trim();
    // Tags default all-on (PaletteSwatch defaults) — filter-not-forbid, matching
    // the customization editor. The current `use` is therefore always included.
    await ref
        .read(paletteRepositoryProvider)
        .add(PaletteSwatch(id: id, name: name, value: value));
    if (!mounted) return;
    setState(() {
      _paletteId = id; // literal -> live palette reference
      _paletteValue = value;
      _saving = false;
    });
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paletteAsync = ref.watch(paletteProvider);

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
                _preview(),
                const SizedBox(height: 14),
                Center(
                  child: _HueWheel(
                    hue: _hsv.hue,
                    saturation: _hsv.saturation,
                    onChanged: _setHueSat,
                  ),
                ),
                const SizedBox(height: 8),
                LabeledSlider(
                  label: 'Bright',
                  value: _hsv.value,
                  min: 0,
                  max: 1,
                  step: 0.01,
                  decimals: 2,
                  labelWidth: 52,
                  onChanged: _setValue,
                ),
                if (widget.allowAlpha)
                  LabeledSlider(
                    label: 'Alpha',
                    value: _a.toDouble(),
                    min: 0,
                    max: 255,
                    step: 1,
                    decimals: 0,
                    labelWidth: 52,
                    onChanged: (v) => _editChannels(a: v.round()),
                  ),
                const Divider(height: 20),
                _channel('R', _r, (v) => _editChannels(r: v)),
                _channel('G', _g, (v) => _editChannels(g: v)),
                _channel('B', _b, (v) => _editChannels(b: v)),
                const SizedBox(height: 10),
                _hexField(theme),
                const SizedBox(height: 12),
                _saveSection(theme),
                const Divider(height: 20),
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
                  onPressed: () => Navigator.of(context).pop(_result),
                  child: const Text('Use colour'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _CheckerPainter()),
            DecoratedBox(decoration: _previewDecoration(_previewValue)),
          ],
        ),
      ),
    );
  }

  Widget _channel(String label, int value, ValueChanged<int> onChanged) {
    return LabeledSlider(
      label: label,
      value: value.toDouble(),
      min: 0,
      max: 255,
      step: 1,
      decimals: 0,
      labelWidth: 20,
      onChanged: (d) => onChanged(d.round()),
    );
  }

  Widget _hexField(ThemeData theme) {
    return Row(
      children: [
        Text('Hex', style: theme.textTheme.bodySmall),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _hex,
            focusNode: _hexFocus,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: const InputDecoration(
              prefixText: '#',
              isDense: true,
              helperText: 'RRGGBB or RRGGBBAA',
            ),
            onChanged: (txt) {
              final p = _parseHex(txt);
              if (p != null) {
                _editChannels(a: p.a, r: p.r, g: p.g, b: p.b, fromHex: true);
              }
            },
          ),
        ),
      ],
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
