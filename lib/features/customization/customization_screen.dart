// lib/features/customization/customization_screen.dart
//
// Customization → Colors, editable. Each colour can be tuned via R/G/B sliders
// OR by typing a hex value; the two stay in sync. Edits autosave (debounced)
// through the repository, drift re-emits, and the swatch grid updates.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/palette_repository.dart';
import '../../model/card_model.dart';
import '../../state/providers.dart';
import 'text_symbol_manager.dart';

class CustomizationScreen extends ConsumerStatefulWidget {
  const CustomizationScreen({super.key});

  @override
  ConsumerState<CustomizationScreen> createState() =>
      _CustomizationScreenState();
}

class _CustomizationScreenState extends ConsumerState<CustomizationScreen> {
  int _subTab = 0; // 0=Colors, 1=Rarities, 2=Symbols, 3=Text
  String? _selectedId;

  static const _subTabNames = ['Colors', 'Rarities', 'Symbols', 'Text'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < _subTabNames.length; i++)
                ButtonSegment(value: i, label: Text(_subTabNames[i])),
            ],
            selected: {_subTab},
            onSelectionChanged: (s) => setState(() => _subTab = s.first),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: switch (_subTab) {
              0 => _buildColors(),
              3 => const TextSymbolManager(),
              _ => Center(
                  child: Text(
                      '${_subTabNames[_subTab]} — coming in a later session')),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildColors() {
    final palette = ref.watch(paletteProvider);
    return palette.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load palette:\n$e')),
      data: (swatches) {
        PaletteSwatch? selected;
        for (final s in swatches) {
          if (s.id == _selectedId) {
            selected = s;
            break;
          }
        }
        return ListView(
          children: [
            _SwatchGrid(
              swatches: swatches,
              selectedId: _selectedId,
              onSelect: (id) => setState(() => _selectedId = id),
              onAdd: _addColor,
            ),
            const SizedBox(height: 20),
            if (selected != null)
              _ColorEditor(
                key: ValueKey(selected.id),
                swatch: selected,
                repo: ref.read(paletteRepositoryProvider),
                onDelete: () {
                  ref.read(paletteRepositoryProvider).delete(selected!.id);
                  setState(() => _selectedId = null);
                },
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Select a color to edit, or ＋ to add one.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _addColor() async {
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    await ref.read(paletteRepositoryProvider).add(
          PaletteSwatch(
            id: id,
            name: 'New Color',
            value: const ColorValue.single(Color(0xFF9E9E9E)),
          ),
        );
    if (mounted) setState(() => _selectedId = id);
  }
}

// ---------------------------------------------------------------------------
// Swatch grid
// ---------------------------------------------------------------------------
class _SwatchGrid extends StatelessWidget {
  final List<PaletteSwatch> swatches;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  const _SwatchGrid({
    required this.swatches,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final s in swatches)
          GestureDetector(
            onTap: () => onSelect(s.id),
            child: Container(
              width: 52,
              height: 52,
              decoration: swatchDecoration(
                s.value,
                selected: s.id == selectedId,
                accent: scheme.primary,
              ),
            ),
          ),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outline, width: 1.5),
            ),
            child: Icon(Icons.add, color: scheme.outline),
          ),
        ),
      ],
    );
  }
}

/// Builds a BoxDecoration previewing a ColorValue. A preview only — the real
/// card uses paintCard.
BoxDecoration swatchDecoration(ColorValue v,
    {bool selected = false, Color? accent}) {
  final radius = BorderRadius.circular(10);
  final border = (selected && accent != null)
      ? Border.all(color: accent, width: 3)
      : Border.all(color: Colors.black.withValues(alpha: 0.12));
  if (!v.isDouble) {
    return BoxDecoration(color: v.c1, borderRadius: radius, border: border);
  }
  final vertical = v.orientation == MixOrientation.vertical;
  final half = v.mix / 2;
  return BoxDecoration(
    borderRadius: radius,
    border: border,
    gradient: LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: [v.c1, v.c1, v.c2!, v.c2!],
      stops: [0.0, 0.5 - half, 0.5 + half, 1.0],
    ),
  );
}

// ---------------------------------------------------------------------------
// Color editor: single/double, R/G/B sliders + editable hex, orientation, mix
// ---------------------------------------------------------------------------
class _ColorEditor extends StatefulWidget {
  final PaletteSwatch swatch;
  final PaletteRepository repo;
  final VoidCallback onDelete;

  const _ColorEditor({
    super.key,
    required this.swatch,
    required this.repo,
    required this.onDelete,
  });

  @override
  State<_ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<_ColorEditor> {
  late final TextEditingController _name;
  late final TextEditingController _hex1;
  late final TextEditingController _hex2;
  late final FocusNode _hex1Focus;
  late final FocusNode _hex2Focus;

  late bool _double;
  late int _r1, _g1, _b1, _r2, _g2, _b2;
  late MixOrientation _orientation;
  late double _mix;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    final v = widget.swatch.value;
    _name = TextEditingController(text: widget.swatch.name)
      ..addListener(_scheduleSave);
    _double = v.isDouble;
    final a = _rgb(v.c1);
    _r1 = a.$1;
    _g1 = a.$2;
    _b1 = a.$3;
    final b = _rgb(v.c2 ?? v.c1);
    _r2 = b.$1;
    _g2 = b.$2;
    _b2 = b.$3;
    _orientation = v.orientation;
    _mix = v.mix;

    _hex1 = TextEditingController(text: _hex6(_r1, _g1, _b1));
    _hex2 = TextEditingController(text: _hex6(_r2, _g2, _b2));
    _hex1Focus = FocusNode()..addListener(_resync1);
    _hex2Focus = FocusNode()..addListener(_resync2);
  }

