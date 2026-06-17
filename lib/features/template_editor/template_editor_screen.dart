// lib/features/template_editor/template_editor_screen.dart
//
// Template Editor v1: create / duplicate / rename / delete templates, and edit
// template-level layout — base colour, border, corner radius, card size — with
// a live preview. Edits autosave and update every card on that template live.
//
// Field editing (placing/resizing/restyling the nine fields) is the focused
// follow-up; this turn makes templates genuinely user-authored at the top level.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/template_repository.dart';
import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';

const Map<String, (double, double)> _sizePresets = {
  'Poker (2.5 × 3.5)': (2.5, 3.5),
  'Bridge (2.25 × 3.5)': (2.25, 3.5),
  'Tarot (2.75 × 4.75)': (2.75, 4.75),
  'Square (3.5 × 3.5)': (3.5, 3.5),
};

class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key});

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);
    final palette = ref.watch(paletteMapProvider);
    final swatches = ref.watch(paletteProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <PaletteSwatch>[],
        );
    final repo = ref.read(templateRepositoryProvider);

    return templatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load templates:\n$e')),
      data: (templates) {
        final selected = templates.isEmpty
            ? null
            : templates.firstWhere((t) => t.id == _selectedId,
                orElse: () => templates.first);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected?.id,
                      hint: const Text('No templates'),
                      items: [
                        for (final t in templates)
                          DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (v) => setState(() => _selectedId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New template',
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final id = await repo.create('New template', starterTemplate());
                      setState(() => _selectedId = id);
                    },
                  ),
                  IconButton(
                    tooltip: 'Duplicate',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: selected == null
                        ? null
                        : () async {
                            final id = await repo.create(
                                '${selected.name} copy', selected.data);
                            setState(() => _selectedId = id);
                          },
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: selected == null
                        ? null
                        : () => _confirmDelete(repo, selected),
                  ),
                ],
              ),
            ),
            Expanded(
              child: selected == null
                  ? const Center(
                      child: Text('Create a template to get started.'))
                  : _TemplateBody(
                      key: ValueKey(selected.id),
                      entry: selected,
                      palette: palette,
                      swatches: swatches,
                      repo: repo,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
      TemplateRepository repo, TemplateEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete "${entry.name}"?'),
        content: const Text(
            'Cards using this template keep rendering from their saved '
            'snapshot; they just lose the live link.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await repo.delete(entry.id);
      setState(() => _selectedId = null);
    }
  }
}

class _TemplateBody extends StatefulWidget {
  final TemplateEntry entry;
  final Map<String, ColorValue> palette;
  final List<PaletteSwatch> swatches;
  final TemplateRepository repo;

  const _TemplateBody({
    super.key,
    required this.entry,
    required this.palette,
    required this.swatches,
    required this.repo,
  });

  @override
  State<_TemplateBody> createState() => _TemplateBodyState();
}

class _TemplateBodyState extends State<_TemplateBody> {
  late TemplateEntry _working;
  late final TextEditingController _name;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _working = widget.entry;
    _name = TextEditingController(text: _working.name)
      ..addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.repo.save(_working);
    _name.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_working));
  }

  void _onNameChanged() {
    if (_working.name == _name.text) return;
    setState(() => _working = _working.copyWith(name: _name.text));
    _scheduleSave();
  }

  void _update(TemplateData data) {
    setState(() => _working = _working.copyWith(data: data));
    _scheduleSave();
  }

  TemplateData get _d => _working.data;

  @override
  Widget build(BuildContext context) {
    final card = composeCard(_d, content: sampleContent());
    final refs = CardRefs(palette: widget.palette);

    final preview = Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: CardPreview(card: card, refs: refs, width: 280)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final form = _form(context);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: preview),
              Expanded(flex: 5, child: form),
            ],
          );
        }
        return ListView(
          children: [preview, form],
        );
      },
    );
  }

  Widget _form(BuildContext context) {
    final border = _d.border;
    final children = <Widget>[
      TextField(
        controller: _name,
        decoration: const InputDecoration(
            labelText: 'Template name', isDense: true, border: OutlineInputBorder()),
      ),
      const SizedBox(height: 20),
      Text('Base colour', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in widget.swatches)
            _swatch(s.value, s.id == _d.baseColor.id,
                () => _update(_d.copyWith(baseColor: ColorRef(id: s.id, snapshot: s.value)))),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Text('Border', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Switch(
            value: border != null,
            onChanged: (on) => _update(_d.copyWith(
                border: on
                    ? const BorderSpec(black: true, thickness: 0.022)
                    : null)),
          ),
        ],
      ),
      if (border != null) ...[
        Row(children: [
          const SizedBox(width: 78, child: Text('Thickness')),
          Expanded(
            child: Slider(
              value: border.thickness.clamp(0.005, 0.05),
              min: 0.005,
              max: 0.05,
              onChanged: (v) => _update(_d.copyWith(
                  border: BorderSpec(black: border.black, thickness: v))),
            ),
          ),
        ]),
        Row(children: [
          const SizedBox(width: 78, child: Text('Colour')),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Black')),
              ButtonSegment(value: false, label: Text('White')),
            ],
            selected: {border.black},
            onSelectionChanged: (s) => _update(_d.copyWith(
                border: BorderSpec(black: s.first, thickness: border.thickness))),
          ),
        ]),
      ],
      const SizedBox(height: 16),
      Text('Corner radius', style: Theme.of(context).textTheme.titleSmall),
      Slider(
        value: _d.cornerRadiusFrac.clamp(0.0, 0.12),
        min: 0.0,
        max: 0.12,
        onChanged: (v) => _update(_d.copyWith(cornerRadiusFrac: v)),
      ),
      const SizedBox(height: 8),
      Text('Card size', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _sizeDropdown(),
      const SizedBox(height: 16),
      Text(
        'Editing a template updates every card that uses it, live. Placing and '
        'restyling the individual fields is the next step.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  Widget _sizeDropdown() {
    String currentKey = 'Custom';
    for (final e in _sizePresets.entries) {
      if ((e.value.$1 - _d.widthInches).abs() < 0.001 &&
          (e.value.$2 - _d.heightInches).abs() < 0.001) {
        currentKey = e.key;
        break;
      }
    }
    return DropdownButton<String>(
      isExpanded: true,
      value: currentKey,
      items: [
        if (currentKey == 'Custom')
          DropdownMenuItem(
              value: 'Custom',
              child: Text('Custom '
                  '(${_d.widthInches} × ${_d.heightInches})')),
        for (final k in _sizePresets.keys)
          DropdownMenuItem(value: k, child: Text(k)),
      ],
      onChanged: (k) {
        if (k == null || k == 'Custom') return;
        final (w, h) = _sizePresets[k]!;
        _update(_d.copyWith(widthInches: w, heightInches: h));
      },
    );
  }

  Widget _swatch(ColorValue v, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    final deco = v.c2 == null
        ? BoxDecoration(color: v.c1, borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [v.c1, v.c2!],
              begin: v.orientation == MixOrientation.vertical
                  ? Alignment.topCenter
                  : Alignment.centerLeft,
              end: v.orientation == MixOrientation.vertical
                  ? Alignment.bottomCenter
                  : Alignment.centerRight,
            ),
          );
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        width: 40,
        height: 40,
        decoration: deco.copyWith(
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1),
        ),
      ),
    );
  }
}
