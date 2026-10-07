import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'label_controller.dart';
import 'label_fader.dart';
import 'label_geometry.dart';
import 'label_renderer.dart';
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
    super.key,
    this.displayLabels = true,
    this.priority,
    this.labelStyle = const LabelStyle(
      TextStyle(fontSize: 12, color: Color(0xFF000000)),
    ),
    this.labelStyleCallback,
    this.sides = const [.right, .left, .bottom, .top],
    this.minZoomForLabels,
    this.maxZoomForLabels,
    this.alwaysShowAllMarkers = true,
    this.labelFadeDuration = const Duration(milliseconds: 200),
  }) : assert(
         minZoomForLabels == null ||
             maxZoomForLabels == null ||
             minZoomForLabels <= maxZoomForLabels,
       );

  /// The controller that manages label collisions for this layer.
  final LabelCollisionController controller;

  /// If false, this is a plain [MarkerLayer]: no labels, and the layer does
  /// not take part in the collision detection (its markers do not block
  /// the labels of other layers either).
  ///
  /// If you want to simply hide a label, but ensure its marker still participates
  /// in the collision detection, simply set the [LabeledMarker.label] to null.
  final bool displayLabels;

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

  /// The default style of the [TextLabel] type labels.
  ///
  /// Used for every text label unless overridden by [labelStyleCallback].
  /// With [LabelStyle.hidden] no text label is drawn unless the callback
  /// gives it a style.
  /// Has no effect on [WidgetLabel] type labels.
  final LabelStyle labelStyle;

  /// A callback that sets the [LabelStyle] of the text label of every marker in the layer.
  ///
  /// If provided, this overrides the [labelStyle] for markers where it returns a non-null value.
  /// Return [LabelStyle.hidden] to hide the label of a marker (the marker is
  /// still an obstacle for the other labels).
  /// If the results of the function change, should call invalidate on the
  /// [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final LabelStyleCallback<T>? labelStyleCallback;

  /// Possible positions for the label relative to its marker, tried in order.
  final List<LabelSide> sides;

  /// The minimum zoom level (inclusive) at which labels are displayed.
  ///
  /// Labels are not shown if the current zoom level is below this value.
  /// The markers still take part in the collision detection (they block the
  /// labels of other layers, and can be hidden by [alwaysShowAllMarkers]).
  final double? minZoomForLabels;

  /// The maximum zoom level (inclusive) at which labels are displayed.
  ///
  /// Labels are not shown if the current zoom level is above this value.
  /// The markers still take part in the collision detection (they block the
  /// labels of other layers, and can be hidden by [alwaysShowAllMarkers]).
  final double? maxZoomForLabels;

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

  /// The duration of the fade when a label appears or disappears.
  ///
  /// [Duration.zero] turns the animation off. Only the labels fade: hidden
  /// markers (see [alwaysShowAllMarkers]) are removed immediately.
  final Duration labelFadeDuration;

  @override
  State<LabeledMarkerLayer<T>> createState() => _LabeledMarkerLayerState<T>();
}

