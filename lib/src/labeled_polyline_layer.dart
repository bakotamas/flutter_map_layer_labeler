import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'label_controller.dart';
import 'label_fader.dart';
import 'label_geometry.dart';
import 'label_renderer.dart';
import 'labeled_marker.dart';
import 'screen_path.dart';
import 'shape_geometry.dart';

/// Higher returned value means the label is placed earlier (wins conflicts).
typedef PolylinePriorityCallback<T> = double Function(
  LabeledPolyline<T> polyline,
);

/// A callback that returns the [LabelStyle] for a given polyline.
///
/// Returns null to use the default [LabeledPolylineLayer.labelStyle].
typedef PolylineLabelStyleCallback<T> = LabelStyle? Function(
  LabeledPolyline<T> polyline,
);

/// Where the label of a polyline is put relative to the line.
enum LabelAlignment {
  /// The label is centered on the line.
  onLine,

  /// The label is above the line: on the side of the line where the top of
  /// the (upright) text is.
  ///
  /// If the labels are not rotated (see [LabeledPolylineLayer.rotateLabels]),
  /// it is the upper side of the screen.
  aboveLine,

  /// The label is below the line: on the side of the line where the bottom of
  /// the (upright) text is.
  ///
  /// If the labels are not rotated (see [LabeledPolylineLayer.rotateLabels]),
  /// it is the lower side of the screen.
  belowLine,
}

/// The number of candidate keys reserved for the labels of one polyline.
///
/// The key of the candidate of the repeat `r` of the polyline `i` is
/// `i * _anchorStride + r`.
const _anchorStride = 64;

/// Wrapper class that associates a polyline with a label and additional data.
class LabeledPolyline<T> {
  const new _({
    required this.polyline,
    required this.label,
    required this.data,
  });

  /// Creates a labeled polyline with the specified polyline, text label, and optional additional data.
  factory({
    required Polyline polyline,
    required String labelText,
    T? data,
  }) => LabeledPolyline._(
    polyline: polyline,
    label: TextLabel(labelText),
    data: data,
  );

  /// Creates a labeled polyline with the specified polyline, sized widget label, and optional additional data.
  factory widget({
    required Polyline polyline,
    required Widget labelWidget,
    required Size labelSize,
    T? data,
    bool ignorePointer = false,
    double spacing = 2,
  }) => LabeledPolyline._(
    polyline: polyline,
    label: WidgetLabel(
      labelWidget,
      labelSize,
      ignorePointer: ignorePointer,
      spacing: spacing,
    ),
    data: data,
  );

  /// The polyline associated with this labeled polyline.
  ///
  /// Do not modify its points in place: the layer remembers their bounds.
  final Polyline polyline;

  /// The label associated with the polyline.
  ///
  /// If null, the polyline has no label.
  final Label? label;

  /// Additional data for the priority and style callbacks.
  final T? data;
}

/// A layer that displays polylines with labels that follow the lines,
/// and handles label collisions together with the other labeled layers.
///
/// The labels are put on the straightest parts of the lines. Their places
/// belong to the whole line, not to its visible part, so the labels do not
/// move along the line while the map is panned.
///
/// Polylines are not obstacles: a label can lie on top of any polyline, but
/// it never overlaps the markers and the other labels.
class LabeledPolylineLayer<T> extends StatefulWidget {
  /// Creates a labeled polyline layer with the specified controller, polylines, and optional label settings.
  const new({
    required this.controller,
    required this.polylines,
    super.key,
    this.displayLabels = true,
    this.priority,
    this.labelStyle = const LabelStyle(
      TextStyle(fontSize: 12, color: Color(0xFF000000)),
    ),
    this.labelStyleCallback,
    this.labelAlignment = .onLine,
    this.labelRepeat,
    this.maxLabelsPerLine = 8,
    this.rotateLabels = true,
    this.followLine = true,
    this.cornerRadius = 2,
    this.hideLabelIfLongerThanLine = true,
    this.simplificationTolerance = 10,
    this.simplificationMinPoints = 300,
    this.labelFadeDuration = const Duration(milliseconds: 200),
  }) : assert(labelRepeat == null || labelRepeat > 0),
       assert(maxLabelsPerLine >= 1 && maxLabelsPerLine <= _anchorStride),
       assert(cornerRadius >= 0);

