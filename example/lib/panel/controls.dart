import 'package:flutter/material.dart';
import 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';

import '../settings.dart';

/// The colors offered by [ParamColor].
const _palette = [
  Color(0xFF212121),
  Color(0xFFFFFFFF),
  Color(0xFF6D5A72),
  Color(0xFFC62828),
  Color(0xFFEF6C00),
  Color(0xFFFFF59D),
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
  Color(0xFF6A1B9A),
];

/// The title of a group of settings.
class Section extends StatelessWidget {
  const new(this.title, {this.note, super.key});

  final String title;

  /// A short explanation below the title.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The name of a parameter, its current value and a hint, above its control.
class _Param extends StatelessWidget {
  const new({
    required this.name,
    this.hint,
    this.value,
    this.trailing,
    this.child,
  });

  final String name;
  final String? hint;
  final String? value;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ?trailing,
            ],
          ),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ?child,
        ],
      ),
    );
  }
}

/// A slider without the default side margins.
class _Slider extends StatelessWidget {
  const new({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        overlayShape: SliderComponentShape.noOverlay,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: SizedBox(
        height: 32,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class ParamSwitch extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String name;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: _Param(
        name: name,
        hint: hint,
        trailing: SizedBox(
          height: 28,
          child: FittedBox(
            child: Switch(value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}

class ParamSlider extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint,
    this.step = 1,
    this.digits = 0,
    this.unit = '',
    super.key,
  });

  final String name;
  final String? hint;
  final double value;
  final double min;
  final double max;

  /// The distance of the values that can be selected.
  final double step;

  /// The number of fraction digits shown.
  final int digits;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Param(
      name: name,
      hint: hint,
      value: '${value.toStringAsFixed(digits)}$unit',
      child: _Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        onChanged: onChanged,
      ),
    );
  }
}

/// A slider of a parameter that can be null.
class ParamOptionalSlider extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.initial,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint,
    this.step = 1,
    this.digits = 0,
    super.key,
  });

  final String name;
  final String? hint;
  final double? value;

  /// The value the parameter gets when it is turned on.
  final double initial;
  final double min;
  final double max;
  final double step;
  final int digits;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return _Param(
      name: name,
      hint: hint,
      value: v == null ? 'null' : v.toStringAsFixed(digits),
      trailing: SizedBox(
        height: 28,
        child: Checkbox(
          value: v != null,
          onChanged: (on) => onChanged(on! ? initial : null),
        ),
      ),
      child: _Slider(
        value: v ?? initial,
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        onChanged: v == null ? null : onChanged,
      ),
    );
  }
}

/// One of a few options, as chips.
class ParamChoice<T> extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String name;
  final String? hint;
  final T value;

  /// The options with their labels.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Param(
      name: name,
      hint: hint,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final MapEntry(:key, value: label) in options.entries)
              ChoiceChip(
                label: Text(label),
                selected: key == value,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onChanged(key),
              ),
          ],
        ),
      ),
    );
  }
}

