import 'dart:collection';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'label_controller.dart';
import 'label_fader.dart';
import 'label_renderer.dart';
import 'labeled_marker.dart';
import 'shape_geometry.dart';

/// Higher returned value means the label is placed earlier (wins conflicts).
typedef PolygonPriorityCallback<T> = double Function(
  LabeledPolygon<T> polygon,
);

/// A callback that returns the [LabelStyle] for a given polygon.
///
/// Returns null to use the default [LabeledPolygonLayer.labelStyle].
typedef PolygonLabelStyleCallback<T> = LabelStyle? Function(
  LabeledPolygon<T> polygon,
);

/// The place of the label of a polygon. It belongs to the whole polygon, so
/// it does not depend on the viewport, the zoom or the rotation of the map.
enum PolygonLabelAnchor {
  /// The center of the bounding box of the polygon (in the projected plane).
  boundingBoxCenter,

  /// The area weighted centroid of the polygon (in the projected plane).
  centroid,
}

/// Wrapper class that associates a polygon with a label and additional data.
class LabeledPolygon<T> {
  const new _({
    required this.polygon,
    required this.label,
    required this.data,
  });

  /// Creates a labeled polygon with the specified polygon, text label, and optional additional data.
  factory({
    required Polygon polygon,
    required String labelText,
    T? data,
  }) => LabeledPolygon._(
    polygon: polygon,
    label: TextLabel(labelText),
    data: data,
  );

  /// Creates a labeled polygon with the specified polygon, sized widget label, and optional additional data.
  factory widget({
    required Polygon polygon,
    required Widget labelWidget,
    required Size labelSize,
    T? data,
    bool ignorePointer = false,
  }) => LabeledPolygon._(
    polygon: polygon,
    label: WidgetLabel(
      labelWidget,
      labelSize,
      ignorePointer: ignorePointer,
    ),
    data: data,
  );

  /// The polygon associated with this labeled polygon.
  ///
  /// Do not set its own label: the layer draws the label of the [LabeledPolygon].
  /// Do not modify its points in place: the layer remembers their bounds and label place.
  final Polygon polygon;

  /// The label associated with the polygon.
  ///
  /// If null, the polygon has no label.
  final Label? label;

  /// Additional data for the priority and style callbacks.
  final T? data;
}

/// A layer that displays polygons with labels at a fixed place of the polygon,
/// and handles label collisions together with the other labeled layers.
///
/// The label place is the centroid or the bounding box center of the whole
/// polygon (see [labelAnchor]), so the label does not move on the polygon
/// while the map is panned. If that place is off the screen, so is the label.
///
/// Polygons are not obstacles: a label can lie on top of any polygon, but
/// it never overlaps the markers and the other labels.
class LabeledPolygonLayer<T> extends StatefulWidget {
  /// Creates a labeled polygon layer with the specified controller, polygons, and optional label settings.
  const new({
    required this.controller,
    required this.polygons,
    super.key,
    this.displayLabels = true,
    this.priority,
    this.labelStyle = const LabelStyle(
      TextStyle(fontSize: 12, color: Color(0xFF000000)),
    ),
    this.labelStyleCallback,
    this.labelAnchor = .centroid,
    this.hideLabelIfLargerThanPolygon = true,
    this.labelFadeDuration = const Duration(milliseconds: 200),
  });

  /// The controller that manages label collisions for this layer.
  final LabelCollisionController controller;

  /// If false, this is a plain [PolygonLayer]: no labels, and the layer does
  /// not take part in the collision detection.
  final bool displayLabels;

  /// The list of labeled polygons to display in this layer.
  ///
  /// Do not modify the list in place: pass a new list when the content changes.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise labels may be misplaced or missing until the next threshold update.
  final List<LabeledPolygon<T>> polygons;

  /// The function that determines the priority of each label.
  /// Higher values mean the label is placed earlier and wins conflicts.
  ///
  /// If changed, should call invalidate on the [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final PolygonPriorityCallback<T>? priority;

  /// The default style of the [TextLabel] type labels.
  ///
  /// Used for every text label unless overridden by [labelStyleCallback].
  /// With [LabelStyle.hidden] no text label is drawn unless the callback
  /// gives it a style.
  /// Has no effect on [WidgetLabel] type labels, and its spacing is not used.
  final LabelStyle labelStyle;

  /// A callback that sets the [LabelStyle] of the text label of every polygon in the layer.
  ///
  /// If provided, this overrides the [labelStyle] for polygons where it returns a non-null value.
  /// Return [LabelStyle.hidden] to hide the label of a polygon.
  /// If the results of the function change, should call invalidate on the
  /// [controller] to recalculate label placements,
  /// otherwise the recalculation may be delayed until the next threshold update.
  final PolygonLabelStyleCallback<T>? labelStyleCallback;

  /// Where the label is put on the whole polygon.
  final PolygonLabelAnchor labelAnchor;

  /// If true, the label is not shown when it is larger than the polygon
  /// (its bounding box on the screen).
  final bool hideLabelIfLargerThanPolygon;

  /// The duration of the fade when a label appears or disappears.
  ///
  /// [Duration.zero] turns the animation off.
  final Duration labelFadeDuration;

  @override
  State<LabeledPolygonLayer<T>> createState() => _LabeledPolygonLayerState<T>();
}

