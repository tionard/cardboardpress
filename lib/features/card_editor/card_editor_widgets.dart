part of 'card_editor_screen.dart';

/// The small (i) button shown beside INLINE-capable text fields. Tapping it
/// opens a dialog explaining the syntax that field supports: {tag} symbols for
/// every inline field, plus *italic* / **bold** markup when the field is
/// multiline (rules-like text). Deliberately tooltip-free — tooltips inside
/// scrollable lists trigger the noisy AXTree console spam on Windows.
class _TextInfoButton extends StatelessWidget {
  /// True for multiline (rules-like) fields: shows the formatting popup.
  /// False for single-line fields (e.g. Cost): shows the {tag} popup only.
  final bool multiline;

  const _TextInfoButton({required this.multiline});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.info_outline),
        onPressed: () => _showHelp(context),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final code = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.primary,
    );

    // One syntax row: the literal typed form on the left, what it does on the
    // right (with the effect demonstrated in the description's own style).
    Widget row(String typed, InlineSpan meaning) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: Text(typed, style: code)),
              const SizedBox(width: 8),
              Expanded(child: Text.rich(meaning, style: body)),
            ],
          ),
        );

    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(multiline ? 'Text formatting' : 'Text symbols'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (multiline) ...[
                row('*text*',
                    TextSpan(
                        text: 'Italic text',
                        style: body?.copyWith(fontStyle: FontStyle.italic))),
                row('**text**',
                    TextSpan(
                        text: 'Bold text',
                        style: body?.copyWith(fontWeight: FontWeight.bold))),
                row('***text***',
                    TextSpan(
                        text: 'Bold italic text',
                        style: body?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic))),
                row('{tag}',
                    const TextSpan(
                        text: 'Draws that text symbol\u2019s glyph inline '
                            '\u2014 e.g. {R}{R} shows the \u201cR\u201d '
                            'symbol twice.')),
              ] else ...[
                Text(
                  'Wrap a symbol\u2019s tag in braces to draw its glyph '
                  'inline with the text.',
                  style: body,
                ),
                const SizedBox(height: 8),
                row('{R}{R}',
                    const TextSpan(
                        text: 'Shows the symbol tagged \u201cR\u201d twice.')),
              ],
              const SizedBox(height: 12),
              Text(
                'Text symbols are managed in Customize \u2192 Symbols \u2192 '
                'Text {tag}.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  final ColorValue value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final outline = scheme.outlineVariant;
    final radius = BorderRadius.circular(8);

    final decoration = value.c2 == null
        ? BoxDecoration(color: value.c1, borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [value.c1, value.c2!],
              begin: value.orientation == MixOrientation.vertical
                  ? Alignment.topCenter
                  : Alignment.centerLeft,
              end: value.orientation == MixOrientation.vertical
                  ? Alignment.bottomCenter
                  : Alignment.centerRight,
            ),
          );

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: decoration.copyWith(
              border: Border.all(
                  color: selected ? accent : outline, width: selected ? 3 : 1),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 48,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final bool vertical;

  /// When true (the phone dock), the vertical rail top-aligns and scrolls if the
  /// tiles don't fit. Desktop leaves this false so the tiles stay centred.
  final bool scroll;
  final _Cat selected;
  final ValueChanged<_Cat> onSelect;

  const _Rail({
    required this.vertical,
    required this.selected,
    required this.onSelect,
    this.scroll = false,
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
      final column = Column(
        mainAxisAlignment:
            scroll ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: tiles,
      );
      return Container(
        width: 84,
        color: scheme.surfaceContainerHighest,
        child: scroll
            ? SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: column,
              )
            : column,
      );
    }
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: tiles),
    );
  }
}

class _RailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RailTile(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.accent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant;
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
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
