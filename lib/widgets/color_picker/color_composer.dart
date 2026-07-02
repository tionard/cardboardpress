part of 'color_picker.dart';

/// The colour-authoring controls, shared by the picker popup and the Customize
/// tab's colour editor: a preview, the [1]/[2] slot chips, a hue/saturation
/// wheel, brightness + alpha sliders, blend controls (duo only), an R/G/B row,
/// and an 8-digit hex field.
///
/// This is a *controlled* widget — the parent owns the [value] and receives
/// every edit via [onChanged]; only the active slot and the hex field's text are
/// internal UI state. That lets the popup track palette-vs-literal itself, and
/// lets the Customize editor autosave, without either duplicating the controls.
/// Set [allowAlpha] false to forbid baked translucency (e.g. rarity): the alpha
/// slider is hidden and every emitted colour is forced opaque.
class ColorComposer extends StatefulWidget {
  final ColorValue value;
  final bool allowAlpha;
  final ValueChanged<ColorValue> onChanged;

  const ColorComposer({
    super.key,
    required this.value,
    this.allowAlpha = true,
    required this.onChanged,
  });

  @override
  State<ColorComposer> createState() => _ColorComposerState();
}

class _ColorComposerState extends State<ColorComposer> {
  int _active = 0; // which slot the controls edit (UI state only)
  final _hex = TextEditingController();
  final _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hex.text = _hexString(_a, _r, _g, _b);
    _hexFocus.addListener(_syncHex);
  }

  @override
  void didUpdateWidget(ColorComposer old) {
    super.didUpdateWidget(old);
    // The parent pushed a new value (or we forced opaque): mirror it into the
    // hex field, unless the user is mid-type there.
    _syncHex();
  }

  @override
  void dispose() {
    _hexFocus.removeListener(_syncHex);
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  // --- derivations from the controlled value ---

  List<Color> get _colors => widget.value.c2 == null
      ? [widget.value.c1]
      : [widget.value.c1, widget.value.c2!];
  int get _activeIdx => _active.clamp(0, _colors.length - 1);
  Color get _activeColor => _colors[_activeIdx];
  int get _a => (_activeColor.a * 255).round();
  int get _r => (_activeColor.r * 255).round();
  int get _g => (_activeColor.g * 255).round();
  int get _b => (_activeColor.b * 255).round();
  HSVColor get _hsv => HSVColor.fromColor(_activeColor);
  bool get _isDuo => _colors.length == 2;

  // --- emitting edits ---

  ColorValue _compose(List<Color> colors) => colors.length == 2
      ? ColorValue.duo(colors[0], colors[1],
          orientation: widget.value.orientation, mix: widget.value.mix)
      : ColorValue.single(colors[0]);

  void _emit(List<Color> colors) {
    final norm = widget.allowAlpha
        ? colors
        : [for (final c in colors) c.withValues(alpha: 1)];
    widget.onChanged(_compose(norm));
    // The hex field resyncs in didUpdateWidget once the new value comes back.
  }

  void _setActiveColor(Color c) {
    final colors = [..._colors];
    colors[_activeIdx] = c;
    _emit(colors);
  }

  void _editChannels({int? a, int? r, int? g, int? b}) {
    final na = widget.allowAlpha ? (a ?? _a) : 255;
    _setActiveColor(Color.fromARGB(na, r ?? _r, g ?? _g, b ?? _b));
  }

  // Wheel: new hue + saturation, keeping the active colour's brightness + alpha.
  void _setHueSat(double hue, double sat) {
    final h = _hsv;
    _setActiveColor(HSVColor.fromAHSV(_a / 255.0, hue, sat, h.value).toColor());
  }

  // Brightness slider: new value, keeping hue + saturation + alpha.
  void _setValue(double value) {
    final h = _hsv;
    _setActiveColor(
        HSVColor.fromAHSV(_a / 255.0, h.hue, h.saturation, value).toColor());
  }

  void _selectSlot(int i) {
    setState(() => _active = i);
    _syncHex();
  }

  void _syncHex() {
    if (!_hexFocus.hasFocus && mounted) {
      final want = _hexString(_a, _r, _g, _b);
      if (_hex.text.toUpperCase() != want) _hex.text = want;
    }
  }

  // --- second colour + blend ---

  void _addC2() {
    // Seed c2 as a visibly different shade of c1 (flip brightness) so the split
    // reads immediately, then make it active to edit.
    final h = HSVColor.fromColor(_colors[0]);
    final v2 = h.value > 0.5 ? h.value - 0.4 : h.value + 0.4;
    final c2 =
        HSVColor.fromAHSV(h.alpha, h.hue, h.saturation, v2.clamp(0.0, 1.0))
            .toColor();
    setState(() => _active = 1);
    _emit([_colors[0], c2]);
  }

  void _removeC2() {
    setState(() => _active = 0);
    _emit([_colors[0]]);
  }

  void _setOrientation(MixOrientation o) {
    if (!_isDuo) return;
    widget.onChanged(ColorValue.duo(_colors[0], _colors[1],
        orientation: o, mix: widget.value.mix));
  }

  void _setMix(double m) {
    if (!_isDuo) return;
    widget.onChanged(ColorValue.duo(_colors[0], _colors[1],
        orientation: widget.value.orientation, mix: m));
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ],
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
            DecoratedBox(decoration: _previewDecoration(widget.value)),
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
    final active = _activeIdx == i;
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => _selectSlot(i),
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
                selected: {widget.value.orientation},
                onSelectionChanged: (s) => _setOrientation(s.first),
              ),
            ),
          ],
        ),
        LabeledSlider(
          label: 'Mix',
          value: widget.value.mix,
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
                _editChannels(a: p.a, r: p.r, g: p.g, b: p.b);
              }
            },
          ),
        ),
      ],
    );
  }
}