class _LabeledMarkerLayerState<T> extends State<LabeledMarkerLayer<T>>
    implements LabelLayerHost {
  final _renderer = LabelRenderer();
  final _fader = LabelFader();

  /// The candidates of the last recalculation: marker index -> resolved label.
  ///
  /// Every candidate has an entry, markers without a label too. It also tells
  /// which marker an index meant at that time, so the results of the
  /// recalculation (labels, hidden markers) are not applied to other markers
  /// after the marker list has changed.
  final _resolved = <int, ResolvedLabel>{};

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
  void didUpdateWidget(LabeledMarkerLayer<T> old) {
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
    if (old.minZoomForLabels != widget.minZoomForLabels ||
        old.maxZoomForLabels != widget.maxZoomForLabels) {
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

  LabelStyle _getStyleFor(LabeledMarker<T> lm) {
    return widget.labelStyleCallback?.call(lm) ?? widget.labelStyle;
  }

  Rect _markerRect(Offset p, LabeledMarker<T> lm) {
    final m = lm.marker;
    final a = m.alignment?.resolve(.ltr) ?? .center;
    final center = p + Offset(a.x * m.width / 2, a.y * m.height / 2);
    return Rect.fromCenter(center: center, width: m.width, height: m.height);
  }

  @override
  bool labelsVisibleAt(double zoom) =>
      (widget.minZoomForLabels == null || zoom >= widget.minZoomForLabels!) &&
      (widget.maxZoomForLabels == null || zoom <= widget.maxZoomForLabels!);

  @override
  List<LabelCandidate> collect(MapCamera camera, Rect area) {
    _resolved.clear();
    final out = <LabelCandidate>[];
    final items = widget.markers;
    final labelsVisible = labelsVisibleAt(camera.zoom);
    for (var i = 0; i < items.length; i++) {
      final lm = items[i];
      final m = lm.marker;
      final rect = LabelGeometry.effectiveMarkerRect(
        _markerRect(camera.latLngToScreenOffset(m.point), lm),
        m.rotate ?? false,
        camera.rotation,
      );
      if (!area.overlaps(rect)) continue;
      // Out of the zoom range the labels are not measured at all, but the
      // marker still takes part in the collision detection as an obstacle.
      final res = _resolved[i] = labelsVisible
          ? _renderer.resolve(context, lm, lm.label, () => _getStyleFor(lm))
          : ResolvedLabel(lm, Size.zero, 0);
      out.add(
        LabelCandidate(
          host: this,
          index: i,
          priority: widget.priority?.call(lm) ?? 0,
          obstacle: rect,
          alwaysShow: widget.alwaysShowAllMarkers,
          slots: res.size.isEmpty
              ? const []
              : [
                  for (final side in widget.sides)
                    LabelSlot.single(
                      LabelGeometry.labelRectFor(
                        rect,
                        res.size,
                        res.spacing,
                        side,
                      ),
                    ),
                ],
        ),
      );
    }
    return out;
  }

  /// The markers to draw: all markers, except the hidden ones by the last recalculation.
  ///
  /// If [LabeledMarkerLayer.alwaysShowAllMarkers] is true or [LabeledMarkerLayer.displayLabels] is false,
  /// all markers will be drawn.
  List<Marker> _buildMarkers() {
    final items = widget.markers;
    if (widget.alwaysShowAllMarkers || !widget.displayLabels) {
      return [for (final lm in items) lm.marker];
    }
    final hidden = widget.controller.hiddenMarkersOf(this);
    return [
      for (var i = 0; i < items.length; i++)
        // Only hide a marker the last recalculation really decided about:
        // a new or moved marker is shown until the next recalculation.
        if (!hidden.contains(i) || _resolved[i]?.source != items[i])
          items[i].marker,
    ];
  }

  /// Where the label of [lm] is for a camera. The label follows its marker
  /// while the map moves, and stays until its own rect leaves the viewport.
  LabelPlacer _placer(
    LabeledMarker<T> lm,
    Label label,
    ResolvedLabel res,
    LabelSide side,
  ) => (camera) {
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
    if (!r.overlaps(Offset.zero & camera.size)) return null;
    return PlacedLabel(r, _renderer.content(label, res.style));
  };

  /// Labels live in their own screen-space overlay, NOT inside the markers:
  /// MarkerLayer culls a marker as soon as its own box leaves the viewport,
  /// which would drop the label even though it is still partly visible.
  /// Here a label stays until its own rect leaves the viewport.
  Widget _buildLabels(BuildContext context) {
    final camera = MapCamera.of(context);
    widget.controller.onCamera(camera);

    final items = widget.markers;
    final placed = LinkedHashMap<Object, LabelPlacer>.identity();
    // Out of the zoom range nothing is placed, so the labels fade out.
    if (labelsVisibleAt(camera.zoom)) {
      widget.controller.placementsOf(this).forEach((i, slot) {
        final res = _resolved[i];
        if (res == null ||
            i >= items.length ||
            res.source != items[i] ||
            slot >= widget.sides.length) {
          return;
        }
        final lm = items[i];
        final label = lm.label;
        if (label == null) return;
        placed[lm] = _placer(lm, label, res, widget.sides[slot]);
      });
    }
    return Stack(
      clipBehavior: .hardEdge,
      children: _fader.build(camera, placed),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.displayLabels) {
      return MarkerLayer(markers: _buildMarkers());
    }

    final labels = ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _fader]),
      builder: (_, _) {
        // Rebuild via MapCamera dependency only affects the inner Builder.
        return Builder(builder: _buildLabels);
      },
    );

    if (widget.alwaysShowAllMarkers) {
      return Stack(
        fit: .expand,
        children: [
          MarkerLayer(markers: _buildMarkers()),
          labels,
        ],
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (_, _) {
        return Stack(
          fit: .expand,
          children: [
            MarkerLayer(markers: _buildMarkers()),
            labels,
          ],
        );
      },
    );
  }
}
