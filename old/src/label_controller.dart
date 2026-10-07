/// @docImport 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'label_geometry.dart';
import 'labeled_marker.dart';
import 'rect_grid.dart';

/// Represents a candidate label of a marker, including its potential placement and priority.
class LabelCandidate {
  new({
    required this.host,
    required this.index,
    required this.markerRect,
    required this.labelSize,
    required this.priority,
    required this.sides,
    required this.spacing,
    required this.rotateMarker,
    required this.alwaysShowMarker,
  });

  /// The host layer that owns this candidate.
  final LabelLayerHost host;

  /// The index of the marker in the host layer.
  final int index;

  /// The rectangle of the marker.
  final Rect markerRect;

  /// The size of the label.
  final Size labelSize;

  /// The priority of this candidate (higher value is more preferred).
  final double priority;

  /// The possible sides where the label can be placed (earlier in the list is more preferred).
  final List<LabelSide> sides;

  /// The spacing between the marker and the label.
  final double spacing;

  /// Whether the marker is counter rotated to the map's rotation.
  final bool rotateMarker;

  /// If true, all markers are always shown, and they are obstacles for all labels.
  ///
  /// If false, markers that collide with higher-priority labels are hidden, as well as their labels.
  final bool alwaysShowMarker;

  int order = 0; // layer order, filled by the controller
  int id = 0; // unique owner id for the grid, given by the controller
}

/// Implemented by each layer state. The controller collects candidates from it.
abstract interface class LabelLayerHost {
  /// Must return candidates for markers whose screen rect overlaps [area].
  /// The priority and style callbacks are only evaluated for these.
  List<LabelCandidate> collect(MapCamera camera, Rect area);
}

/// Shared between any number of [LabeledMarkerLayer]s and recomputes label collisions across all of them.
/// Recomputes only when the camera moved past a threshold since the last recomputation.
class LabelCollisionController extends ChangeNotifier {
  new({
    this.bufferFactor = .5,
    this.moveThreshold = 128,
    this.zoomThreshold = .5,
    this.rotationThreshold = 15,
    this.cellSize = 64,
  }) : assert(bufferFactor >= 0);

  /// Extra area around the viewport, as a fraction of its width/height.
  ///
  /// This helps to avoid labels popping in and out at the edges of the viewport.
  final double bufferFactor;

  /// Pan distance (in screen pixels) that triggers a recomputation.
  ///
  /// Keep it below the buffer size, or labels pop in at the edges.
  final double moveThreshold;

  /// Zoom level difference that triggers a recomputation.
  final double zoomThreshold;

  /// Rotation difference in degrees that triggers a recomputation.
  final double rotationThreshold;

  /// The size of the grid cells.
  ///
  /// If too small, labels will belong to too many cells.
  /// If too large, grid cells will contain too many labels.
  /// Neither way is good for performance.
  final double cellSize;

  final _hosts = <LabelLayerHost>[];
  final _placements = <LabelLayerHost, Map<int, LabelSide>>{};

  MapCamera? _latest;
  _Snapshot? _snap;
  bool _dirty = true;
  bool _scheduled = false;

  final _hiddenMarkers = <LabelLayerHost, Set<int>>{};

  /// Indexes of the markers of [host] that were hidden by the last recomputation.
  ///
  /// Only markers of layers with [LabeledMarkerLayer.alwaysShowAllMarkers]
  /// set to false can be hidden.
  @internal
  Set<int> hiddenMarkersOf(LabelLayerHost host) =>
      _hiddenMarkers[host] ?? const {};

  /// Attaches the given [host] to the controller.
  ///
  /// The controller will start collecting label candidates from this host.
  @internal
  void attach(LabelLayerHost host) {
    _hosts.add(host);
    invalidate();
  }

  /// Detaches the given [host] from the controller.
  ///
  /// The controller will stop collecting label candidates from this host.
  @internal
  void detach(LabelLayerHost host) {
    _hosts.remove(host);
    _placements.remove(host);
    _hiddenMarkers.remove(host);
    invalidate();
  }

