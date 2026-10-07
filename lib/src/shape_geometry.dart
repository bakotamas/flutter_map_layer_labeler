import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';

extension LatLngBoundsExtension on LatLngBounds {
  /// The screen rect that contains these bounds (also if the map is rotated).
  Rect screenRect(MapCamera camera) {
    return ShapeGeometry.boundsOf([
      camera.latLngToScreenOffset(southWest),
      camera.latLngToScreenOffset(southEast),
      camera.latLngToScreenOffset(northEast),
      camera.latLngToScreenOffset(northWest),
    ]);
  }
}

/// Utility class for the geometry of polylines and polygons on the screen.
abstract final class ShapeGeometry {
  /// The smallest rect that contains all of [points], which must not be empty.
  static Rect boundsOf(List<Offset> points) {
    var left = points.first.dx, right = left;
    var top = points.first.dy, bottom = top;
    for (final p in points) {
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// The part of the segment [p0]-[p1] that is inside [r], as the range of
  /// its parameter (0 is [p0], 1 is [p1]), or null if it is outside (Liang–Barsky).
  static (double, double)? clipSegment(Offset p0, Offset p1, Rect r) {
    var t0 = 0.0, t1 = 1.0;
    final dx = p1.dx - p0.dx, dy = p1.dy - p0.dy;

    bool clip(double p, double q) {
      if (p == 0) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
      return true;
    }

    if (clip(-dx, p0.dx - r.left) &&
        clip(dx, r.right - p0.dx) &&
        clip(-dy, p0.dy - r.top) &&
        clip(dy, r.bottom - p0.dy)) {
      return (t0, t1);
    }
    return null;
  }

  /// Clips the polygon with the vertices [points] to [r] (Sutherland–Hodgman).
  static List<Offset> clipPolygon(List<Offset> points, Rect r) {
    var out = _clipAgainst(
      points,
      (p) => p.dx >= r.left,
      (a, b) => Offset(
        r.left,
        a.dy + (b.dy - a.dy) * (r.left - a.dx) / (b.dx - a.dx),
      ),
    );
    out = _clipAgainst(
      out,
      (p) => p.dx <= r.right,
      (a, b) => Offset(
        r.right,
        a.dy + (b.dy - a.dy) * (r.right - a.dx) / (b.dx - a.dx),
      ),
    );
    out = _clipAgainst(
      out,
      (p) => p.dy >= r.top,
      (a, b) =>
          Offset(a.dx + (b.dx - a.dx) * (r.top - a.dy) / (b.dy - a.dy), r.top),
    );
    return _clipAgainst(
      out,
      (p) => p.dy <= r.bottom,
      (a, b) => Offset(
        a.dx + (b.dx - a.dx) * (r.bottom - a.dy) / (b.dy - a.dy),
        r.bottom,
      ),
    );
  }

  static List<Offset> _clipAgainst(
    List<Offset> input,
    bool Function(Offset) inside,
    Offset Function(Offset, Offset) intersect,
  ) {
    if (input.isEmpty) return input;
    final output = <Offset>[];
    var prev = input.last;
    for (final cur in input) {
      final curIn = inside(cur), prevIn = inside(prev);
      if (curIn) {
        if (!prevIn) output.add(intersect(prev, cur));
        output.add(cur);
      } else if (prevIn) {
        output.add(intersect(prev, cur));
      }
      prev = cur;
    }
    return output;
  }

  /// The area weighted centroid of the polygon, or null if it has less than 3 vertices.
  ///
  /// For a degenerate (zero area) polygon, the average of the vertices.
  static Offset? centroid(List<Offset> points) {
    if (points.length < 3) return null;
    var area = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p0 = points[i], p1 = points[(i + 1) % points.length];
      final cross = p0.dx * p1.dy - p1.dx * p0.dy;
      area += cross;
      cx += (p0.dx + p1.dx) * cross;
      cy += (p0.dy + p1.dy) * cross;
    }
    if (area.abs() < 1e-6) {
      var sx = 0.0, sy = 0.0;
      for (final p in points) {
        sx += p.dx;
        sy += p.dy;
      }
      return Offset(sx / points.length, sy / points.length);
    }
    return Offset(cx / (3 * area), cy / (3 * area));
  }
}
