import 'dart:math' as math;
import 'dart:ui';

import 'labeled_marker.dart';

/// Utility class for label and marker geometry calculations.
abstract final class LabelGeometry {
  /// Returns true if the given [angle] in degrees is closer to a 90° or 270° turn, than to a 0° or 180° turn.
  static bool _isCloserToQuarterTurn(double angle) {
    angle = (angle % 360 + 360) % 360;
    final dHoriz = (angle % 180 <= 90) ? angle % 180 : 180 - (angle % 180);
    return dHoriz > 45;
  }

  /// The screen rect a marker occupies at the given [mapRotation].
  ///
  /// Markers that are not counter rotated ([rotateMarker] is false) turn with
  /// the map, so close to a quarter turn their width and height are swapped.
  static Rect effectiveMarkerRect(
    Rect m,
    bool rotateMarker,
    double mapRotation,
  ) => !rotateMarker && _isCloserToQuarterTurn(mapRotation)
      ? Rect.fromCenter(center: m.center, width: m.height, height: m.width)
      : m;

  /// Screen rect of a label placed on [side] of the marker.
  static Rect labelRectFor(Rect m, Size s, double g, LabelSide side) {
    return switch (side) {
      .bottom => .fromLTWH(
        m.center.dx - s.width / 2,
        m.bottom + g,
        s.width,
        s.height,
      ),
      .top => .fromLTWH(
        m.center.dx - s.width / 2,
        m.top - g - s.height,
        s.width,
        s.height,
      ),
      .right => .fromLTWH(
        m.right + g,
        m.center.dy - s.height / 2,
        s.width,
        s.height,
      ),
      .left => .fromLTWH(
        m.left - g - s.width,
        m.center.dy - s.height / 2,
        s.width,
        s.height,
      ),
    };
  }

  /// The size of the bounding box of a rect of size [s] rotated by [angle] radians.
  static Size rotatedBounds(Size s, double angle) {
    final c = math.cos(angle).abs();
    final n = math.sin(angle).abs();
    return Size(s.width * c + s.height * n, s.width * n + s.height * c);
  }

  /// Maps [angle] (radians) to the (-π/2, π/2] range, by turning it 180°
  /// if needed, so a text rotated by it is never upside down.
  static double uprightAngle(double angle) {
    if (angle > math.pi / 2) return angle - math.pi;
    if (angle <= -math.pi / 2) return angle + math.pi;
    return angle;
  }
}
