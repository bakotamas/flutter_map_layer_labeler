import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'label_controller.dart';
import 'label_geometry.dart';
import 'labeled_marker.dart';

/// Higher returned value means the label is placed earlier (wins conflicts).
typedef LabelPriorityCallback<T> = double Function(
  LabeledMarker<T> marker,
);

/// A callback that returns the [LabelStyle] for a given marker.
///
/// Returns null to use the default [LabeledMarkerLayer.labelStyle].
typedef LabelStyleCallback<T> = LabelStyle? Function(
  LabeledMarker<T> marker,
);

/// A layer that displays labeled markers and handles label collisions.
class LabeledMarkerLayer<T> extends StatefulWidget {
  /// Creates a labeled marker layer with the specified controller, markers, and optional label settings.
  const new({
    required this.controller,
    required this.markers,
    this.priority,
    this.labelStyleCallback,
    this.labelStyle = const LabelStyle(
      TextStyle(fontSize: 12, color: Color(0xFF000000)),
    ),
    this.sides = const [.right, .left, .bottom, .top],
    this.displayLabels = true,
    this.alwaysShowAllMarkers = true,
    this.alignment = .center,
    this.rotate = false,
    super.key,
  });

  /// The controller that manages label collisions for this layer.
  final LabelCollisionController controller;

  /// The list of labeled markers to display in this layer.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise labels may be misplaced or missing until the next threshold update.
  final List<LabeledMarker<T>> markers;

  /// The function that determines the priority of each label.
  /// Higher values mean the label is placed earlier and wins conflicts.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final LabelPriorityCallback<T>? priority;

  /// A callback that sets the [LabelStyle] of the text label of every marker in the layer.
  ///
  /// If provided, this overrides the [labelStyle] for markers where it returns a non-null value.
  /// If the results of the function change, should call invalidate on the
  /// [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final LabelStyleCallback<T>? labelStyleCallback;

  /// The default style of the [TextLabel] type labels.
  ///
  /// Used for every text label unless overridden by [labelStyleCallback].
  /// Has no effect on [WidgetLabel] type labels.
  final LabelStyle labelStyle;

  /// Possible positions for the label relative to its marker, tried in order.
  final List<LabelSide> sides;

  /// If false, this is a plain [MarkerLayer]: no labels, and the layer does
  /// not take part in the collision detection (its markers do not block
  /// the labels of other layers either).
  ///
  /// If you want to simply hide a label, but ensure its marker still participates
  /// in the collision detection, simply set the [LabeledMarker.label] to null.
  final bool displayLabels;

  /// If true, every marker is shown, and each one is an
  /// obstacle for the other labels.
  ///
  /// If false, the markers are processed by priority: a marker that overlaps a
  /// higher-priority marker or label is hidden together with its label.
  /// A marker whose label finds no free side is not hidden, only its label.
  /// With equal priorities the order of the list decides, so providing a [priority] is recommended.
  ///
  /// Markers of layers where this is true are never hidden, and they can block the
  /// labels of this layer (and markers if this is false for this layer).
  ///
  /// If the child widgets of the markers are stateful, giving them a key is good idea,
  /// because the hidden markers are removed from the layer.
  final bool alwaysShowAllMarkers;

  /// Alignment of each marker relative to its normal center at [Marker.point]
  ///
  /// For example, [Alignment.topCenter] will mean the entire marker widget is located above the [Marker.point].
  ///
  /// The center of rotation (anchor) will be opposite this.
  ///
  /// Defaults to [Alignment.center]. Overriden by [Marker.alignment] if set.
  final Alignment alignment;

  /// Whether to counter rotate markers to the map's rotation, to keep a fixed orientation.
  ///
  /// When true, markers will always appear upright and vertical from the user's perspective. Defaults to false. Overriden by [Marker.rotate].
  ///
  /// Note that this is not used to apply a custom rotation in degrees to the markers. Use a widget inside [Marker.child] to perform this.
  final bool rotate;

  @override
  State<LabeledMarkerLayer<T>> createState() => _LabeledMarkerLayerState<T>();
}

/// A marker candidate of the last recalculation and its resolved label.
///
/// The calculation and the painting must agree on the size and the spacing,
/// so they are resolved once per recalculation and reused until the next one.
/// Markers without a non-empty label have a zero sized one.
class _Resolved {
  const new(this.marker, this.size, this.spacing, [this.style]);

