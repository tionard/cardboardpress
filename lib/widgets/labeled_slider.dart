// lib/widgets/labeled_slider.dart
//
// A slider built for touch: a label, fine −/+ stepper buttons, the slider
// itself, and a tappable readout you can type an exact value into. The drag is
// for rough aim; precision comes from the stepper (nudge by [step]) and the
// readout (tap to type). That combination fixes the "can't land the fingertip
// on 0.25" problem on a phone without losing the quick visual drag.
//
// Fully controlled: [value] always comes from the parent, and every change —
// drag, step, or typed entry — is reported through [onChanged], clamped to
// [min]..[max]. The widget holds no value state of its own (only whether the
// readout is currently being edited).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LabeledSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Increment for the −/+ buttons and the slider's snapping. If null, a
  /// sensible step is derived from the range (finer ranges step finer) — the
  /// same rule the old inline sliders used, so existing controls are unchanged.
  final double? step;

  /// Readout precision. 0 shows an integer (e.g. an RGB 0–255 channel).
  final int decimals;

  final double labelWidth;
  final bool showStepper;
  final bool editable;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.step,
    this.decimals = 2,
    this.labelWidth = 80,
    this.showStepper = true,
    this.editable = true,
  });

  @override
  State<LabeledSlider> createState() => _LabeledSliderState();
}

class _LabeledSliderState extends State<LabeledSlider> {
  bool _editing = false;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  double get _step =>
      widget.step ?? ((widget.max - widget.min) <= 0.15 ? 0.005 : 0.05);

  int get _divisions =>
      ((widget.max - widget.min) / _step).round().clamp(1, 1000);

  double _clamp(double v) => v.clamp(widget.min, widget.max).toDouble();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  void _emit(double v) {
    final c = _clamp(v);
    if (c != _clamp(widget.value)) widget.onChanged(c);
  }

  // Nudge by one step, snapped to the step grid so repeated taps stay tidy.
  void _nudge(double delta) =>
      _emit((((_clamp(widget.value) + delta) / _step).round() * _step));

  void _beginEdit() {
    if (!widget.editable) return;
    _ctrl.text = _fmt(_clamp(widget.value));
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    });
  }

  void _commitEdit() {
    if (!_editing) return;
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (parsed != null) _emit(parsed);
    setState(() => _editing = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _clamp(widget.value);

    final readout = SizedBox(
      width: 56,
      child: _editing
          ? TextField(
              controller: _ctrl,
              focusNode: _focus,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ],
              style: theme.textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              ),
              onSubmitted: (_) => _commitEdit(),
              onTapOutside: (_) => _commitEdit(),
            )
          : InkWell(
              onTap: widget.editable ? _beginEdit : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _fmt(shown),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
    );

    return Row(
      children: [
        SizedBox(
          width: widget.labelWidth,
          child: Text(widget.label, style: theme.textTheme.bodySmall),
        ),
        if (widget.showStepper)
          _StepButton(
            icon: Icons.remove,
            onTap: shown > widget.min ? () => _nudge(-_step) : null,
          ),
        Expanded(
          child: Slider(
            value: shown,
            min: widget.min,
            max: widget.max,
            divisions: _divisions,
            onChanged: (v) {
              if (_editing) _commitEdit();
              widget.onChanged(_clamp(v));
            },
          ),
        ),
        if (widget.showStepper)
          _StepButton(
            icon: Icons.add,
            onTap: shown < widget.max ? () => _nudge(_step) : null,
          ),
        readout,
      ],
    );
  }
}

// A compact, tooltip-free icon button. No tooltip on purpose: tooltips inside
// scrollable lists trigger the benign-but-noisy AXTree console spam on Windows.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }
}
