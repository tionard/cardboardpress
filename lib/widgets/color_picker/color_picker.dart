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
import '../../state/recent_colors.dart';
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
  // Working colour(s), held as Colors. One entry = single colour; two = duo.
  // The "active" slot is the one the wheel / brightness / alpha / RGB / hex
  // controls edit. Channels are read/written 8-bit (matches storage: ARGB32).
  late List<Color> _colors;
  int _active = 0;
  MixOrientation _orientation = MixOrientation.vertical;
  double _mix = 0.3;

  // When non-null the working value still equals this palette swatch (picked and
  // untouched). Any edit — colour, alpha, blend, add/remove c2 — forks to a
  // literal and this goes null.
  String? _paletteId;

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
      _loadValue(init.snapshot);
    } else {
      _colors = [const Color(0xFF9E9E9E)]; // neutral grey default
    }
    if (!widget.allowAlpha) _colors = [for (final c in _colors) _opaque(c)];
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

  Color get _activeColor => _colors[_active]; // the colour being edited
  int get _a => (_activeColor.a * 255).round();
  int get _r => (_activeColor.r * 255).round();
  int get _g => (_activeColor.g * 255).round();
  int get _b => (_activeColor.b * 255).round();
  HSVColor get _hsv => HSVColor.fromColor(_activeColor);
  bool get _isLiteral => _paletteId == null;
  bool get _isDuo => _colors.length == 2;

  ColorValue get _workingValue => _isDuo
      ? ColorValue.duo(_colors[0], _colors[1],
          orientation: _orientation, mix: _mix)
      : ColorValue.single(_colors[0]);
  ColorValue get _previewValue => _workingValue;

  ColorRef get _result => _paletteId != null
      ? ColorRef(id: _paletteId, snapshot: _workingValue)
      : ColorRef.literal(_workingValue);

  static Color _opaque(Color c) => c.withValues(alpha: 1);

  void _loadValue(ColorValue v) {
    _colors = v.c2 == null ? [v.c1] : [v.c1, v.c2!];
    _orientation = v.orientation;
    _mix = v.mix;
    _active = 0;
  }

  // --- mutations ---

  // Replace the ACTIVE colour and fork to a literal (any edit diverges from a
  // picked palette swatch). [fromHex] leaves the hex field alone so typing isn't
  // interrupted mid-entry.
  void _setActive(Color c, {bool fromHex = false}) {
    setState(() {
      _colors[_active] = widget.allowAlpha ? c : _opaque(c);
      _paletteId = null;
    });
    if (!fromHex) _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _editChannels({int? a, int? r, int? g, int? b, bool fromHex = false}) {
    final na = widget.allowAlpha ? (a ?? _a) : 255;
    _setActive(Color.fromARGB(na, r ?? _r, g ?? _g, b ?? _b), fromHex: fromHex);
  }

  // Wheel: new hue + saturation, keeping the active colour's brightness + alpha.
  void _setHueSat(double hue, double sat) {
    final h = _hsv;
    _setActive(HSVColor.fromAHSV(_a / 255.0, hue, sat, h.value).toColor());
  }

  // Brightness slider: new value, keeping hue + saturation + alpha.
  void _setValue(double value) {
    final h = _hsv;
    _setActive(
        HSVColor.fromAHSV(_a / 255.0, h.hue, h.saturation, value).toColor());
  }

  // Picking a palette swatch loads it whole (single or duo) and keeps it as a
  // live reference until edited.
  void _pickSwatch(PaletteSwatch s) {
    setState(() {
      _paletteId = s.id;
      _loadValue(s.value);
      if (!widget.allowAlpha) _colors = [for (final c in _colors) _opaque(c)];
      _saving = false;
    });
    _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _resyncHex() {
    if (!_hexFocus.hasFocus && mounted) {
      _hex.text = _hexString(_a, _r, _g, _b);
    }
  }

  // --- second colour + blend ---

  void _addC2() {
    // Seed c2 as a visibly different shade of c1 (flip brightness) so the split
    // reads immediately, then make it active to edit.
    final h = HSVColor.fromColor(_colors[0]);
    final v2 = h.value > 0.5 ? h.value - 0.4 : h.value + 0.4;
    final c2 = HSVColor.fromAHSV(h.alpha, h.hue, h.saturation, v2.clamp(0.0, 1.0))
        .toColor();
    setState(() {
      _colors = [_colors[0], widget.allowAlpha ? c2 : _opaque(c2)];
      _active = 1;
      _paletteId = null;
    });
    _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _removeC2() {
    setState(() {
      _colors = [_colors[0]];
      _active = 0;
      _paletteId = null;
    });
    _hex.text = _hexString(_a, _r, _g, _b);
  }

  void _setOrientation(MixOrientation o) => setState(() {
        _orientation = o;
        _paletteId = null;
      });

  void _setMix(double v) => setState(() {
        _mix = v;
        _paletteId = null;
      });

  Future<void> _saveToPalette() async {
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    final value = _workingValue;
    final name = _name.text.trim().isEmpty ? 'Unnamed' : _name.text.trim();
    // Save-to-palette bakes everything: c1 + its alpha, c2 + its alpha,
    // orientation, mix (PaletteSwatch already stores a full ColorValue). Tags
    // default all-on (filter-not-forbid), so the current `use` is included.
    await ref
        .read(paletteRepositoryProvider)
        .add(PaletteSwatch(id: id, name: name, value: value));
    if (!mounted) return;
    setState(() {
      _paletteId = id; // literal -> live palette reference
      _saving = false;
    });
  }

  // Commit: record the colour in this tag's recents if it's a literal (palette
  // swatches already live in the palette), then return it. Awaited so the write
  // finishes while the notifier is still watched (no set-after-dispose).
  Future<void> _commit() async {
    final result = _result;
    if (result.id == null) {
      await ref
          .read(recentColorsProvider.notifier)
          .add(widget.use, result.snapshot);
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  // Tapping a recent loads it as a literal (recents are always literals).
  void _pickRecent(ColorValue v) {
    setState(() {
      _loadValue(v);
      if (!widget.allowAlpha) _colors = [for (final c in _colors) _opaque(c)];
      _paletteId = null;
      _saving = false;
    });
    _hex.text = _hexString(_a, _r, _g, _b);
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paletteAsync = ref.watch(paletteProvider);
    final recents = ref.watch(recentColorsProvider)[widget.use] ??
        const <ColorValue>[];

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
                const SizedBox(height: 12),
                _slotChips(theme),
                const SizedBox(height: 12),
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
                if (_isDuo) ...[
                  const SizedBox(height: 4),
                  _blendControls(theme),
                ],
                const Divider(height: 20),
                _channel('R', _r, (v) => _editChannels(r: v)),
                _channel('G', _g, (v) => _editChannels(g: v)),
                _channel('B', _b, (v) => _editChannels(b: v)),
                const SizedBox(height: 10),
                _hexField(theme),
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

  // The active-slot chips: [1] and either [2] (+ remove) or a "2nd colour"
  // button. Tapping a chip makes it the target of the wheel / sliders / hex.
  Widget _slotChips(ThemeData theme) {
    return Row(
      children: [
        _chip(0, theme),
        const SizedBox(width: 8),
        if (_isDuo) ...[
          _chip(1, theme),
          IconButton(
            tooltip: 'Remove second colour',
            visualDensity: VisualDensity.compact,
            onPressed: _removeC2,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _addC2,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('2nd colour'),
          ),
        const Spacer(),
      ],
    );
  }

  Widget _chip(int i, ThemeData theme) {
    final active = _active == i;
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => setState(() => _active = i),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: _previewDecoration(
          ColorValue.single(_colors[i]),
          radius: 8,
          border: Border.all(
            color: active ? scheme.primary : scheme.outlineVariant,
            width: active ? 3 : 1,
          ),
        ),
        child: Text(
          '${i + 1}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: _readableOn(_colors[i]),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Blend controls (duo only): orientation + how soft the seam is.
  Widget _blendControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Text('Blend', style: theme.textTheme.bodySmall),
            ),
            Expanded(
              child: SegmentedButton<MixOrientation>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: MixOrientation.vertical, label: Text('Vertical')),
                  ButtonSegment(
                      value: MixOrientation.horizontal,
                      label: Text('Horizontal')),
                ],
                selected: {_orientation},
                onSelectionChanged: (s) => _setOrientation(s.first),
              ),
            ),
          ],
        ),
        LabeledSlider(
          label: 'Mix',
          value: _mix,
          min: 0,
          max: 1,
          step: 0.05,
          decimals: 2,
          labelWidth: 52,
          onChanged: _setMix,
        ),
      ],
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
            separatorBuilder: (_, __) => const SizedBox(width: 8),
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