  @override
  void dispose() {
    _name.removeListener(_scheduleSave);
    _saveTimer?.cancel();
    widget.repo.save(_current()); // flush the latest edit before leaving
    _name.dispose();
    _hex1.dispose();
    _hex2.dispose();
    _hex1Focus.dispose();
    _hex2Focus.dispose();
    super.dispose();
  }

  Color get _c1 => Color.fromARGB(255, _r1, _g1, _b1);
  Color get _c2 => Color.fromARGB(255, _r2, _g2, _b2);

  PaletteSwatch _current() {
    final value = _double
        ? ColorValue.duo(_c1, _c2, orientation: _orientation, mix: _mix)
        : ColorValue.single(_c1);
    final name = _name.text.trim().isEmpty ? 'Unnamed' : _name.text.trim();
    return PaletteSwatch(id: widget.swatch.id, name: name, value: value);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_current()));
  }

  void _change(VoidCallback apply) {
    setState(apply);
    _scheduleSave();
  }

  // When the change comes from a slider we also push the value into the hex
  // field; when it comes FROM the hex field we leave the field alone so the
  // user's cursor/typing isn't disturbed.
  void _setRgb1(int r, int g, int b, bool fromHex) {
    _change(() {
      _r1 = r;
      _g1 = g;
      _b1 = b;
    });
    if (!fromHex) _hex1.text = _hex6(r, g, b);
  }

  void _setRgb2(int r, int g, int b, bool fromHex) {
    _change(() {
      _r2 = r;
      _g2 = g;
      _b2 = b;
    });
    if (!fromHex) _hex2.text = _hex6(r, g, b);
  }

  // On blur, snap a half-typed/invalid field back to the real colour's hex.
  void _resync1() {
    if (!_hex1Focus.hasFocus && mounted) _hex1.text = _hex6(_r1, _g1, _b1);
  }

  void _resync2() {
    if (!_hex2Focus.hasFocus && mounted) _hex2.text = _hex6(_r2, _g2, _b2);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Name', isDense: true),
                ),
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete color',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Single')),
              ButtonSegment(value: true, label: Text('Double')),
            ],
            selected: {_double},
            onSelectionChanged: (s) => _change(() => _double = s.first),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 88,
              height: 56,
              decoration: swatchDecoration(_current().value),
            ),
          ),
          const SizedBox(height: 14),
          _rgbGroup(
            title: _double ? 'Color 1' : 'Color',
            r: _r1,
            g: _g1,
            b: _b1,
            hexController: _hex1,
            hexFocus: _hex1Focus,
            onRgb: _setRgb1,
          ),
          if (_double) ...[
            const SizedBox(height: 14),
            _rgbGroup(
              title: 'Color 2',
              r: _r2,
              g: _g2,
              b: _b2,
              hexController: _hex2,
              hexFocus: _hex2Focus,
              onRgb: _setRgb2,
            ),
            const SizedBox(height: 14),
            SegmentedButton<MixOrientation>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: MixOrientation.vertical, label: Text('Vertical')),
                ButtonSegment(
                    value: MixOrientation.horizontal,
                    label: Text('Horizontal')),
              ],
              selected: {_orientation},
              onSelectionChanged: (s) => _change(() => _orientation = s.first),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 36, child: Text('Mix')),
                Expanded(
                  child: Slider(
                    value: _mix,
                    divisions: 20,
                    label: _mix.toStringAsFixed(2),
                    onChanged: (d) => _change(() => _mix = d),
                  ),
                ),
                SizedBox(
                    width: 36,
                    child: Text(_mix.toStringAsFixed(2),
                        textAlign: TextAlign.right)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rgbGroup({
    required String title,
    required int r,
    required int g,
    required int b,
    required TextEditingController hexController,
    required FocusNode hexFocus,
    required void Function(int r, int g, int b, bool fromHex) onRgb,
  }) {
    final preview = Color.fromARGB(255, r, g, b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            SizedBox(
              width: 118,
              child: TextField(
                controller: hexController,
                focusNode: hexFocus,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  prefixText: '#',
                  labelText: 'Hex',
                  isDense: true,
                ),
                onChanged: (txt) {
                  final p = _parseHex(txt);
                  if (p != null) onRgb(p.$1, p.$2, p.$3, true);
                },
              ),
            ),
          ],
        ),
        _channel('R', r, (nr) => onRgb(nr, g, b, false)),
        _channel('G', g, (ng) => onRgb(r, ng, b, false)),
        _channel('B', b, (nb) => onRgb(r, g, nb, false)),
      ],
    );
  }

  Widget _channel(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 18, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
        SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.right)),
      ],
    );
  }
}

// (r, g, b) channels from a Color, without using deprecated members.
(int, int, int) _rgb(Color c) {
  final v = c.toARGB32();
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

// Six uppercase hex digits (no '#'), to match the field's '#' prefix.
String _hex6(int r, int g, int b) =>
    ((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0').toUpperCase();

// Parse a 6-digit hex string (optional leading '#') -> (r, g, b), or null if
// it isn't a valid complete hex colour. Caller ignores null = "do nothing".
(int, int, int)? _parseHex(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return ((n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF);
}