  /// Forces a recalculation on the next frame.
  ///
  /// Call this method when the [LabeledMarkerLayer.markers] list, the
  /// [LabeledMarkerLayer.priority] function or the result of the
  /// [LabeledMarkerLayer.labelStyleCallback] function changes on any of the
  /// attached hosts.
  void invalidate() {
    _dirty = true;
    _schedule();
  }

  /// Called by layers on every camera change to check thresholds.
  @internal
  void onCamera(MapCamera camera) {
    _latest = camera;
    if (_needsRecompute(camera)) _schedule();
  }

  /// Label placements from the last recomputation for [host]: marker index -> side.
  @internal
  Map<int, LabelSide> placementsOf(LabelLayerHost host) =>
      _placements[host] ?? const {};

  /// Checks if a recomputation is needed based on the current camera state.
  bool _needsRecompute(MapCamera cam) {
    final s = _snap;
    if (_dirty || s == null) return true;
    if (cam.size != s.size) return true;
    if ((cam.zoom - s.zoom).abs() > zoomThreshold) return true;
    final dRotation = ((cam.rotation - s.rotation + 540) % 360 - 180).abs();
    if (dRotation > rotationThreshold) return true;
    final dCenter =
        cam.latLngToScreenOffset(s.center) -
        Offset(cam.size.width / 2, cam.size.height / 2);
    return dCenter.distance > moveThreshold;
  }

  /// Schedules a recomputation on the next frame if needed.
  void _schedule() {
    if (_scheduled || _latest == null) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _recompute())
      ..scheduleFrame();
  }

  /// Recompute the label placements.
  void _recompute() {
    _scheduled = false;
    final cam = _latest;
    if (cam == null) return;

    final w = cam.size.width, h = cam.size.height, f = bufferFactor;
    final area = Rect.fromLTRB(-w * f, -h * f, w * (1 + f), h * (1 + f));

    final candidates = <LabelCandidate>[];
    for (var li = 0; li < _hosts.length; li++) {
      for (final c in _hosts[li].collect(cam, area)) {
        c
          ..order = li
          ..id = candidates.length;
        candidates.add(c);
      }
    }

    // Markers that always shown are added to the grid as obstacles.
    // The other markers are added later, in priority order, if they not hidden by higher-priority labels.
    final grid = RectGrid(cellSize);
    for (final c in candidates) {
      if (c.alwaysShowMarker) {
        final r = LabelGeometry.effectiveMarkerRect(
          c.markerRect,
          c.rotateMarker,
          cam.rotation,
        );
        grid.add(r, c.id);
      }
    }

    // Sort candidates by priority, order and index.
    final sorted = [...candidates]
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        final o = a.order.compareTo(b.order);
        return o != 0 ? o : a.index.compareTo(b.index);
      });

    final result = <LabelLayerHost, Map<int, LabelSide>>{};
    final hidden = <LabelLayerHost, Set<int>>{};
    for (final c in sorted) {
      final mR = LabelGeometry.effectiveMarkerRect(
        c.markerRect,
        c.rotateMarker,
        cam.rotation,
      );
      if (!c.alwaysShowMarker) {
        if (grid.hits(mR, ignoreOwner: c.id)) {
          (hidden[c.host] ??= {}).add(c.index);
          continue;
        }
        grid.add(mR, c.id);
      }
      if (c.labelSize.isEmpty) continue;
      for (final side in c.sides) {
        final r = LabelGeometry.labelRectFor(mR, c.labelSize, c.spacing, side);
        if (!grid.hits(r, ignoreOwner: c.id)) {
          grid.add(r, c.id);
          (result[c.host] ??= {})[c.index] = side;
          break;
        }
      }
    }

    _placements
      ..clear()
      ..addAll(result);
    _hiddenMarkers
      ..clear()
      ..addAll(hidden);
    _snap = _Snapshot(cam.center, cam.zoom, cam.rotation, cam.size);
    _dirty = false;
    notifyListeners();
  }
}

/// Snapshot of the current camera state.
class _Snapshot {
  new(
    this.center,
    this.zoom,
    this.rotation,
    this.size,
  );

  final LatLng center;
  final double zoom;
  final double rotation;
  final Size size;
}
