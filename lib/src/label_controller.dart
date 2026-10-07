/// @docImport 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'rect_grid.dart';

/// A place where a label can be put: the screen rects it occupies.
///
/// Most labels occupy one rect. A label that follows a curved line occupies
/// several small ones, so it does not block the empty space around the curve.
class LabelSlot {
  const new(this.rects);

  /// A slot that occupies one rect.
  factory single(Rect rect) => LabelSlot([rect]);

  /// A slot that can not be used (for example, it is outside the solved area).
  static const unusable = LabelSlot([]);

  /// The screen rects of the slot. Empty if the slot can not be used.
  final List<Rect> rects;
}

/// Represents a candidate label of a map item (marker, polyline or polygon),
/// including the places where its label can be put and its priority.
class LabelCandidate {
  new({
    required this.host,
    required this.index,
    required this.priority,
    required this.slots,
    this.obstacle,
    this.alwaysShow = true,
    this.tier = 0,
  });

  /// The host layer that owns this candidate.
  final LabelLayerHost host;

  /// The key of the candidate in the host layer, usually the index of the item.
  ///
  /// A host that has more candidates per item (repeated labels) can encode
  /// the item and the repeat in it. It is only used to identify the
  /// placement and to order candidates of equal priority.
  final int index;

  /// Candidates of a lower tier are placed before the ones of a higher tier,
  /// whatever their priority is.
  ///
  /// It lets the first label of every item win against the repeated labels of
  /// the other items.
  final int tier;

  /// The priority of this candidate (higher value is more preferred).
  final double priority;

  /// The screen rect that blocks the labels (and markers) of other candidates.
  ///
  /// Null if the item blocks nothing (polylines and polygons).
  final Rect? obstacle;

  /// The places the label may occupy, the earlier the more preferred.
  ///
  /// Empty if the item has no label. Slots without rects are skipped.
  final List<LabelSlot> slots;

  /// Only relevant if there is an [obstacle].
  ///
  /// If true, the item is always shown, and the obstacle blocks all labels.
  /// If false, the item is hidden, together with its label, when its obstacle
  /// collides with a higher-priority obstacle or label.
  final bool alwaysShow;

  int order = 0; // layer order, filled by the controller
  int id = 0; // unique owner id for the grid, given by the controller
}

/// Implemented by each layer state. The controller collects candidates from it.
abstract interface class LabelLayerHost {
  /// Whether this layer displays labels at [zoom].
  bool labelsVisibleAt(double zoom);

  /// Must return candidates for items whose label may be in [area].
  /// The priority and style callbacks are only evaluated for these.
  List<LabelCandidate> collect(MapCamera camera, Rect area);
}

/// Shared between any number of labeled layers and recomputes label collisions across all of them.
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

  /// Chosen slot of the labels: host -> item index -> slot index.
  final _placements = <LabelLayerHost, Map<int, int>>{};

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
  /// Call this method when the list of the items (markers, polylines,
  /// polygons), the priority function or the result of the style callback
  /// function changes on any of the attached layers.
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

  /// Label placements from the last recomputation for [host]: candidate
  /// index ([LabelCandidate.index]) -> slot index.
  @internal
  Map<int, int> placementsOf(LabelLayerHost host) =>
      _placements[host] ?? const {};

  /// Checks if a recomputation is needed based on the current camera state.
  bool _needsRecompute(MapCamera cam) {
    final s = _snap;
    if (_dirty || s == null) return true;
    if (cam.size != s.size) return true;
    if (_hosts.any(
      (host) => host.labelsVisibleAt(s.zoom) != host.labelsVisibleAt(cam.zoom),
    )) {
      return true;
    }

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

    // Obstacles that are always shown are added to the grid first.
    // The other ones are added later, in priority order, if they are not
    // hidden by higher-priority obstacles or labels.
    final grid = RectGrid(cellSize);
    for (final c in candidates) {
      final o = c.obstacle;
      if (o != null && c.alwaysShow) grid.add(o, c.id);
    }

    // Sort candidates by tier, priority, order and index.
    final sorted = [...candidates]
      ..sort((a, b) {
        final t = a.tier.compareTo(b.tier);
        if (t != 0) return t;
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        final o = a.order.compareTo(b.order);
        return o != 0 ? o : a.index.compareTo(b.index);
      });

    final result = <LabelLayerHost, Map<int, int>>{};
    final hidden = <LabelLayerHost, Set<int>>{};
    for (final c in sorted) {
      final o = c.obstacle;
      if (o != null && !c.alwaysShow) {
        // An item that collides with a stronger obstacle or label is hidden
        // together with its label.
        if (grid.hits(o, ignoreOwner: c.id)) {
          (hidden[c.host] ??= {}).add(c.index);
          continue;
        }
        grid.add(o, c.id);
      }
      for (var s = 0; s < c.slots.length; s++) {
        final rects = c.slots[s].rects;
        if (rects.isEmpty) continue;
        // All rects of the slot must be free; they do not block each other.
        if (rects.any((r) => grid.hits(r, ignoreOwner: c.id))) continue;
        for (final r in rects) {
          grid.add(r, c.id);
        }
        (result[c.host] ??= {})[c.index] = s;
        break;
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