  /// The controller that manages label collisions for this layer.
  final LabelCollisionController controller;

  /// If false, this is a plain [PolylineLayer]: no labels, and the layer does
  /// not take part in the collision detection.
  final bool displayLabels;

  /// The list of labeled polylines to display in this layer.
  ///
  /// Do not modify the list in place: pass a new list when the content changes.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise labels may be misplaced or missing until the next threshold update.
  final List<LabeledPolyline<T>> polylines;

  /// The function that determines the priority of each label.
  /// Higher values mean the label is placed earlier and wins conflicts.
  ///
  /// The first label of every polyline is placed before any repeated label.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final PolylinePriorityCallback<T>? priority;

  /// The default style of the [TextLabel] type labels.
  ///
  /// Used for every text label unless overridden by [labelStyleCallback].
  /// With [LabelStyle.hidden] no text label is drawn unless the callback
  /// gives it a style.
  /// Has no effect on [WidgetLabel] type labels, except its (or the widget
  /// label's) spacing: it is the gap between the line and the label if
  /// [labelAlignment] is not [LabelAlignment.onLine].
  /// Its padding and decoration are ignored if the text follows the line
  /// (see [followLine]).
  final LabelStyle labelStyle;

  /// A callback that sets the [LabelStyle] of the text label of every polyline in the layer.
  ///
  /// If provided, this overrides the [labelStyle] for polylines where it returns a non-null value.
  /// Return [LabelStyle.hidden] to hide the label of a polyline.
  /// If the results of the function change, should call invalidate on the
  /// [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final PolylineLabelStyleCallback<T>? labelStyleCallback;

  /// Where the label is put relative to the line: on it, above it or below it.
  ///
  /// Above and below, the label is moved sideways from the line by the half
  /// of the stroke width of the line, the spacing of the label style, and
  /// the half of the label height.
  final LabelAlignment labelAlignment;

  /// The smallest distance between two labels of the same line, as a
  /// multiple of the longer side of the viewport.
  ///
  /// For example 0.6 means that a line is labeled at most once in every
  /// 0.6 viewport lengths. The longer side is used, so turning the device
  /// does not change the distance.
  ///
  /// If null, every line has only one label.
  ///
  /// The places of the repeated labels are nested: when the map is zoomed in,
  /// the existing labels stay, and new ones appear between them.
  final double? labelRepeat;

  /// The largest number of labels of a single line (see [labelRepeat]).
  final int maxLabelsPerLine;

  /// If true, the labels turn along the line (and are never upside down).
  /// If false, they are horizontal.
  final bool rotateLabels;

  /// If true (and [rotateLabels] is true), a text label is painted glyph by
  /// glyph along the geometry of the line, so it bends with the line.
  /// If false, the label is straight, turned to the direction of the line.
  ///
  /// Widget labels are always straight.
  final bool followLine;

  /// The radius of the curves that replace the corners of the line under a
  /// text that follows the line, as a multiple of the text height.
  ///
  /// The glyphs are placed along a smooth curve (quadratic Bézier curves
  /// at the corners, straight parts between them) instead of the broken
  /// line, so the text does not break at the corners. The curve never
  /// leaves the corner, and the radius is limited to the half of the shorter
  /// segment next to the corner. 0 turns the rounding off.
  ///
  /// Only the part of the line under the label is rounded. The label places
  /// are still chosen on the original line, so the rounding does not move them
  /// along the line while the map is zoomed.
  final double cornerRadius;

