import 'dart:math' as math;
import 'dart:ui';

/// A polyline on the screen with cumulative lengths, to find places by the
/// distance measured along it.
class ScreenPath {
  /// [points] must have at least two items.
  new(this.points) : cumulative = _cumulative(points);

  final List<Offset> points;

  /// `cumulative[i]` is the length of the path from the start to `points[i]`.
  final List<double> cumulative;

  /// The total length of the path.
  double get length => cumulative.last;

  static List<double> _cumulative(List<Offset> pts) {
    final out = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      out[i] = out[i - 1] + (pts[i] - pts[i - 1]).distance;
    }
    return out;
  }

  /// The index of the segment (`points[i]`-`points[i + 1]`) that contains the
  /// distance [d]. Distances outside the path give the first or last segment.
  int _segmentAt(double d) {
    var lo = 0, hi = points.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumulative[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The point at the distance [d] from the start.
  ///
  /// Outside of `0..length` the path is continued along its first/last segment.
  Offset pointAt(double d) {
    final i = _segmentAt(d);
    final segment = cumulative[i + 1] - cumulative[i];
    if (segment == 0) return points[i];
    return Offset.lerp(
      points[i],
      points[i + 1],
      (d - cumulative[i]) / segment,
    )!;
  }

  /// The part of the path between the distances [d0] and [d1] (continued
  /// beyond the ends if needed), as a list of points.
  List<Offset> slice(double d0, double d1) {
    final out = <Offset>[pointAt(d0)];
    // Only the points inside the range are visited, so a very long line
    // is not walked again for every slice.
    for (
      var i = _segmentAt(d0) + 1;
      i < points.length && cumulative[i] < d1;
      i++
    ) {
      if (cumulative[i] > d0) out.add(points[i]);
    }
    out.add(pointAt(d1));
    return out;
  }

  /// How far the part of the path between the distances [d0] and [d1] is from
  /// being straight: the largest distance of its points from the chord, in
  /// pixels. 0 means a perfectly straight part.
  double deviation(double d0, double d1) {
    final a = pointAt(d0), b = pointAt(d1);
    var worst = 0.0;
    for (
      var i = _segmentAt(d0) + 1;
      i < points.length && cumulative[i] < d1;
      i++
    ) {
      if (cumulative[i] > d0) {
        worst = math.max(worst, _distanceToSegment(points[i], a, b));
      }
    }
    return worst;
  }

  /// [pts] moved sideways by [distance].
  ///
  /// A positive [distance] moves the points to the left of the direction of
  /// travel as seen on the screen (to the top of a text that runs along the
  /// points), a negative one to the right. At the vertices the average
  /// direction of the two segments is used.
  static List<Offset> offset(List<Offset> pts, double distance) {
    if (pts.length < 2 || distance == 0) return pts;
    Offset unit(Offset a, Offset b) {
      final d = b - a;
      final length = d.distance;
      return length == 0 ? Offset.zero : d / length;
    }

    final out = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final before = i > 0 ? unit(pts[i - 1], pts[i]) : Offset.zero;
      final after = i < pts.length - 1 ? unit(pts[i], pts[i + 1]) : Offset.zero;
      var d = before + after;
      if (d.distance < 1e-9) d = after == Offset.zero ? before : after;
      if (d.distance < 1e-9) {
        out.add(pts[i]);
        continue;
      }
      d = d / d.distance;
      out.add(pts[i] + Offset(d.dy, -d.dx) * distance);
    }
    return out;
  }

  /// A copy of this path with every corner replaced by a smooth curve.
  ///
  /// Around a corner a quadratic Bézier curve is used: it starts at the
  /// distance [radius] before the corner, ends at the same distance after it,
  /// and the corner itself is its control point. The curve joins the straight
  /// parts without a break in the direction, and never leaves the triangle
  /// of the corner (it can not overshoot like an interpolating spline).
  /// The radius is limited to the half of the shorter neighbor segment, so
  /// the curves of two neighbor corners never overlap. Nearly straight
  /// corners are left as they are, and straight parts stay straight.
  ///
  /// The curve is flattened to short segments (about every 8.5 degrees of
  /// turn), so the result can be used as any other [ScreenPath].
  ScreenPath rounded(double radius) {
    if (radius <= 0 || points.length < 3) return this;
    // Consecutive duplicates have no direction, so they are dropped.
    final pts = <Offset>[points.first];
    for (final p in points.skip(1)) {
      if ((p - pts.last).distance > 1e-6) pts.add(p);
    }
    if (pts.length < 3) return this;

    final out = <Offset>[pts.first];
    for (var i = 1; i < pts.length - 1; i++) {
      final p = pts[i];
      final toPrev = pts[i - 1] - p, toNext = pts[i + 1] - p;
      final l0 = toPrev.distance, l1 = toNext.distance;
      final u0 = toPrev / l0, u1 = toNext / l1;
      // The angle between the direction before the corner (-u0) and after it (u1).
      final cosTurn = (-(u0.dx * u1.dx + u0.dy * u1.dy)).clamp(-1.0, 1.0);
      final turn = math.acos(cosTurn);
      if (turn < .02) {
        out.add(p);
        continue;
      }
      final r = math.min(radius, math.min(l0, l1) / 2);
      final a = p + u0 * r, b = p + u1 * r;
      final n = math.min(24, math.max(2, (turn / .15).ceil()));
      for (var k = 0; k <= n; k++) {
        final t = k / n, m = 1 - t;
        out.add(a * (m * m) + p * (2 * m * t) + b * (t * t));
      }
    }
    out.add(pts.last);
    return ScreenPath(out);
  }

  /// Douglas–Peucker simplification of [pts].
  ///
  /// Returns the indexes of the points to keep (always the first and the last
  /// one): no removed point is farther than [tolerance] from the result.
  /// Iterative, so a very long line can not overflow the stack.
  static List<int> simplify(List<Offset> pts, double tolerance) {
    if (pts.length < 3) return [for (var i = 0; i < pts.length; i++) i];
    final keep = List<bool>.filled(pts.length, false);
    keep[0] = keep[pts.length - 1] = true;
    final stack = <(int, int)>[(0, pts.length - 1)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      var maxDistance = 0.0, far = -1;
      for (var i = a + 1; i < b; i++) {
        final d = _distanceToSegment(pts[i], pts[a], pts[b]);
        if (d > maxDistance) {
          maxDistance = d;
          far = i;
        }
      }
      if (far != -1 && maxDistance > tolerance) {
        keep[far] = true;
        stack
          ..add((a, far))
          ..add((far, b));
      }
    }
    return [
      for (var i = 0; i < pts.length; i++)
        if (keep[i]) i,
    ];
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a, ap = p - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return ap.distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}
