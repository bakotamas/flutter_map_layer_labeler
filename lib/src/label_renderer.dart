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

/// A copy of [span] without its [WidgetSpan]s (and other placeholders),
/// with its texts mapped by [text] and its styles by [style].
TextSpan _mapSpan(
  TextSpan span, {
  String Function(String text)? text,
  TextStyle? Function(TextStyle? style)? style,
}) => TextSpan(
  text: span.text == null || text == null ? span.text : text(span.text!),
  style: style == null ? span.style : style(span.style),
  locale: span.locale,
  spellOut: span.spellOut,
  children: span.children == null
      ? null
      : [
          for (final c in span.children!)
            if (c is TextSpan) _mapSpan(c, text: text, style: style),
        ],
);

/// The line breaks of a text, to paint it in one line.
final _lineBreak = RegExp(r'\r\n|[\n\r  ]');

/// The text alignment of the lines of a label whose [alignment] edge faces its item.
TextAlign _textAlign(Alignment alignment) => alignment.x < 0
    ? TextAlign.left
    : alignment.x > 0
    ? TextAlign.right
    : TextAlign.center;

/// Measures and builds the labels for the labeled layers.
class LabelRenderer {
  /// Constant to ensure the same text height behavior is used regardless different font settings.
  static const _heightBehavior = TextHeightBehavior();

  /// A cache for the measured sizes of label texts by their style and
  /// whether they are painted in one line.
  final _sizeCache = <(TextSpan, LabelStyle, bool), Size>{};

  /// A cache for the glyphs of label texts by their style.
  final _runCache = <(TextSpan, LabelStyle), GlyphRun>{};

  /// A cache for the widgets of label texts by their style and alignment.
  ///
  /// A label gets the same widget instance at every build, so the framework
  /// does not build (and lay out) its text again while the map moves.
  final _textCache = <(TextSpan, LabelStyle?, TextAlign), Widget>{};

  /// A cache for the widgets of widget labels by their alignment, for the same
  /// reason. Weak, so the labels of a replaced item list are released.
  final _widgetCache = Expando<Map<Alignment, Widget>>();

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