  /// If true, the label is not shown when it is longer than the line.
  final bool hideLabelIfLongerThanLine;

  /// The tolerance (in screen pixels) of the Douglas–Peucker simplification
  /// of the lines, used only to place the labels. The lines themselves are
  /// drawn unchanged. 0 turns the simplification off.
  ///
  /// A line is simplified at a recalculation if more than
  /// [simplificationMinPoints] of its points are inside the viewport.
  /// The whole line is simplified, so the positions stay consistent.
  final double simplificationTolerance;

  /// The number of points of a line inside the viewport above which the line
  /// is simplified for the label placement (see [simplificationTolerance]).
  final int simplificationMinPoints;

  /// The duration of the fade when a label appears or disappears.
  ///
  /// [Duration.zero] turns the animation off.
  final Duration labelFadeDuration;

  @override
  State<LabeledPolylineLayer<T>> createState() =>
      _LabeledPolylineLayerState<T>();
}

/// What the last recalculation resolved for a polyline.
class _LineLabel {
  const new(
    this.res,
    this.run,
    this.bounds,
    this.points,
    this.gap,
    this.fractions,
  );

  final ResolvedLabel res;

  /// The points the label positions were calculated on (possibly simplified).
  /// The painting uses the same points, so a label does not shift.
  final List<LatLng> points;

  /// The glyphs, if the text follows the line.
  final GlyphRun? run;

  final LatLngBounds bounds;

  /// The distance between the line center and the edge of the label that
  /// faces the line, if the label is above or below the line.
  final double gap;

  /// The places of the labels as fractions of the line length:
  /// `fractions[repeat][slot]`. A repeat without a usable place has an empty list.
  final List<List<double>> fractions;
}

/// A simplified line, reused until the zoom changes noticeably.
class _Simplified {
  const new(this.zoom, this.points);

  final double zoom;
  final List<LatLng> points;
}

/// Whether more than [limit] of [points] are inside [rect].
bool _moreInside(List<Offset> points, Rect rect, int limit) {
  var n = 0;
  for (final p in points) {
    if (rect.contains(p) && ++n > limit) return true;
  }
  return false;
}

/// The distance along a line of the center of a label of [width], put at
/// [fraction] of a line of [length]. The label stays on the line.
double _centerDistance(double fraction, double length, double width) {
  if (length <= width) return length / 2;
  return (length * fraction.clamp(0.0, 1.0)).clamp(
    width / 2,
    length - width / 2,
  );
}

/// Whether text along [chord] reads left to right without being upside down.
bool _isUpright(Offset chord) {
  final a = chord.direction;
  return a > -math.pi / 2 && a <= math.pi / 2;
}

/// The (upright) direction of the line under a label of [width] centered at [c].
double _lineAngle(ScreenPath path, double c, double width) {
  final chord = path.pointAt(c + width / 2) - path.pointAt(c - width / 2);
  return LabelGeometry.uprightAngle(chord.direction);
}

/// How far the center of a label is moved sideways from the line:
/// positive above the line, negative below it.
double _shift(LabelAlignment alignment, double halfHeight, double gap) =>
    switch (alignment) {
      .onLine => 0.0,
      .aboveLine => halfHeight + gap,
      .belowLine => -(halfHeight + gap),
    };

/// The center and the angle of a straight label centered at [c] on [path].
///
/// Above or below the line the label is moved along the normal of the line
/// far enough not to touch it, also if the label is not turned with the line.
({Offset center, double angle}) _straightPlacement(
  ScreenPath path,
  double c,
  Size size,
  bool rotate,
  LabelAlignment alignment,
  double gap,
) {
  final lineAngle = _lineAngle(path, c, size.width);
  final angle = rotate ? lineAngle : 0.0;
  var center = path.pointAt(c);
  if (alignment != LabelAlignment.onLine) {
    // Half of the extent of the (turned) label across the line.
    final delta = angle - lineAngle;
    final reach =
        size.width / 2 * math.sin(delta).abs() +
        size.height / 2 * math.cos(delta).abs();
    final side = alignment == LabelAlignment.aboveLine ? 1.0 : -1.0;
    // The normal on the upper side of the (upright) line.
    final normal = Offset(math.sin(lineAngle), -math.cos(lineAngle));
    center += normal * (side * (gap + reach));
  }
  return (center: center, angle: angle);
}

