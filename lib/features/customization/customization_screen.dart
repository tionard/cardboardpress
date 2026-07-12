// lib/features/customization/customization_screen.dart
//
// Customization → Colors, editable. Each colour is tuned with the shared
// ColorComposer (hue wheel, brightness/alpha, R/G/B, hex, and duo + blend) —
// the same controls as the pop-up picker. The Customize editor adds what's
// specific to a palette swatch: a name and the tag toggles that decide which
// pickers (card / text / symbol) it shows up in. Edits autosave (debounced)
// through the repository; drift re-emits and the swatch grid updates.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/palette_repository.dart';
import '../../model/card_model.dart';
import '../../state/providers.dart';
import '../../widgets/color_picker/color_picker.dart';
import 'frame_manager.dart';
import 'rarity_manager.dart';
import 'symbol_manager.dart';
import 'text_symbol_manager.dart';

class CustomizationScreen extends ConsumerStatefulWidget {
  const CustomizationScreen({super.key});

  @override
  ConsumerState<CustomizationScreen> createState() =>
      _CustomizationScreenState();
}

class _CustomizationScreenState extends ConsumerState<CustomizationScreen> {
  int _subTab = 0; // 0=Colors, 1=Rarities, 2=Symbols, 3=Text, 4=Frames
  String? _selectedId;

  static const _subTabNames = ['Colors', 'Rarities', 'Symbols', 'Text', 'Frames'];

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
              1 => const RarityManager(),
              2 => const SymbolManager(),
              3 => const TextSymbolManager(),
              4 => const FrameManager(),
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
// Color editor: name + tag toggles wrapped around the shared ColorComposer.
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
  late ColorValue _value;
  late bool _tagCard, _tagText, _tagSymbol;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.swatch.name)
      ..addListener(_scheduleSave);
    _value = widget.swatch.value;
    _tagCard = widget.swatch.tagCard;
    _tagText = widget.swatch.tagText;
    _tagSymbol = widget.swatch.tagSymbol;
  }

  @override
  void dispose() {
    _name.removeListener(_scheduleSave);
    _saveTimer?.cancel();
    widget.repo.save(_current()); // flush the latest edit before leaving
    _name.dispose();
    super.dispose();
  }

  PaletteSwatch _current() => PaletteSwatch(
        id: widget.swatch.id,
        name: _name.text.trim().isEmpty ? 'Unnamed' : _name.text.trim(),
        value: _value,
        tagCard: _tagCard,
        tagText: _tagText,
        tagSymbol: _tagSymbol,
      );

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_current()));
  }

  void _change(VoidCallback apply) {
    setState(apply);
    _scheduleSave();
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
          ColorComposer(
            value: _value,
            onChanged: (v) => _change(() => _value = v),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text('Show in pickers for',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          _tagToggle('Card backgrounds & fills', _tagCard,
              (v) => _change(() => _tagCard = v)),
          _tagToggle('Text', _tagText, (v) => _change(() => _tagText = v)),
          _tagToggle('Symbols & watermarks', _tagSymbol,
              (v) => _change(() => _tagSymbol = v)),
        ],
      ),
    );
  }

  Widget _tagToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
