import 'package:flutter/widgets.dart';

import 'labeled_marker.dart';
import 'screen_path.dart';

/// A label with its style and size resolved at the last recalculation.
///
/// The calculation and the painting must agree on the size and the spacing,
/// so they are resolved once per recalculation and reused until the next one.
/// Items without a non-empty label have a zero sized one.
class ResolvedLabel {
  const new(this.source, this.size, this.spacing, [this.style]);

  /// The item (marker, polyline, polygon) this was resolved for, to detect a changed item list.
  final Object source;

  /// The size of the label.
  final Size size;

  /// The spacing between the label and its marker.
  final double spacing;

  /// The style of the label, only for [TextLabel] type labels.
  final LabelStyle? style;
}

/// One character of a [GlyphRun], ready to be painted.
class Glyph {
  const new(this.fill, this.halo, this.offset, this.advance);

  final TextPainter fill;

  /// The outline painted below the [fill], if the style has a halo.
  final TextPainter? halo;

  /// The distance of the glyph from the start of the text.
  final double offset;

  /// The width reserved for the glyph.
  final double advance;
}

/// A text split into glyphs, so it can be painted along a curve.
class GlyphRun {
  const new(this.glyphs, this.width, this.height);

  final List<Glyph> glyphs;

  /// The width and height of the whole text (without padding).
  final double width;
  final double height;
}

/// Paints a [GlyphRun] along a path, every glyph turned to the direction of the path.
class PathTextPainter extends CustomPainter {
  const new(this.run, this.path, this.start);

  final GlyphRun run;

  /// The path in the coordinates of the painted box, in reading direction.
  final ScreenPath path;

  /// The distance along the path where the text starts.
  final double start;

  @override
  void paint(Canvas canvas, Size size) {
    for (final g in run.glyphs) {
      final d = start + g.offset + g.advance / 2;
      final w = g.advance;
      final a = path.pointAt(d - w / 2);
      final b = path.pointAt(d + w / 2);
      final c = path.pointAt(d);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..rotate((b - a).direction);
      final o = Offset(-g.advance / 2, -run.height / 2);
      g.halo?.paint(canvas, o);
      g.fill.paint(canvas, o);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PathTextPainter old) {
    if (old.run != run || (old.start - start).abs() > .01) {
      return true;
    }
    final p = old.path.points, q = path.points;
    if (p.length != q.length) return true;
    for (var i = 0; i < p.length; i++) {
      if ((p[i] - q[i]).distance > .01) return true;
    }
    return false;
  }
}

/// Measures and builds the labels for the labeled layers.
class LabelRenderer {
  /// Constant to ensure the same text height behavior is used regardless different font settings.
  static const _heightBehavior = TextHeightBehavior();

  /// A cache for the measured sizes of label texts by their style.
  final _sizeCache = <(String, LabelStyle), Size>{};

  /// A cache for the glyphs of label texts by their style.
  final _runCache = <(String, LabelStyle), GlyphRun>{};

  /// The base text style of the labels (the defaults of the context).
  TextStyle? _baseStyle;

  /// Updates the base text style from [context].
  ///
  /// Returns true if it changed, so the sizes must be calculated again.
  bool updateBaseStyle(BuildContext context) {
    var s = DefaultTextStyle.of(context).style;
    if (MediaQuery.boldTextOf(context)) {
      s = s.merge(const TextStyle(fontWeight: .bold));
    }
    if (s == _baseStyle) return false;
    _baseStyle = s;
    clearCache();
    return true;
  }

  /// Forgets the measured sizes and glyphs.
  ///
  /// The glyph painters are not disposed here: labels that are fading out may
  /// still paint them. They are released with the renderer.
  void clearCache() {
    _sizeCache.clear();
    _runCache.clear();
  }

  /// Releases the glyph painters. Call it when the owner layer is disposed.
  void dispose() {
    for (final run in _runCache.values) {
      for (final g in run.glyphs) {
        g.fill.dispose();
        g.halo?.dispose();
      }
    }
    _runCache.clear();
  }

  /// Resolves the style, size and spacing of [label] of [source].
  ///
  /// [styleFor] is only called for text labels. A missing or empty label, or a
  /// text label with a hidden style ([LabelStyle.hidden]), gets a zero size.
  ResolvedLabel resolve(
    BuildContext context,
    Object source,
    Label? label,
    LabelStyle Function() styleFor,
  ) => switch (label) {
    null => ResolvedLabel(source, Size.zero, 0),
    TextLabel(:final text) when text.isEmpty => ResolvedLabel(
      source,
      Size.zero,
      0,
    ),
    TextLabel(:final text) => _resolveText(context, source, text, styleFor()),
    WidgetLabel(:final size, :final spacing) => ResolvedLabel(
      source,
      size,
      spacing,
    ),
  };