/// The path of a label that follows the line: the part of [path] under a
/// label of [width] centered at [c], with the corners rounded by [radius],
/// in reading direction and moved sideways by [shift] (see [_shift]).
///
/// Only a part a bit longer than the label is rounded, so the cost does not
/// depend on the length of the line. The extra length (two radii on both
/// sides) keeps the ends of the cut, where the rounding is not exact, out of
/// the label.
List<Offset> _curvedPart(
  ScreenPath path,
  double c,
  double width,
  double shift,
  double radius,
) {
  var part = path.slice(c - width / 2, c + width / 2);
  if (radius > 0) {
    final margin = width / 2 + 2 * radius;
    final local = ScreenPath(path.slice(c - margin, c + margin))
        .rounded(radius);
    // The rounded part is symmetric around the label, so its middle is the
    // center of the label.
    final mid = local.length / 2;
    part = local.slice(mid - width / 2, mid + width / 2);
  }
  if (!_isUpright(part.last - part.first)) part = part.reversed.toList();
  return ScreenPath.offset(part, shift);
}

/// The half of the width of the drawn line in pixels (without the border).
double _halfStroke(Polyline polyline) =>
    polyline.useStrokeWidthInMeter ? 0.0 : polyline.strokeWidth / 2;

/// The range of distances along [path] where it is inside [area], or null if
/// it never is.
(double, double)? _visibleRange(ScreenPath path, Rect area) {
  var from = double.infinity, to = double.negativeInfinity;
  final p = path.points;
  for (var i = 0; i + 1 < p.length; i++) {
    final t = ShapeGeometry.clipSegment(p[i], p[i + 1], area);
    if (t == null) continue;
    final segment = path.cumulative[i + 1] - path.cumulative[i];
    from = math.min(from, path.cumulative[i] + segment * t.$1);
    to = math.max(to, path.cumulative[i] + segment * t.$2);
  }
  return from > to ? null : (from, to);
}

/// The anchors of the labels of a line of [length]: `(tier, fraction)` pairs,
/// the more important ones first.
///
/// Without [minGap] the only anchor is the middle of the line. Otherwise the
/// anchors are the nested fractions 1/2, 1/4 and 3/4, 1/8 and 3/8 and 5/8 and
/// 7/8 ... of the line, level by level (the tier is the level), as long as
/// neighbors are at least [minGap] apart and there are at most [max] of them.
/// The anchor at an index is always the same fraction, so the repeats keep
/// their identity when the number of levels changes.
List<(int, double)> _anchors(double length, double? minGap, int max) {
  if (minGap == null || max <= 1 || length < 2 * minGap) {
    return const [(0, .5)];
  }
  final out = <(int, double)>[];
  for (var l = 1; length / (1 << l) >= minGap; l++) {
    final n = 1 << (l - 1);
    if (out.length + n > max) break;
    for (var k = 0; k < n; k++) {
      out.add((l - 1, (2 * k + 1) / (1 << l)));
    }
  }
  return out;
}