  /// The marker this was resolved for (to detect a changed marker list).
  final LabeledMarker marker;

  /// The size of the label.
  final Size size;

  /// The spacing between the label and its marker.
  final double spacing;

  /// The style of the label, only for [TextLabel] type labels.
  final LabelStyle? style;
}

class _LabeledMarkerLayerState<T> extends State<LabeledMarkerLayer<T>>
    implements LabelLayerHost {
  /// Constant to ensure the same text height behavior is used regardless different font settings.
  static const _heightBehavior = TextHeightBehavior();

  /// A cache for the measured sizes of label texts by their style.
  final _sizeCache = <(String, LabelStyle), Size>{};

  /// The candidates of the last recalculation: marker index -> resolved label.
  ///
  /// Every candidate has an entry, markers without a label too. It also tells
  /// which marker an index meant at that time, so the results of the
  /// recalculation (labels, hidden markers) are not applied to other markers
  /// after the marker list has changed.
  final _resolved = <int, _Resolved>{};

  /// The base text style of the labels (the defaults of the context).
  TextStyle? _baseStyle;

  @override
  void initState() {
    super.initState();
    if (widget.displayLabels) widget.controller.attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStyle();
  }

  @override
  void didUpdateWidget(LabeledMarkerLayer<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.displayLabels) old.controller.detach(this);
      if (widget.displayLabels) widget.controller.attach(this);
    } else if (old.displayLabels != widget.displayLabels) {
      widget.displayLabels
          ? widget.controller.attach(this)
          : widget.controller.detach(this);
    }
    if (old.labelStyle != widget.labelStyle) {
      _sizeCache.clear();
      if (widget.displayLabels) widget.controller.invalidate();
    }
    if (!listEquals(old.sides, widget.sides) ||
        old.alwaysShowAllMarkers != widget.alwaysShowAllMarkers) {
      if (widget.displayLabels) widget.controller.invalidate();
    }
    _updateStyle();
  }

  @override
  void dispose() {
    if (widget.displayLabels) widget.controller.detach(this);
    super.dispose();
  }

  /// Updates the base label style if changed.
  void _updateStyle() {
    var s = DefaultTextStyle.of(context).style;
    if (MediaQuery.boldTextOf(context)) {
      s = s.merge(const TextStyle(fontWeight: .bold));
    }
    if (s != _baseStyle) {
      _baseStyle = s;
      _sizeCache.clear();
      if (widget.displayLabels) widget.controller.invalidate();
    }
  }

  LabelStyle _getStyleFor(LabeledMarker<T> lm) {
    return widget.labelStyleCallback?.call(lm) ?? widget.labelStyle;
  }

  /// Resolves the style, size and spacing of the label of [lm].
  ///
  /// A marker without a non-empty label gets a zero sized one.
  _Resolved _resolve(LabeledMarker<T> lm) => switch (lm.label) {
    null => _Resolved(lm, Size.zero, 0),
    TextLabel(:final text) when text.isEmpty => _Resolved(lm, Size.zero, 0),
    TextLabel(:final text) => _resolveText(lm, text),
    WidgetLabel(:final size, :final spacing) => _Resolved(lm, size, spacing),
  };

  _Resolved _resolveText(LabeledMarker<T> lm, String text) {
    final style = _getStyleFor(lm);
    return _Resolved(lm, _measureText(text, style), style.spacing, style);
  }

  Size _measureText(String text, LabelStyle style) {
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

  Rect _markerRect(Offset p, LabeledMarker<T> lm) {
    final m = lm.marker;
    final a = m.alignment?.resolve(.ltr) ?? .center;
    final center = p + Offset(a.x * m.width / 2, a.y * m.height / 2);
    return Rect.fromCenter(center: center, width: m.width, height: m.height);
  }

  @override
  List<LabelCandidate> collect(MapCamera camera, Rect area) {
    _resolved.clear();
    final out = <LabelCandidate>[];
    final items = widget.markers;
    for (var i = 0; i < items.length; i++) {
      final lm = items[i];
      final m = lm.marker;
      final rect = _markerRect(camera.latLngToScreenOffset(m.point), lm);
      if (!area.overlaps(rect)) continue;
      final res = _resolved[i] = _resolve(lm);
      out.add(
        LabelCandidate(
          host: this,
          index: i,
          markerRect: rect,
          labelSize: res.size,
          priority: widget.priority?.call(lm) ?? 0,
          sides: widget.sides,
          spacing: res.spacing,
          rotateMarker: m.rotate ?? false,
          alwaysShowMarker: widget.alwaysShowAllMarkers,
        ),
      );
    }
    return out;
  }

  Widget _label(LabeledMarker<T> lm, _Resolved res, Rect r) =>
      switch (lm.label) {
        TextLabel(:final text) => _textLabel(text, r, res.style),
        WidgetLabel(:final widget, :final ignorePointer) => Positioned.fromRect(
          rect: r,
          child: IgnorePointer(
            ignoring: ignorePointer,
            child: widget,
          ),
        ),
        null => const SizedBox.shrink(),
      };

  Widget _textLabel(String text, Rect r, LabelStyle? style) {
    if (text.isEmpty) return const SizedBox.shrink();
    final h = style?.halo;
    final ts = (_baseStyle ?? const TextStyle()).merge(style?.textStyle);

    var labelWidget = _labelWidget(text, ts);
    if (h != null && h.width != null && h.color != null) {
      labelWidget = Stack(
        children: [
          _labelWidget(
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

    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
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
      ),
    );
  }

  Widget _labelWidget(String label, TextStyle style) => Text(
    label,
    style: style,
    maxLines: 1,
    softWrap: false,
    overflow: .visible,
    textScaler: .noScaling,
    textHeightBehavior: _heightBehavior,
    textWidthBasis: .longestLine,
  );

  /// The markers to draw: all markers, except the hidden ones by the last recalculation.
  ///
  /// If [LabeledMarkerLayer.alwaysShowAllMarkers] is true or [LabeledMarkerLayer.displayLabels] is false,
  /// all markers will be drawn.
  List<Marker> _buildMarkers(BuildContext context) {
    final items = widget.markers;
    if (widget.alwaysShowAllMarkers || !widget.displayLabels) {
      return [for (final lm in items) lm.marker];
    }
    final hidden = widget.controller.hiddenMarkersOf(this);
    return [
      for (var i = 0; i < items.length; i++)
        // Only hide a marker the last recalculation really decided about:
        // a new or moved marker is shown until the next recalculation.
        if (!hidden.contains(i) || _resolved[i]?.marker != items[i])
          items[i].marker,
    ];
  }

  /// Labels live in their own screen-space overlay, NOT inside the markers:
  /// MarkerLayer culls a marker as soon as its own box leaves the viewport,
  /// which would drop the label even though it is still partly visible.
  /// Here a label stays until its own rect leaves the viewport.
  Widget _buildLabels(BuildContext context) {
    final camera = MapCamera.of(context);
    widget.controller.onCamera(camera);

    final viewport = Offset.zero & camera.size;
    final items = widget.markers;
    final children = <Widget>[];
    widget.controller.placementsOf(this).forEach((i, side) {
      final res = _resolved[i];
      if (res == null || i >= items.length || res.marker != items[i]) {
        return;
      }
      final lm = items[i];
      final markerRect = LabelGeometry.effectiveMarkerRect(
        _markerRect(camera.latLngToScreenOffset(lm.marker.point), lm),
        lm.marker.rotate ?? false,
        camera.rotation,
      );
      final r = LabelGeometry.labelRectFor(
        markerRect,
        res.size,
        res.spacing,
        side,
      );
      if (r.overlaps(viewport)) children.add(_label(lm, res, r));
    });
    return Stack(
      clipBehavior: .hardEdge,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.displayLabels) {
      return MarkerLayer(
        markers: _buildMarkers(context),
        alignment: widget.alignment,
        rotate: widget.rotate,
      );
    }

    if (widget.alwaysShowAllMarkers) {
      return Stack(
        fit: .expand,
        children: [
          MarkerLayer(
            markers: _buildMarkers(context),
            alignment: widget.alignment,
            rotate: widget.rotate,
          ),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (_, _) {
              // Rebuild via MapCamera dependency only affects the inner Builder.
              return Builder(
                builder: _buildLabels,
              );
            },
          ),
        ],
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (_, _) {
        return Stack(
          fit: .expand,
          children: [
            MarkerLayer(
              markers: _buildMarkers(context),
              alignment: widget.alignment,
              rotate: widget.rotate,
            ),
            // Rebuild via MapCamera dependency only affects the inner Builder.
            Builder(
              builder: _buildLabels,
            ),
          ],
        );
      },
    );
  }
}