  ResolvedLabel _resolveText(
    BuildContext context,
    Object source,
    String text,
    LabelStyle style,
  ) {
    // A style without a text style hides the label: it gets a zero size, so
    // the layers treat it as an item without a label.
    if (style.isHidden) return ResolvedLabel(source, Size.zero, 0);
    return ResolvedLabel(
      source,
      _measureText(context, text, style),
      style.spacing,
      style,
    );
  }

  Size _measureText(BuildContext context, String text, LabelStyle style) {
    if (text.isEmpty) return Size.zero;
    final key = (text, style);
    return _sizeCache.putIfAbsent(key, () {
      final ts = (_baseStyle ?? const TextStyle()).merge(style.textStyle);
      final tp = TextPainter(
        text: TextSpan(text: text, style: ts),
        textDirection: Directionality.maybeOf(context) ?? .ltr,
        textScaler: .noScaling,
        textHeightBehavior: _heightBehavior,
        textWidthBasis: .longestLine,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final s = Size(
        // +1 to prevent sub-pixel clipping.
        tp.width.ceilToDouble() + 1 + style.padding.horizontal,
        tp.height.ceilToDouble() + style.padding.vertical,
      );
      tp.dispose();
      return s;
    });
  }

  /// The glyphs of [text], to paint it along a curve with [PathTextPainter].
  ///
  /// Left-to-right text is assumed. The padding and the decoration of the
  /// style are not used for curved text.
  GlyphRun glyphRun(BuildContext context, String text, LabelStyle style) =>
      _runCache.putIfAbsent((
        text,
        style,
      ), () => _buildRun(context, text, style));

  GlyphRun _buildRun(BuildContext context, String text, LabelStyle style) {
    final ts = (_baseStyle ?? const TextStyle()).merge(style.textStyle);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final locale = Localizations.maybeLocaleOf(context);

    TextPainter layout(String t, TextStyle s) => TextPainter(
      text: TextSpan(text: t, style: s),
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      textHeightBehavior: _heightBehavior,
      locale: locale,
      maxLines: 1,
    )..layout();

    final h = style.halo;
    final haloStyle = h.width != null && h.color != null
        ? ts.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = h.width!
              ..color = h.color!,
          )
        : null;

    // The whole text is laid out once, so the kerning is kept in the offsets.
    final whole = layout(text, ts);
    final glyphs = <Glyph>[];
    var start = 0;
    for (final ch in text.characters) {
      final end = start + ch.length;
      final boxes = whole.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      start = end;
      if (boxes.isEmpty || ch.trim().isEmpty) continue;
      final box = boxes.first;
      glyphs.add(
        Glyph(
          layout(ch, ts),
          haloStyle == null ? null : layout(ch, haloStyle),
          box.left,
          box.right - box.left,
        ),
      );
    }
    final run = GlyphRun(glyphs, whole.width, whole.height);
    whole.dispose();
    return run;
  }

  /// The widget of [label], to be positioned (and turned) by the caller to
  /// the resolved size.
  Widget content(Label label, LabelStyle? style) => switch (label) {
    TextLabel(:final text) => _text(text, style),
    WidgetLabel(:final widget, :final ignorePointer) => IgnorePointer(
      ignoring: ignorePointer,
      child: widget,
    ),
  };

  Widget _text(String text, LabelStyle? style) {
    if (text.isEmpty) return const SizedBox.shrink();
    final h = style?.halo;
    final ts = (_baseStyle ?? const TextStyle()).merge(style?.textStyle);

    var labelWidget = _textWidget(text, ts);
    if (h != null && h.width != null && h.color != null) {
      labelWidget = Stack(
        children: [
          _textWidget(
            text,
            ts.copyWith(
              foreground: Paint()
                ..style = .stroke
                ..strokeWidth = h.width!
                ..color = h.color!,
            ),
          ),
          labelWidget,
        ],
      );
    }

    return IgnorePointer(
      child: OverflowBox(
        minWidth: 0,
        maxWidth: .infinity,
        minHeight: 0,
        maxHeight: .infinity,
        child: DecoratedBox(
          decoration: style?.decoration ?? const BoxDecoration(),
          child: Padding(
            padding: style?.padding ?? .zero,
            child: labelWidget,
          ),
        ),
      ),
    );
  }

  Widget _textWidget(String label, TextStyle style) => Text(
    label,
    style: style,
    maxLines: 1,
    softWrap: false,
    overflow: .visible,
    textScaler: .noScaling,
    textHeightBehavior: _heightBehavior,
    textWidthBasis: .longestLine,
  );
}