/// The places (as distances along [path]) a label of [width] may be put near
/// [ideal], the best first.
///
/// The places that belong to the anchor ([ideal] and [reach]) are tried on a
/// fixed grid of the line, which does not depend on the viewport, so a pan
/// does not change what is compared. Only the places that touch the [visible]
/// range (the solved area) are usable. The result is empty if there is none.
///
/// With [straight] the places are compared by how much the line under the
/// label bends, plus a small cost for the distance from the preferred place of
/// a new label: the anchor, or, if [single] (one label on the line) and the
/// anchor is off the screen, the middle of the part of the line that is
/// [onScreen]. Places that are on the screen are always preferred.
/// At most [_slotsPerLabel] places, half a label width apart, are returned.
///
/// The [previous] place (the one the last recalculation chose) stays the
/// first one, as long as it is usable and on the screen (or nothing is), and
/// it is not clearly more bent than the best place. Without this a label
/// would jump to an equally good place at every recalculation of a pan.
List<double> _centersAround(
  ScreenPath path,
  double ideal,
  double width,
  double reach,
  (double, double) visible,
  (double, double)? onScreen,
  double? previous, {
  required bool single,
}) {
  final length = path.length;
  if (length <= width) return [length / 2];
  // The places that belong to the anchor, and the ones usable now.
  final minC = math.max(width / 2, ideal - reach);
  final maxC = math.min(length - width / 2, ideal + reach);
  final lo = math.max(minC, visible.$1 - width / 2);
  final hi = math.min(maxC, visible.$2 + width / 2);
  if (lo > hi) return const [];

  bool onScreenAt(double c) =>
      onScreen != null &&
      c + width / 2 >= onScreen.$1 &&
      c - width / 2 <= onScreen.$2;

  var focus = ideal;
  if (single && onScreen != null && !onScreenAt(ideal)) {
    focus = (onScreen.$1 + onScreen.$2) / 2;
  }
  final keep = previous != null && previous >= lo && previous <= hi
      ? previous
      : null;

  if (ideal >= lo && ideal <= hi) return [ideal];
  return [keep ?? focus.clamp(lo, hi)];
}