  /// Forgets the measured sizes, glyphs and text widgets.
  ///
  /// The glyph painters are not disposed here: labels that are fading out may
  /// still paint them. They are released with the renderer.
  void clearCache() {
    _sizeCache.clear();
    _runCache.clear();
    _textCache.clear();
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
  /// With [singleLine] a text label is measured in one line, as [glyphRun]
  /// paints it.
  ResolvedLabel resolve(
    BuildContext context,
    Object source,
    Label? label,
    LabelStyle Function() styleFor, {
    bool singleLine = false,
  }) => switch (label) {
    null => ResolvedLabel(source, Size.zero, 0),
    TextLabel(:final text) when text.isEmpty => ResolvedLabel(
      source,
      Size.zero,
      0,
    ),
    TextLabel(:final span) => _resolveText(
      context,
      source,
      span,
      styleFor(),
      singleLine,
    ),
    WidgetLabel(:final size, :final spacing) => ResolvedLabel(
      source,
      size,
      spacing,
    ),
  };

  ResolvedLabel _resolveText(
    BuildContext context,
    Object source,
    TextSpan span,
    LabelStyle style,
    bool singleLine,
  ) {
    // A style without a text style hides the label: it gets a zero size, so
    // the layers treat it as an item without a label.
    if (style.isHidden) return ResolvedLabel(source, Size.zero, 0);
    return ResolvedLabel(
      source,
      _measureText(context, span, style, singleLine),
      style.spacing,
      style,
    );
  }

  Size _measureText(
    BuildContext context,
    TextSpan span,
    LabelStyle style,
    bool singleLine,
  ) {
    final key = (span, style, singleLine);
    return _sizeCache.putIfAbsent(key, () {
      final ts = (_baseStyle ?? const TextStyle()).merge(style.textStyle);
      final content = singleLine ? _singleLine(span) : _mapSpan(span);
      final tp = TextPainter(
        text: TextSpan(style: ts, children: [content]),
        textDirection: Directionality.maybeOf(context) ?? .ltr,
        textScaler: .noScaling,
        textHeightBehavior: _heightBehavior,
        textWidthBasis: .longestLine,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: singleLine ? 1 : null,
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

  /// [span] with its line breaks replaced by spaces.
  TextSpan _singleLine(TextSpan span) =>
      _mapSpan(span, text: (t) => t.replaceAll(_lineBreak, ' '));

  /// The stroke that paints the [halo], or null if it has none.
  Paint? _haloPaint(TextLabelHalo halo, {StrokeJoin join = .miter}) =>
      halo.width != null && halo.color != null
      ? (Paint()
          ..style = .stroke
          ..strokeJoin = join
          ..strokeWidth = halo.width!
          ..color = halo.color!)
      : null;

  /// The glyphs of [span], to paint it along a curve with [PathTextPainter].
  ///
  /// Left-to-right text is assumed. The text is painted in one line: its line
  /// breaks are replaced by spaces. The padding and the decoration of the
  /// style are not used for curved text.
  GlyphRun glyphRun(BuildContext context, TextSpan span, LabelStyle style) =>
      _runCache.putIfAbsent((
        span,
        style,
      ), () => _buildRun(context, span, style));

  GlyphRun _buildRun(BuildContext context, TextSpan span, LabelStyle style) {
    final ts = (_baseStyle ?? const TextStyle()).merge(style.textStyle);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final locale = Localizations.maybeLocaleOf(context);

    TextPainter layout(TextSpan s) => TextPainter(
      text: s,
      textDirection: direction,
      textScaler: TextScaler.noScaling,
      textHeightBehavior: _heightBehavior,
      locale: locale,
      maxLines: 1,
    )..layout();

    final stroke = _haloPaint(style.halo, join: StrokeJoin.round);
    final line = _singleLine(span);

    // The whole text is laid out once, so the kerning is kept in the offsets.
    final whole = layout(TextSpan(style: ts, children: [line]));
    final glyphs = <Glyph>[];
    var start = 0;
    // Every glyph gets the style of its own span, merged onto the styles of
    // the spans above it.
    void walk(TextSpan s, TextStyle parent) {
      final st = parent.merge(s.style);
      for (final ch in (s.text ?? '').characters) {
        final end = start + ch.length;
        final boxes = whole.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        start = end;
        if (boxes.isEmpty || ch.trim().isEmpty) continue;
        final box = boxes.first;
        glyphs.add(
          Glyph(
            layout(TextSpan(text: ch, style: st)),
            stroke == null
                ? null
                : layout(
                    TextSpan(text: ch, style: st.copyWith(foreground: stroke)),
                  ),
            box.left,
            box.right - box.left,
          ),
        );
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        // Placeholders were removed by _singleLine.
        walk(c as TextSpan, st);
      }
    }

    walk(line, ts);
    final run = GlyphRun(glyphs, whole.width, whole.height);
    whole.dispose();
    return run;
  }

  /// The widget of [label], to be positioned (and turned) by the caller to
  /// the resolved size.
  ///
  /// [alignment] is the edge of the label that faces its item: the lines of a
  /// text label are aligned to it, and a widget label gets it in its builder.
  Widget content(Label label, LabelStyle? style, Alignment alignment) =>
      switch (label) {
        TextLabel(:final span) => _textCache.putIfAbsent((
          span,
          style,
          _textAlign(alignment),
        ), () => _text(span, style, _textAlign(alignment))),
        WidgetLabel() => (_widgetCache[label] ??= {}).putIfAbsent(
          alignment,
          () => IgnorePointer(
            ignoring: label.ignorePointer,
            child: Builder(
              builder: (context) => label.builder(context, alignment),
            ),
          ),
        ),
      };

  Widget _text(TextSpan span, LabelStyle? style, TextAlign align) {
    final content = _mapSpan(span);
    final ts = (_baseStyle ?? const TextStyle()).merge(style?.textStyle);

    var labelWidget = _textWidget(content, ts, align);
    final stroke = style == null ? null : _haloPaint(style.halo);
    if (stroke != null) {
      labelWidget = Stack(
        children: [
          _textWidget(
            // The halo replaces the colors of the spans too.
            _mapSpan(
              content,
              style: (s) => s?.copyWith(foreground: stroke),
            ),
            ts.copyWith(foreground: stroke),
            align,
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

  /// The lines are broken only at the line breaks of the text.
  Widget _textWidget(TextSpan span, TextStyle style, TextAlign align) =>
      Text.rich(
        span,
        style: style,
        textAlign: align,
        softWrap: false,
        overflow: .visible,
        textScaler: .noScaling,
        textHeightBehavior: _heightBehavior,
        textWidthBasis: .longestLine,
      );
}
