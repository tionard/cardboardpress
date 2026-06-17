// lib/features/card_editor/card_editor_screen.dart
//
// Card Editor: preview + a category rail + a settings pane, arranged
// responsively (side-by-side when wide, stacked when narrow). The "Card"
// category is the content form — one debounced-autosave input per authorable
// text field. Other categories are placeholders for upcoming work.
//
// Per flutter-conventions.md these are independent panes driven by a width
// breakpoint, so the eventual phone slide-up dock vs tablet side-by-side is a
// layout change, not a rewrite.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_repository.dart';
import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../spike/spike_screen.dart';

class CardEditorScreen extends ConsumerWidget {
  const CardEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider);
    final templates = ref.watch(templatesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <TemplateEntry>[],
        );
    final templatesMap = ref.watch(templatesMapProvider);
    final refs = CardRefs(palette: ref.watch(paletteMapProvider));

    return cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load cards:\n$e')),
      data: (cards) {
        if (cards.isEmpty) {
          return const Center(child: Text('No cards yet.'));
        }
        final card = cards.first;
        return _CardEditorBody(
          key: ValueKey(card.id),
          card: card,
          templates: templates,
          templatesMap: templatesMap,
          refs: refs,
          repo: ref.read(cardRepositoryProvider),
        );
      },
    );
  }
}

// Rail categories (flutter-conventions.md §"Card Editor dock").
enum _Cat { card, art, color, set, export }

const _catLabels = {
  _Cat.card: 'Card',
  _Cat.art: 'Art',
  _Cat.color: 'Color',
  _Cat.set: 'Set',
  _Cat.export: 'Export',
};
const _catIcons = {
  _Cat.card: Icons.style_outlined,
  _Cat.art: Icons.image_outlined,
  _Cat.color: Icons.palette_outlined,
  _Cat.set: Icons.folder_outlined,
  _Cat.export: Icons.ios_share_outlined,
};

class _CardEditorBody extends StatefulWidget {
  final CardEntry card;
  final List<TemplateEntry> templates;
  final Map<String, TemplateData> templatesMap;
  final CardRefs refs;
  final CardRepository repo;

  const _CardEditorBody({
    super.key,
    required this.card,
    required this.templates,
    required this.templatesMap,
    required this.refs,
    required this.repo,
  });

  @override
  State<_CardEditorBody> createState() => _CardEditorBodyState();
}

class _CardEditorBodyState extends State<_CardEditorBody> {
  late CardEntry _working;
  final Map<String, TextEditingController> _controllers = {};
  Timer? _saveTimer;
  _Cat _cat = _Cat.card;

  @override
  void initState() {
    super.initState();
    _working = widget.card;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.repo.save(_working); // flush latest edit
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // One controller per field id, created on demand and seeded from content.
  TextEditingController _controllerFor(FieldSpec f) {
    return _controllers.putIfAbsent(f.id, () {
      final c = TextEditingController(text: _working.content.text[f.id] ?? '');
      c.addListener(() => _onFieldChanged(f.id, c.text));
      return c;
    });
  }

  void _onFieldChanged(String fieldId, String value) {
    if ((_working.content.text[fieldId] ?? '') == value) return;
    setState(() {
      _working =
          _working.copyWith(content: _working.content.withText(fieldId, value));
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_working));
  }

  void _changeTemplate(String? id) {
    if (id == null) return;
    final snapshot = widget.templatesMap[id] ?? _working.templateSnapshot;
    setState(() => _working =
        _working.copyWith(templateId: id, templateSnapshot: snapshot));
    widget.repo.save(_working);
  }

  TemplateData get _effective => _working.effectiveTemplate(widget.templatesMap);

  // Authorable text fields: text-bearing, excluding the derived Footer.
  List<FieldSpec> get _editableFields => _effective.fields
      .where((f) => f.text != null && f.type != FieldType.footer)
      .toList();

  @override
  Widget build(BuildContext context) {
    final card = composeCard(_effective,
        content: _working.content, foil: _working.foil);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final preview = Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: CardPreview(
                card: card, refs: widget.refs, width: wide ? 300 : 220),
          ),
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: preview),
              _Rail(
                vertical: true,
                selected: _cat,
                onSelect: (c) => setState(() => _cat = c),
              ),
              Expanded(
                flex: 4,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _settings(),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            preview,
            _Rail(
              vertical: false,
              selected: _cat,
              onSelect: (c) => setState(() => _cat = c),
            ),
            Expanded(child: _settings()),
          ],
        );
      },
    );
  }

  Widget _settings() {
    switch (_cat) {
      case _Cat.card:
        return _cardSettings();
      case _Cat.export:
        return _exportSettings();
      default:
        return Center(
          child: Text('${_catLabels[_cat]} — coming soon',
              style: Theme.of(context).textTheme.bodyMedium),
        );
    }
  }

  Widget _cardSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Template: '),
            DropdownButton<String>(
              value: widget.templates.any((t) => t.id == _working.templateId)
                  ? _working.templateId
                  : null,
              items: [
                for (final t in widget.templates)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: _changeTemplate,
            ),
          ],
        ),
        const Divider(height: 28),
        for (final f in _editableFields) ...[
          TextField(
            controller: _controllerFor(f),
            maxLines: f.type == FieldType.rules ? 4 : 1,
            decoration: InputDecoration(
              labelText: _fieldLabel(f.type),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          'Each field autosaves as you type and the preview updates live. The '
          'Footer is omitted — it shows values derived from the set and rarity, '
          'which it will once those exist.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _exportSettings() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Export & share — coming soon',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SpikeScreen()),
            ),
            icon: const Icon(Icons.compare_outlined),
            label: const Text('Preview-vs-PNG spike'),
          ),
        ],
      ),
    );
  }
}

String _fieldLabel(FieldType t) =>
    t.name[0].toUpperCase() + t.name.substring(1);

// The category rail — vertical (wide) or horizontal (narrow).
class _Rail extends StatelessWidget {
  final bool vertical;
  final _Cat selected;
  final ValueChanged<_Cat> onSelect;

  const _Rail({
    required this.vertical,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = [
      for (final c in _Cat.values)
        _RailTile(
          icon: _catIcons[c]!,
          label: _catLabels[c]!,
          selected: c == selected,
          accent: scheme.primary,
          onTap: () => onSelect(c),
        ),
    ];

    if (vertical) {
      return Container(
        width: 84,
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: tiles,
        ),
      );
    }
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tiles,
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RailTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