class _LabeledPolylineLayerState<T> extends State<LabeledPolylineLayer<T>>
    implements LabelLayerHost {
  final _renderer = LabelRenderer();
  final _fader = LabelFader();

  /// The labeled polylines of the last recalculation: polyline index -> what was resolved.
  final _entries = <int, _LineLabel>{};

  /// The geographic bounds of the polylines.
  final _bounds = Expando<LatLngBounds>();

  /// The simplified polylines, for the current tolerance.
  var _simplified = Expando<_Simplified>();

  /// The keys of the labels of the polylines (one per repeat), the same
  /// objects for the whole life of a polyline, so the fade can follow a label
  /// over the recalculations.
  final _partKeys = Expando<List<Object>>();

  List<LabeledPolyline<T>>? _source;
  List<Polyline> _lines = const [];

  /// The plain polylines, with the same list instance until the labeled list changes.
  List<Polyline> get _plainLines {
    if (!identical(_source, widget.polylines)) {
      _source = widget.polylines;
      _lines = [for (final lp in widget.polylines) lp.polyline];
    }
    return _lines;
  }

  /// Whether the text labels of this layer follow the geometry of the lines.
  bool get _curved => widget.followLine && widget.rotateLabels;

  @override
  void initState() {
    super.initState();
    _fader.duration = widget.labelFadeDuration;
    if (widget.displayLabels) widget.controller.attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStyle();
  }

  @override
  void didUpdateWidget(LabeledPolylineLayer<T> old) {
    super.didUpdateWidget(old);
    _fader.duration = widget.labelFadeDuration;
    if (old.controller != widget.controller) {
      if (old.displayLabels) old.controller.detach(this);
      if (widget.displayLabels) widget.controller.attach(this);
    } else if (old.displayLabels != widget.displayLabels) {
      widget.displayLabels
          ? widget.controller.attach(this)
          : widget.controller.detach(this);
    }
    if (old.labelStyle != widget.labelStyle) {
      _renderer.clearCache();
      if (widget.displayLabels) widget.controller.invalidate();
    }
    if (old.labelAlignment != widget.labelAlignment ||
        old.labelRepeat != widget.labelRepeat ||
        old.maxLabelsPerLine != widget.maxLabelsPerLine ||
        old.rotateLabels != widget.rotateLabels ||
        old.followLine != widget.followLine ||
        old.cornerRadius != widget.cornerRadius ||
        old.hideLabelIfLongerThanLine != widget.hideLabelIfLongerThanLine) {
      if (widget.displayLabels) widget.controller.invalidate();
    }
    if (old.simplificationTolerance != widget.simplificationTolerance) {
      _simplified = Expando<_Simplified>();
      if (widget.displayLabels) widget.controller.invalidate();
    }
    if (old.simplificationMinPoints != widget.simplificationMinPoints) {
      if (widget.displayLabels) widget.controller.invalidate();
    }
    _updateStyle();
  }

  @override
  void dispose() {
    if (widget.displayLabels) widget.controller.detach(this);
    _fader.dispose();
    _renderer.dispose();
    super.dispose();
  }

  /// Updates the base label style if changed.
  void _updateStyle() {
    if (_renderer.updateBaseStyle(context) && widget.displayLabels) {
      widget.controller.invalidate();
    }
  }

  LabelStyle _getStyleFor(LabeledPolyline<T> lp) {
    return widget.labelStyleCallback?.call(lp) ?? widget.labelStyle;
  }

  /// The key of the label of the repeat [part] of [lp].
  Object _keyFor(LabeledPolyline<T> lp, int part) {
    final keys = _partKeys[lp] ??= <Object>[];
    while (keys.length <= part) {
      keys.add(Object());
    }
    return keys[part];
  }

  /// The places chosen by the last recalculation, as fractions of the line
  /// length: candidate key -> fraction.
  Map<int, double> _lastChosen() {
    final out = <int, double>{};
    final items = widget.polylines;
    widget.controller.placementsOf(this).forEach((key, slot) {
      final i = key ~/ _anchorStride, r = key % _anchorStride;
      final e = _entries[i];
      if (e == null || i >= items.length || e.res.source != items[i]) return;
      if (r < e.fractions.length && slot < e.fractions[r].length) {
        out[key] = e.fractions[r][slot];
      }
    });
    return out;
  }

  @override
  bool labelsVisibleAt(double zoom) => true;

  @override
  List<LabelCandidate> collect(MapCamera camera, Rect area) {
    final last = _lastChosen();
    _entries.clear();
    final out = <LabelCandidate>[];
    final items = widget.polylines;
    final repeat = widget.labelRepeat;
    final minGap = repeat == null
        ? null
        : repeat * math.max(camera.size.width, camera.size.height);
    for (var i = 0; i < items.length; i++) {
      final lp = items[i];
      final points = lp.polyline.points;
      // Polylines are not obstacles, so only the labeled ones are candidates.
      final label = lp.label;
      if (label == null || points.length < 2) continue;
      final bounds = _bounds[lp.polyline] ??= LatLngBounds.fromPoints(points);
      // A label is on the line, so a line outside the area has no label there.
      if (!bounds.screenRect(camera).overlaps(area)) continue;

      final res = _renderer.resolve(context, lp, label, () => _getStyleFor(lp));
      if (res.size.isEmpty) continue;

      // The positions belong to the whole line, not to its visible part.
      final (usedPoints, path) = _pathOf(camera, lp.polyline);
      if (path.length <= 0) continue;
      if (widget.hideLabelIfLongerThanLine && path.length < res.size.width) {
        continue;
      }
      final visible = _visibleRange(path, area);
      if (visible == null) continue;
      final onScreen = _visibleRange(path, Offset.zero & camera.size);

      final run = _curved && label is TextLabel
          ? _renderer.glyphRun(context, label.text, res.style!)
          : null;
      final gap = _halfStroke(lp.polyline) + res.spacing;

      final anchors = _anchors(path.length, minGap, widget.maxLabelsPerLine);
      // A single label may look for a straight part anywhere on the line,
      // repeated labels only near their own anchors.
      final reach = anchors.length == 1
          ? path.length / 2
          : path.length * .4 / (1 << (anchors.last.$1 + 1));

      final fractions = <List<double>>[];
      final candidates = <LabelCandidate>[];
      for (var r = 0; r < anchors.length; r++) {
        final (tier, fraction) = anchors[r];
        final key = i * _anchorStride + r;
        final ideal = _centerDistance(fraction, path.length, res.size.width);
        final before = last[key];
        final centers = _centersAround(
          path,
          ideal,
          res.size.width,
          reach,
          visible,
          onScreen,
          before == null ? null : before * path.length,
          single: anchors.length == 1,
        );
        fractions.add([for (final c in centers) c / path.length]);
        if (centers.isEmpty) continue;
        candidates.add(
          LabelCandidate(
            host: this,
            index: key,
            tier: tier,
            priority: widget.priority?.call(lp) ?? 0,
            slots: [
              for (final c in centers)
                _slotAt(path, c, res.size, run, area, gap),
            ],
          ),
        );
      }
      if (candidates.isEmpty) continue;
      _entries[i] = _LineLabel(res, run, bounds, usedPoints, gap, fractions);
      out.addAll(candidates);
    }
    return out;
  }

  /// The points and the screen path to place the labels of [polyline] on.
  ///
  /// If more than [LabeledPolylineLayer.simplificationMinPoints] points are
  /// inside the viewport, the whole line is simplified, otherwise it is used
  /// as it is. The result is kept in the layer for the painting.
  (List<LatLng>, ScreenPath) _pathOf(MapCamera camera, Polyline polyline) {
    final points = polyline.points;
    final tolerance = widget.simplificationTolerance;

    // A line that was simplified stays simplified until the zoom changes
    // noticeably. Otherwise a pan could switch it between the original and the
    // simplified line (as points enter the viewport), which have different
    // lengths, so the labels would move.
    final cached = tolerance <= 0 ? null : _simplified[polyline];
    if (cached != null && (cached.zoom - camera.zoom).abs() < .25) {
      return (
        cached.points,
        ScreenPath([
          for (final p in cached.points) camera.latLngToScreenOffset(p),
        ]),
      );
    }

    final screen = [for (final p in points) camera.latLngToScreenOffset(p)];
    if (tolerance <= 0 ||
        !_moreInside(
          screen,
          Offset.zero & camera.size,
          widget.simplificationMinPoints,
        )) {
      return (points, ScreenPath(screen));
    }
    final keep = ScreenPath.simplify(screen, tolerance);
    final simplified = [for (final i in keep) points[i]];
    _simplified[polyline] = _Simplified(camera.zoom, simplified);
    return (simplified, ScreenPath([for (final i in keep) screen[i]]));
  }

  /// The screen rects of the label centered at the distance [c] of the line.
  ///
  /// A label that follows the line is covered by several small rects along
  /// the line, so a bend does not block the empty space around it.
  LabelSlot _slotAt(
    ScreenPath path,
    double c,
    Size size,
    GlyphRun? run,
    Rect area,
    double gap,
  ) {
    final rects = <Rect>[];
    if (run != null) {
      final shift = _shift(widget.labelAlignment, run.height / 2, gap);
      final part = ScreenPath(
        _curvedPart(
          path,
          c,
          size.width,
          shift,
          widget.cornerRadius * run.height,
        ),
      );
      final length = part.length;
      final n = math.max(1, (length / math.max(size.height * 1.5, 12)).ceil());
      for (var k = 0; k < n; k++) {
        final sub = part.slice(length * k / n, length * (k + 1) / n);
        rects.add(ShapeGeometry.boundsOf(sub).inflate(size.height / 2));
      }
    } else {
      final p = _straightPlacement(
        path,
        c,
        size,
        widget.rotateLabels,
        widget.labelAlignment,
        gap,
      );
      final b = LabelGeometry.rotatedBounds(size, p.angle);
      rects.add(
        Rect.fromCenter(center: p.center, width: b.width, height: b.height),
      );
    }
    // A place outside of the solved area is not worth solving.
    return rects.any(area.overlaps) ? LabelSlot(rects) : LabelSlot.unusable;
  }

  /// Where the label is for a camera: [fraction] of the line, measured on the
  /// current screen geometry, so the label stays at the same place of the line
  /// while the map moves or zooms.
  LabelPlacer _placer(
    Label label,
    _LineLabel e,
    double fraction,
    bool rotate,
    LabelAlignment alignment,
    double cornerRadius,
  ) => (camera) {
    final viewport = Offset.zero & camera.size;
    if (!e.bounds.screenRect(camera).overlaps(viewport)) return null;
    final path = ScreenPath([
      for (final p in e.points) camera.latLngToScreenOffset(p),
    ]);
    if (path.length <= 0) return null;

    final size = e.res.size;
    final c = _centerDistance(fraction, path.length, size.width);

    final run = e.run;
    if (run != null) {
      final shift = _shift(alignment, run.height / 2, e.gap);
      final part = _curvedPart(
        path,
        c,
        size.width,
        shift,
        cornerRadius * run.height,
      );
      final r = ShapeGeometry.boundsOf(part).inflate(size.height / 2 + 2);
      if (!r.overlaps(viewport)) return null;
      return PlacedLabel(
        r,
        IgnorePointer(
          child: CustomPaint(
            size: r.size,
            painter: PathTextPainter(
              run,
              ScreenPath([for (final p in part) p - r.topLeft]),
              (size.width - run.width) / 2,
            ),
          ),
        ),
      );
    }

    final p = _straightPlacement(path, c, size, rotate, alignment, e.gap);
    final b = LabelGeometry.rotatedBounds(size, p.angle);
    final visible = Rect.fromCenter(
      center: p.center,
      width: b.width,
      height: b.height,
    );
    if (!visible.overlaps(viewport)) return null;
    return PlacedLabel(
      Rect.fromCenter(
        center: p.center,
        width: size.width,
        height: size.height,
      ),
      _renderer.content(label, e.res.style),
      angle: p.angle,
    );
  };

  /// Labels live in their own screen-space overlay above the lines.
  /// A label follows its place on the line while the map moves, without a new calculation.
  Widget _buildLabels(BuildContext context) {
    final camera = MapCamera.of(context);
    widget.controller.onCamera(camera);

    final items = widget.polylines;
    final alignment = widget.labelAlignment;
    final placed = LinkedHashMap<Object, LabelPlacer>.identity();
    widget.controller.placementsOf(this).forEach((key, slot) {
      final i = key ~/ _anchorStride, r = key % _anchorStride;
      final e = _entries[i];
      if (e == null ||
          i >= items.length ||
          e.res.source != items[i] ||
          r >= e.fractions.length ||
          slot >= e.fractions[r].length) {
        return;
      }
      final lp = items[i];
      final label = lp.label;
      if (label == null) return;
      placed[_keyFor(lp, r)] = _placer(
        label,
        e,
        e.fractions[r][slot],
        widget.rotateLabels,
        alignment,
        widget.cornerRadius,
      );
    });
    return Stack(
      clipBehavior: .hardEdge,
      children: _fader.build(camera, placed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = PolylineLayer(polylines: _plainLines);
    if (!widget.displayLabels) return lines;
    return Stack(
      fit: .expand,
      children: [
        lines,
        ListenableBuilder(
          listenable: Listenable.merge([widget.controller, _fader]),
          builder: (_, _) {
            // Rebuild via MapCamera dependency only affects the inner Builder.
            return Builder(builder: _buildLabels);
          },
        ),
      ],
    );
  }
}