/// What the last recalculation resolved for a polygon.
class _PolygonLabel {
  const new(this.res, this.anchor);

  final ResolvedLabel res;

  /// The geographic place of the label, so it follows the polygon when the map moves.
  final LatLng anchor;
}

class _LabeledPolygonLayerState<T> extends State<LabeledPolygonLayer<T>>
    implements LabelLayerHost {
  final _renderer = LabelRenderer();
  final _fader = LabelFader();

  /// The labeled polygons of the last recalculation: polygon index -> what was resolved.
  final _entries = <int, _PolygonLabel>{};

  /// The geographic bounds of the polygons.
  final _bounds = Expando<LatLngBounds>();

  /// The label places of the polygons, for the current [LabeledPolygonLayer.labelAnchor].
  var _anchors = Expando<LatLng>();

  List<LabeledPolygon<T>>? _source;
  List<Polygon> _shapes = const [];

  /// The plain polygons, with the same list instance until the labeled list changes.
  List<Polygon> get _plainPolygons {
    if (!identical(_source, widget.polygons)) {
      _source = widget.polygons;
      _shapes = [for (final lp in widget.polygons) lp.polygon];
    }
    return _shapes;
  }

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
  void didUpdateWidget(LabeledPolygonLayer<T> old) {
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
    if (old.labelAnchor != widget.labelAnchor) {
      _anchors = Expando<LatLng>();
      if (widget.displayLabels) widget.controller.invalidate();
    }
    if (old.hideLabelIfLargerThanPolygon !=
        widget.hideLabelIfLargerThanPolygon) {
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

  LabelStyle _getStyleFor(LabeledPolygon<T> lp) {
    return widget.labelStyleCallback?.call(lp) ?? widget.labelStyle;
  }

  /// The label place of [polygon], calculated once from all of its points in
  /// the projected plane (not on the screen), so it does not depend on the camera.
  LatLng _anchorOf(MapCamera camera, Polygon polygon) {
    return _anchors[polygon] ??= () {
      final projection = camera.crs.projection;
      final pts = [for (final p in polygon.points) projection.project(p)];
      final center = switch (widget.labelAnchor) {
        .boundingBoxCenter => ShapeGeometry.boundsOf(pts).center,
        .centroid =>
          ShapeGeometry.centroid(pts) ?? ShapeGeometry.boundsOf(pts).center,
      };
      return projection.unproject(Point(center.dx, center.dy));
    }();
  }

  @override
  bool labelsVisibleAt(double zoom) => true;

  @override
  List<LabelCandidate> collect(MapCamera camera, Rect area) {
    _entries.clear();
    final out = <LabelCandidate>[];
    final items = widget.polygons;
    for (var i = 0; i < items.length; i++) {
      final lp = items[i];
      final points = lp.polygon.points;
      // Polygons are not obstacles, so only the labeled ones are candidates.
      final label = lp.label;
      if (label == null || points.length < 3) continue;
      final bounds = _bounds[lp.polygon] ??= LatLngBounds.fromPoints(points);
      // The label place is inside the bounds of the polygon.
      final screenBounds = bounds.screenRect(camera);
      if (!screenBounds.overlaps(area)) continue;

      final res = _renderer.resolve(context, lp, label, () => _getStyleFor(lp));
      if (res.size.isEmpty) continue;
      if (widget.hideLabelIfLargerThanPolygon &&
          (res.size.width > screenBounds.width ||
              res.size.height > screenBounds.height)) {
        continue;
      }

      final anchor = _anchorOf(camera, lp.polygon);
      final rect = Rect.fromCenter(
        center: camera.latLngToScreenOffset(anchor),
        width: res.size.width,
        height: res.size.height,
      );
      if (!rect.overlaps(area)) continue;

      _entries[i] = _PolygonLabel(res, anchor);
      out.add(
        LabelCandidate(
          host: this,
          index: i,
          priority: widget.priority?.call(lp) ?? 0,
          slots: [LabelSlot.single(rect)],
        ),
      );
    }
    return out;
  }

  /// Where the label is for a camera: at the geographic place of the polygon.
  LabelPlacer _placer(Label label, _PolygonLabel e) => (camera) {
    final r = Rect.fromCenter(
      center: camera.latLngToScreenOffset(e.anchor),
      width: e.res.size.width,
      height: e.res.size.height,
    );
    if (!r.overlaps(Offset.zero & camera.size)) return null;
    return PlacedLabel(r, _renderer.content(label, e.res.style));
  };

  /// Labels live in their own screen-space overlay above the polygons.
  /// A label follows its place on the polygon while the map moves, without a new calculation.
  Widget _buildLabels(BuildContext context) {
    final camera = MapCamera.of(context);
    widget.controller.onCamera(camera);

    final items = widget.polygons;
    final placed = LinkedHashMap<Object, LabelPlacer>.identity();
    widget.controller.placementsOf(this).forEach((i, _) {
      final e = _entries[i];
      if (e == null || i >= items.length || e.res.source != items[i]) return;
      final label = items[i].label;
      if (label == null) return;
      placed[items[i]] = _placer(label, e);
    });
    return Stack(
      clipBehavior: .hardEdge,
      children: _fader.build(camera, placed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shapes = PolygonLayer(polygons: _plainPolygons);
    if (!widget.displayLabels) return shapes;
    return Stack(
      fit: .expand,
      children: [
        shapes,
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
