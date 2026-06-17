// lib/features/template_editor/template_editor_screen.dart
//
// Template Editor: manage templates (create/duplicate/rename/delete) and edit
// their layout. Two panes via a Layout/Fields switch:
//   * Layout  — base colour, border, corner radius, card size.
//   * Fields  — add/remove fields and edit the selected field's type, position,
//               fill, outline, corners, and text style. The selected field is
//               outlined on the live preview.
// Edits autosave and update every card on the template live. No schema change —
// fields already persist inside the template's JSON.

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

// Defaults for newly-added fields (seeded palette ids).
const _paperRef =
    ColorRef(id: 'c_paper', snapshot: ColorValue.single(Color(0xFFF1EFE8)));
const _inkRef =
    ColorRef(id: 'c_ink', snapshot: ColorValue.single(Color(0xFF2C2B27)));

const double _previewW = 280;

enum _Mode { layout, fields }

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
                      final id =
                          await repo.create('New template', starterTemplate());
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
  _Mode _mode = _Mode.layout;
  String? _selectedFieldId;

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

  TemplateData get _d => _working.data;

  FieldSpec? get _selectedField {
    for (final f in _d.fields) {
      if (f.id == _selectedFieldId) return f;
    }
    return null;
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

  void _updateField(FieldSpec updated) {
    final fields =
        _d.fields.map((f) => f.id == updated.id ? updated : f).toList();
    _update(_d.copyWith(fields: fields));
  }

  void _addField(FieldType type) {
    final id = 'f_${DateTime.now().microsecondsSinceEpoch}';
    final isArt = type == FieldType.art;
    final f = FieldSpec(
      id: id,
      type: type,
      frac: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.24),
      fill: isArt ? null : _paperRef,
      fillAlpha: 0.85,
      text: isArt
          ? null
          : const TextStyleSpec(sizeFrac: 0.035, colorRef: _inkRef),
    );
    _update(_d.copyWith(fields: [..._d.fields, f]));
    setState(() => _selectedFieldId = id);
  }

  void _removeField(String id) {
    _update(_d.copyWith(fields: _d.fields.where((f) => f.id != id).toList()));
    setState(() => _selectedFieldId = null);
  }

  void _changeFieldType(FieldSpec f, FieldType type) {
    var updated = f.copyWith(type: type);
    if (type == FieldType.art) {
      updated = updated.copyWith(text: null, fill: null);
    } else if (f.text == null) {
      updated = updated.copyWith(
          text: const TextStyleSpec(sizeFrac: 0.035, colorRef: _inkRef));
    }
    _updateField(updated);
  }

  void _setFrac(FieldSpec f, {double? l, double? t, double? r, double? b}) {
    const min = 0.03;
    var left = l ?? f.frac.left;
    var top = t ?? f.frac.top;
    var right = r ?? f.frac.right;
    var bottom = b ?? f.frac.bottom;
    if (l != null) left = left.clamp(0.0, right - min);
    if (r != null) right = right.clamp(left + min, 1.0);
    if (t != null) top = top.clamp(0.0, bottom - min);
    if (b != null) bottom = bottom.clamp(top + min, 1.0);
    _updateField(f.copyWith(frac: Rect.fromLTRB(left, top, right, bottom)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: _previewWithOverlay()),
    );

    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.layout, label: Text('Layout')),
              ButtonSegment(value: _Mode.fields, label: Text('Fields')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: _mode == _Mode.layout ? _layoutForm() : _fieldsPane(),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: preview),
              Expanded(flex: 5, child: pane),
            ],
          );
        }
        return Column(children: [preview, Expanded(child: pane)]);
      },
    );
  }

  Widget _previewWithOverlay() {
    final h = _previewW * _d.heightInches / _d.widthInches;
    final sel = _selectedField;
    final card = composeCard(_d, content: sampleContent());
    return SizedBox(
      width: _previewW,
      height: h,
      child: Stack(
        children: [
          CardPreview(
              card: card,
              refs: CardRefs(palette: widget.palette),
              width: _previewW),
          if (_mode == _Mode.fields && sel != null)
            Positioned(
              left: sel.frac.left * _previewW,
              top: sel.frac.top * h,
              width: sel.frac.width * _previewW,
              height: sel.frac.height * h,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Layout pane ----

  Widget _layoutForm() {
    final border = _d.border;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'Template name',
              isDense: true,
              border: OutlineInputBorder()),
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
                  () => _update(_d.copyWith(
                      baseColor: ColorRef(id: s.id, snapshot: s.value)))),
          ],
        ),
        const SizedBox(height: 20),
        Row(children: [
          Text('Border', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Switch(
            value: border != null,
            onChanged: (on) => _update(_d.copyWith(
                border: on
                    ? const BorderSpec(black: true, thickness: 0.022)
                    : null)),
          ),
        ]),
        if (border != null) ...[
          _labeledSlider('Thickness', border.thickness, 0.005, 0.05,
              (v) => _update(_d.copyWith(
                  border: BorderSpec(black: border.black, thickness: v)))),
          Row(children: [
            const SizedBox(width: 80, child: Text('Colour')),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Black')),
                ButtonSegment(value: false, label: Text('White')),
              ],
              selected: {border.black},
              onSelectionChanged: (s) => _update(_d.copyWith(
                  border:
                      BorderSpec(black: s.first, thickness: border.thickness))),
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
      ],
    );
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
              child: Text('Custom (${_d.widthInches} × ${_d.heightInches})')),
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

  // ---- Fields pane ----

  Widget _fieldsPane() {
    final sel = _selectedField;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Fields', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            PopupMenuButton<FieldType>(
              onSelected: _addField,
              itemBuilder: (_) => [
                for (final t in FieldType.values)
                  PopupMenuItem(value: t, child: Text(_typeLabel(t))),
              ],
              child: const Chip(
                avatar: Icon(Icons.add, size: 18),
                label: Text('Add field'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _d.fields)
              ChoiceChip(
                label: Text(_typeLabel(f.type)),
                selected: f.id == _selectedFieldId,
                onSelected: (_) => setState(() => _selectedFieldId = f.id),
              ),
          ],
        ),
        const Divider(height: 28),
        if (sel == null)
          Text('Select a field to edit it, or add one.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          _fieldEditor(sel),
      ],
    );
  }

  Widget _fieldEditor(FieldSpec f) {
    final text = f.text;
    final outline = f.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Type')),
            Expanded(
              child: DropdownButton<FieldType>(
                isExpanded: true,
                value: f.type,
                items: [
                  for (final t in FieldType.values)
                    DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                ],
                onChanged: (t) {
                  if (t != null) _changeFieldType(f, t);
                },
              ),
            ),
            IconButton(
              tooltip: 'Remove field',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeField(f.id),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Position', style: Theme.of(context).textTheme.labelLarge),
        _labeledSlider('Left', f.frac.left, 0, 1, (v) => _setFrac(f, l: v)),
        _labeledSlider('Top', f.frac.top, 0, 1, (v) => _setFrac(f, t: v)),
        _labeledSlider('Right', f.frac.right, 0, 1, (v) => _setFrac(f, r: v)),
        _labeledSlider('Bottom', f.frac.bottom, 0, 1, (v) => _setFrac(f, b: v)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _labeledSlider('Corner', f.cornerRadius, 0, 0.1,
                (v) => _updateField(f.copyWith(cornerRadius: v))),
          ),
          const Text('Sharp'),
          Switch(
            value: f.sharp,
            onChanged: (v) => _updateField(f.copyWith(sharp: v)),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Fill', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _noneTile(f.fill == null, () => _updateField(f.copyWith(fill: null))),
          for (final s in widget.swatches)
            _swatch(s.value, s.id == f.fill?.id,
                () => _updateField(
                    f.copyWith(fill: ColorRef(id: s.id, snapshot: s.value)))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text('Outline', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          Switch(
            value: outline != null,
            onChanged: (on) => _updateField(
                f.copyWith(outline: on ? const OutlineSpec() : null)),
          ),
        ]),
        if (outline != null) ...[
          _labeledSlider('Intensity', outline.intensity, 0, 1,
              (v) => _updateField(f.copyWith(outline: outline.copyWith(intensity: v)))),
          Row(children: [
            const SizedBox(width: 80, child: Text('Lighter')),
            Switch(
              value: outline.lighter,
              onChanged: (v) => _updateField(
                  f.copyWith(outline: outline.copyWith(lighter: v))),
            ),
          ]),
        ],
        if (text != null) ...[
          const SizedBox(height: 12),
          Text('Text', style: Theme.of(context).textTheme.labelLarge),
          _labeledSlider('Size', text.sizeFrac, 0.01, 0.12,
              (v) => _updateField(f.copyWith(text: text.copyWith(sizeFrac: v)))),
          Row(children: [
            const SizedBox(width: 80, child: Text('Bold')),
            Switch(
              value: text.bold,
              onChanged: (v) =>
                  _updateField(f.copyWith(text: text.copyWith(bold: v))),
            ),
            const SizedBox(width: 12),
            SegmentedButton<TextAlign>(
              segments: const [
                ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left)),
                ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center)),
                ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right)),
              ],
              selected: {text.align},
              onSelectionChanged: (s) => _updateField(
                  f.copyWith(text: text.copyWith(align: s.first))),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Text colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in widget.swatches)
              _swatch(s.value, s.id == text.colorRef.id,
                  () => _updateField(f.copyWith(
                      text: text.copyWith(
                          colorRef: ColorRef(id: s.id, snapshot: s.value))))),
          ]),
        ],
      ],
    );
  }

  // ---- shared bits ----

  Widget _labeledSlider(String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      Row(children: [
        SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged),
        ),
      ]);

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

  Widget _noneTile(bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1),
        ),
        child: Icon(Icons.block, size: 18, color: scheme.outline),
      ),
    );
  }
}

String _typeLabel(FieldType t) => t.name[0].toUpperCase() + t.name.substring(1);