class ParamColor extends StatelessWidget {
  const new({
    required this.name,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String name;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Param(
      name: name,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in _palette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(color),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == value
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: color == value ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The order of the candidate sides, and which ones are used.
class SidesEditor extends StatelessWidget {
  const new({
    required this.order,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final List<LabelSide> order;
  final Set<LabelSide> enabled;
  final void Function(List<LabelSide> order, Set<LabelSide> enabled) onChanged;

  void _move(int from, int to) {
    final next = [...order];
    next.insert(to, next.removeAt(from));
    onChanged(next, enabled);
  }

  @override
  Widget build(BuildContext context) {
    return _Param(
      name: 'sides',
      hint: 'The candidate sides, tried from top to bottom.',
      child: Column(
        children: [
          for (final (i, side) in order.indexed)
            Row(
              children: [
                Checkbox(
                  value: enabled.contains(side),
                  visualDensity: VisualDensity.compact,
                  onChanged: (on) => onChanged(order, {
                    ...enabled.where((s) => s != side),
                    if (on!) side,
                  }),
                ),
                Expanded(child: Text('${i + 1}. ${side.name}')),
                IconButton(
                  tooltip: 'Try earlier',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0 ? null : () => _move(i, i - 1),
                ),
                IconButton(
                  tooltip: 'Try later',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == order.length - 1
                      ? null
                      : () => _move(i, i + 1),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The controls of a [LabelStyle].
class LabelStyleEditor extends StatelessWidget {
  const new({
    required this.style,
    required this.onChanged,
    this.spacingHint = 'The distance of the label from its marker.',
    this.boxNote,
    super.key,
  });

  final LabelStyleSettings style;

  /// Called with a function that changes [style].
  final ValueChanged<VoidCallback> onChanged;

  final String spacingHint;

  /// Shown above the padding and decoration controls.
  final String? boxNote;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParamSlider(
          name: 'textStyle.fontSize',
          value: s.fontSize,
          min: 8,
          max: 24,
          onChanged: (v) => onChanged(() => s.fontSize = v),
        ),
        ParamSwitch(
          name: 'textStyle.fontWeight: bold',
          value: s.bold,
          onChanged: (v) => onChanged(() => s.bold = v),
        ),
        ParamSwitch(
          name: 'textStyle.fontStyle: italic',
          value: s.italic,
          onChanged: (v) => onChanged(() => s.italic = v),
        ),
        ParamSlider(
          name: 'textStyle.letterSpacing',
          value: s.letterSpacing,
          min: 0,
          max: 6,
          step: .5,
          digits: 1,
          onChanged: (v) => onChanged(() => s.letterSpacing = v),
        ),
        ParamColor(
          name: 'textStyle.color',
          value: s.color,
          onChanged: (v) => onChanged(() => s.color = v),
        ),
        ParamChoice<HaloMode>(
          name: 'halo',
          hint: 'The outline around the text.',
          value: s.halo,
          options: const {
            .standard: 'TextLabelHalo()',
            .none: '.zero()',
            .custom: '.custom(...)',
          },
          onChanged: (v) => onChanged(() => s.halo = v),
        ),
        if (s.halo == HaloMode.custom) ...[
          ParamColor(
            name: 'halo.color',
            value: s.haloColor,
            onChanged: (v) => onChanged(() => s.haloColor = v),
          ),
          ParamSlider(
            name: 'halo.width',
            value: s.haloWidth,
            min: 0,
            max: 8,
            step: .5,
            digits: 1,
            onChanged: (v) => onChanged(() => s.haloWidth = v),
          ),
        ],
        ParamSlider(
          name: 'spacing',
          hint: spacingHint,
          value: s.spacing,
          min: 0,
          max: 16,
          onChanged: (v) => onChanged(() => s.spacing = v),
        ),
        if (boxNote != null) Section('Label box', note: boxNote),
        ParamSlider(
          name: 'padding.horizontal',
          hint: 'The padding is part of the collision size.',
          value: s.paddingH,
          min: 0,
          max: 16,
          onChanged: (v) => onChanged(() => s.paddingH = v),
        ),
        ParamSlider(
          name: 'padding.vertical',
          value: s.paddingV,
          min: 0,
          max: 16,
          onChanged: (v) => onChanged(() => s.paddingV = v),
        ),
        ParamChoice<BoxMode>(
          name: 'decoration',
          hint: 'The BoxDecoration of the label box.',
          value: s.box,
          options: const {
            .none: 'null',
            .filled: 'filled',
            .outlined: 'filled + border',
          },
          onChanged: (v) => onChanged(() => s.box = v),
        ),
        if (s.box != BoxMode.none) ...[
          ParamColor(
            name: 'decoration.color',
            value: s.boxColor,
            onChanged: (v) => onChanged(() => s.boxColor = v),
          ),
          ParamSlider(
            name: 'decoration.borderRadius',
            value: s.boxRadius,
            min: 0,
            max: 12,
            onChanged: (v) => onChanged(() => s.boxRadius = v),
          ),
        ],
      ],
    );
  }
}
