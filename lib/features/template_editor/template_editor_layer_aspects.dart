// lib/features/template_editor/template_editor_layer_aspects.dart
//
// Per-aspect SECTION BUILDERS for the selected layer: fill, image, outline,
// text (the big one), border/9-slice, foil, watermark — plus the Add-aspect
// menu and the defaults an aspect gets when first switched on. This is the
// file that grows when a new aspect (or aspect control) is added; the pane
// scaffolding and the mutation engine stay in template_editor_layers.dart.

part of 'template_editor_screen.dart';

const ColorRef _kWatermarkDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF2C2B27)));

// Defaults used when an aspect is first switched on, or a new layer is created.
const ColorRef _kLayerFillDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF9E9E9E)));
const ColorRef _kLayerTextDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF1A1A1A)));
const ColorRef _kOutlineDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF1A1A1A)));

extension _TemplateLayerAspects on _TemplateBodyState {
  List<Widget> _layerAspectSections(Layer layer) {
    final id = layer.id;
    final fill = layer.fill;
    final image = layer.image;
    final border = layer.border;
    final outline = layer.outline;
    final foil = layer.foil;
    final text = layer.text;
    final wm = layer.watermark;
    return [
      if (fill != null)
        _section('l_fill', 'Fill', [
          Text('Colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _colorWell(
            current: fill.color,
            use: SwatchUse.card,
            onPicked: (r) => _updateLayer(
                id,
                (l) => l.copyWith(
                    fill: (l.fill ?? const FillAspect(color: _kLayerFillDefault))
                        .copyWith(color: r))),
          ),
          _labeledSlider('Opacity', fill.alpha, 0, 1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(fill: l.fill?.copyWith(alpha: v)))),
          _exposeControl(id, ExposedAspect.fill, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(fill: null))),
        ]),
      if (image != null)
        _section('l_image', 'Image', [
          Row(children: [
            const SizedBox(width: 80, child: Text('Source')),
            Expanded(
              child: SegmentedButton<ImageSource>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: ImageSource.fixed, label: Text('Picture')),
                  ButtonSegment(
                      value: ImageSource.setSymbol, label: Text('Set symbol')),
                  ButtonSegment(
                      value: ImageSource.cardArt, label: Text('Card art')),
                ],
                selected: {image.source},
                onSelectionChanged: (s) => _updateLayer(id,
                    (l) => l.copyWith(image: l.image?.copyWith(source: s.first))),
              ),
            ),
          ]),
          if (image.source == ImageSource.fixed)
            Row(children: [
              const SizedBox(width: 80, child: Text('Picture')),
              OutlinedButton.icon(
                onPressed: () => _pickLayerImage(layer),
                icon: const Icon(Icons.image_outlined),
                label: Text(image.imageId.isEmpty ? 'Choose…' : 'Change…'),
              ),
            ])
          else if (image.source == ImageSource.setSymbol)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  "Uses the card's set symbol, tinted by the rarity colour.",
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Per-card artwork: each card picks and positions its own '
                  'image in the Card Editor\u2019s Art tab. Empty shows the '
                  'ART placeholder.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          if (image.source == ImageSource.fixed) ...[
            Text('Tint (silhouette)',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _colorWell(
              current: image.tint,
              use: SwatchUse.card,
              onPicked: (r) => _updateLayer(
                  id, (l) => l.copyWith(image: l.image?.copyWith(tint: r))),
              onClear: () => _updateLayer(
                  id, (l) => l.copyWith(image: l.image?.copyWith(tint: null))),
            ),
          ],
          _labeledSlider('Opacity', image.alpha, 0, 1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(image: l.image?.copyWith(alpha: v)))),
          if (image.source == ImageSource.fixed) ...[
            Row(children: [
              Expanded(
                child: Text('Position',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              if (!image.transform.isIdentity)
                TextButton(
                  onPressed: () => _updateLayer(id,
                      (l) => l.copyWith(
                          image: l.image?.copyWith(transform: const ArtTransform()))),
                  child: const Text('Reset'),
                ),
            ]),
            _labeledSlider('Zoom', image.transform.zoom, 1.0, 3.0,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(
                        image: l.image?.copyWith(transform: image.transform.copyWith(zoom: v))))),
            _labeledSlider('Horizontal', image.transform.panX, -1.0, 1.0,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(
                        image: l.image?.copyWith(transform: image.transform.copyWith(panX: v))))),
            _labeledSlider('Vertical', image.transform.panY, -1.0, 1.0,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(
                        image: l.image?.copyWith(transform: image.transform.copyWith(panY: v))))),
          ],
          if (image.source != ImageSource.cardArt)
            _exposeControl(id, ExposedAspect.image, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(image: null))),
        ]),
      if (border != null)
        _section('l_border', 'Border (9-slice)', [
          Text(
              'A sliced frame from your Frames library. While on, it replaces '
              'the flat fill.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 80, child: Text('Frame')),
            Expanded(
              child: Text(
                ref.watch(framesMapProvider)[border.frameId]?.name ??
                    (border.hasImage ? 'Saved copy (frame deleted)' : '(none)'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickLayerBorder(layer),
              icon: const Icon(Icons.image_outlined),
              label: Text(border.hasImage ? 'Change…' : 'Choose…'),
            ),
          ]),
          if (border.hasImage) ...[
            const SizedBox(height: 8),
            // The slicing (cuts + tile modes) is library-owned: editing it
            // changes the frame for EVERY template that uses it. Only the
            // use-site properties below belong to this layer.
            Builder(builder: (_) {
              final f = ref.watch(framesMapProvider)[border.frameId];
              if (f == null) {
                return Text(
                    'This layer renders the copy it saved when the frame was '
                    'picked. Choose a frame to follow the library again.',
                    style: Theme.of(context).textTheme.bodySmall);
              }
              return Row(children: [
                Expanded(
                  child: Text(
                      'Cuts and tiling come from the library frame (shared by '
                      'every template using it).',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                TextButton(
                  onPressed: () async {
                    await editFrameSlicing(context, ref, f);
                    _syncImages();
                  },
                  child: const Text('Edit frame…'),
                ),
              ]);
            }),
            _labeledSlider('Thickness', border.thickness, 0, 0.2,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(border: l.border?.copyWith(thickness: v)))),
            Text(
                'Drawn size of the thickest side; the others scale in '
                'proportion to the frame\'s cuts.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            _aspectToggle(
                'Fill center',
                border.drawCenter,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(border: l.border?.copyWith(drawCenter: v)))),
            const SizedBox(height: 8),
            Text('Tint', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _colorWell(
              current: border.tint,
              use: SwatchUse.card,
              onPicked: (r) => _updateLayer(
                  id, (l) => l.copyWith(border: l.border?.copyWith(tint: r))),
              onClear: () => _updateLayer(
                  id, (l) => l.copyWith(border: l.border?.copyWith(tint: null))),
            ),
          ],
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(border: null))),
        ]),
      if (outline != null)
        _section('l_outline', 'Outline', [
          Text('Colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _colorWell(
            current: outline.color,
            use: SwatchUse.card,
            onPicked: (r) => _updateLayer(
                id, (l) => l.copyWith(outline: l.outline?.copyWith(color: r))),
          ),
          _labeledSlider(
              'Thickness',
              outline.thickness,
              0,
              0.02,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(outline: l.outline?.copyWith(thickness: v)))),
          _labeledSlider(
              'Opacity',
              outline.alpha,
              0,
              1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(outline: l.outline?.copyWith(alpha: v)))),
          if (outline.color == null && fill == null)
            Text('This outline shades the fill — pick a colour, or add a Fill.',
                style: Theme.of(context).textTheme.bodySmall),
          _exposeControl(id, ExposedAspect.outlineColor, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(outline: null))),
        ]),
      if (foil != null)
        _section('l_foil', 'Foil', [
          Row(children: [
            const SizedBox(width: 80, child: Text('Style')),
            Expanded(
              child: SegmentedButton<FoilType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: FoilType.none, label: Text('None')),
                  ButtonSegment(value: FoilType.holo, label: Text('Holo')),
                  ButtonSegment(value: FoilType.gold, label: Text('Gold')),
                ],
                selected: {foil},
                onSelectionChanged: (s) =>
                    _updateLayer(id, (l) => l.copyWith(foil: s.first)),
              ),
            ),
          ]),
          _exposeControl(id, ExposedAspect.foil, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(foil: null))),
        ]),
      if (wm != null)
        _section('l_wm', 'Watermark', [
          Text('A symbol drawn faintly behind this layer\u2019s text.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 80, child: Text('Symbol')),
            OutlinedButton.icon(
              onPressed: () => _pickLayerWatermarkSymbol(layer),
              icon: const Icon(Icons.image_outlined),
              label: Text(wm.symbolId.isEmpty ? 'Choose…' : 'Change…'),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _colorWell(
            current: wm.color,
            use: SwatchUse.symbol,
            onPicked: (r) => _updateLayer(id,
                (l) => l.copyWith(watermark: l.watermark?.copyWith(color: r))),
          ),
          _labeledSlider(
              'Opacity',
              wm.alpha,
              0,
              1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(watermark: l.watermark?.copyWith(alpha: v)))),
          _exposeControl(id, ExposedAspect.watermark, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(watermark: null))),
        ]),
      if (text != null)
        _section('l_text', 'Text', [
          ..._textAspectControls(layer, text),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(text: null))),
        ]),
      const SizedBox(height: 8),
      _addAspectMenu(layer),
    ];
  }

  /// A right-aligned "Remove" button ending an aspect section.
  Widget _removeAspectRow(VoidCallback onRemove) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Remove'),
        ),
      );

  /// "+ Add aspect" — lists only the aspects this layer doesn't have yet.
  Widget _addAspectMenu(Layer layer) {
    final absent = <String, String>{
      if (layer.fill == null) 'fill': 'Fill',
      if (layer.image == null) 'image': 'Image',
      if (layer.border == null) 'border': 'Border (9-slice)',
      if (layer.outline == null) 'outline': 'Outline',
      if (layer.foil == null) 'foil': 'Foil',
      if (layer.text == null) 'text': 'Text',
      if (layer.watermark == null) 'watermark': 'Watermark',
    };
    if (absent.isEmpty) {
      return Text('All aspects added.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        onSelected: (a) => _addAspect(layer, a),
        itemBuilder: (ctx) => [
          for (final e in absent.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: const Chip(
          avatar: Icon(Icons.add, size: 18),
          label: Text('Add aspect'),
        ),
      ),
    );
  }

  void _addAspect(Layer layer, String a) {
    _updateLayer(
        layer.id,
        (l) => switch (a) {
              'fill' =>
                l.copyWith(fill: const FillAspect(color: _kLayerFillDefault)),
              'image' => l.copyWith(image: const ImageAspect()),
              'border' => l.copyWith(border: const NineSliceSpec()),
              'outline' =>
                l.copyWith(outline: const OutlineSpec(color: _kOutlineDefault)),
              'foil' => l.copyWith(foil: FoilType.holo),
              'text' => l.copyWith(text: _defaultTextAspect()),
              'watermark' => l.copyWith(
                  watermark: const WatermarkSpec(color: _kWatermarkDefault)),
              _ => l,
            });
  }

  List<Widget> _textAspectControls(Layer layer, TextAspect text) {
    final id = layer.id;
    final s = text.style;
    final placeholder = text.placeholder;
    final partsSummary = text.parts.isEmpty
        ? 'Free text (typed on the card)'
        : text.parts.map(_textSourceLabel).join(' ${text.separator} ');
    return [
      Row(children: [
        const SizedBox(width: 80, child: Text('Sources')),
        Expanded(
          child: Text(partsSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
            onPressed: () => _editTextParts(layer), child: const Text('Edit…')),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Placeholder')),
        Expanded(
          child: Text(placeholder.isEmpty ? '(none)' : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
            onPressed: () => _editLayerPlaceholder(layer),
            child: const Text('Edit…')),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Multiline')),
        Switch(
          value: text.multiline,
          onChanged: (v) => _updateLayer(
              id, (l) => l.copyWith(text: l.text?.copyWith(multiline: v))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Wrap to multiple lines (and a multi-line card field).',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Markup')),
        Switch(
          value: text.inline,
          onChanged: (v) => _updateLayer(
              id, (l) => l.copyWith(text: l.text?.copyWith(inline: v))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Parse {symbols} and **bold** / *italic*.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Font')),
        Expanded(
          child: DropdownButton<String?>(
            value: s.fontFamily,
            isExpanded: true,
            // Each entry renders in its own face — the fonts are bundled
            // assets, so the widget layer can use them directly. The stored
            // value is the pubspec family string; null = app default.
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Default'),
              ),
              for (final f in kFontCatalog)
                DropdownMenuItem<String?>(
                  value: f.family,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: f.family,
                        style: TextStyle(fontFamily: f.family, fontSize: 16),
                      ),
                      TextSpan(
                        text: '  · ${f.note}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    ]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (fam) => _updateLayer(
                id,
                (l) => l.copyWith(
                    text: l.text?.copyWith(style: s.copyWith(fontFamily: fam)))),
          ),
        ),
      ]),
      _labeledSlider(
          'Size',
          s.sizeFrac,
          0.01,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(sizeFrac: v))))),
      Row(children: [
        const SizedBox(width: 80, child: Text('Bold')),
        Switch(
          value: s.bold,
          onChanged: (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(bold: v)))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<TextAlign>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: TextAlign.left, icon: Icon(Icons.format_align_left)),
              ButtonSegment(
                  value: TextAlign.center, icon: Icon(Icons.format_align_center)),
              ButtonSegment(
                  value: TextAlign.right, icon: Icon(Icons.format_align_right)),
            ],
            selected: {s.align},
            onSelectionChanged: (a) => _updateLayer(id,
                (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(align: a.first)))),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 80, child: Text('Anchor')),
        SegmentedButton<VAlign>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: VAlign.top, icon: Icon(Icons.vertical_align_top)),
            ButtonSegment(
                value: VAlign.middle, icon: Icon(Icons.vertical_align_center)),
            ButtonSegment(
                value: VAlign.bottom, icon: Icon(Icons.vertical_align_bottom)),
          ],
          selected: {s.vAlign},
          onSelectionChanged: (a) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(vAlign: a.first)))),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 80, child: Text('Fit')),
        SegmentedButton<TextFit>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TextFit.fixed, label: Text('Fixed')),
            ButtonSegment(value: TextFit.shrink, label: Text('Shrink')),
          ],
          selected: {s.fit},
          onSelectionChanged: (a) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(fit: a.first)))),
        ),
      ]),
      _labeledSlider(
          'Side padding',
          s.padX,
          0,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(padX: v))))),
      _labeledSlider(
          'Vert padding',
          s.padY,
          0,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(padY: v))))),
      const SizedBox(height: 8),
      Text('Colour', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      _colorWell(
        current: s.colorRef,
        use: SwatchUse.text,
        onPicked: (r) => _updateLayer(id,
            (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(colorRef: r)))),
      ),
      _labeledSlider(
          'Opacity',
          s.colorAlpha,
          0,
          1,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(colorAlpha: v))))),
      _exposeControl(id, ExposedAspect.text, layer.exposed),
    ];
  }

  Widget _aspectToggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(children: [
        SizedBox(width: 80, child: Text(label)),
        Switch(value: value, onChanged: onChanged),
      ]);

}
