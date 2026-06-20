part of 'card_editor_screen.dart';

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
