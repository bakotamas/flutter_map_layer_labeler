import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// A label that is positioned on the screen for the current camera.
class PlacedLabel {
  const new(this.rect, this.child, {this.angle = 0});

  /// The screen rect of the (unturned) label.
  final Rect rect;

  final Widget child;

  /// The label is turned around the center of [rect] by this many radians.
  final double angle;
}

/// Calculates where a label is for [camera], or null if it is off the screen.
typedef LabelPlacer = PlacedLabel? Function(MapCamera camera);

class _FadeEntry {
  new(this.key, this.placer);

  final Object key;
  LabelPlacer placer;

  /// False when the label lost its place and is fading out.
  bool visible = true;

  /// True when the fade in has finished once, so a label that returns to the
  /// screen after a pan does not fade in again.
  bool settled = false;
}

/// Builds the label overlay of a layer and fades the labels in and out.
///
/// Labels that lost their place at a recalculation are kept (with their last
/// placer) until they have faded out, so they still follow their item.
class LabelFader extends ChangeNotifier {
  /// The duration of the fade. [Duration.zero] turns the animation off.
  Duration duration = Duration.zero;

  final _entries = LinkedHashMap<Object, _FadeEntry>.identity();

  /// Returns the children of the label overlay (a `Stack`).
  ///
  /// [placed] maps an item to the placer of its label.
  List<Widget> build(MapCamera camera, Map<Object, LabelPlacer> placed) {
    if (duration <= Duration.zero) {
      _entries.clear();
      return [
        for (final MapEntry(:key, :value) in placed.entries)
          if (value(camera) case final p?) _position(key, p, p.child),
      ];
    }

    for (final e in _entries.values) {
      e.visible = false;
    }
    placed.forEach((key, placer) {
      // Not a cascade on `??=`: that would update only the new entries.
      (_entries[key] ??= _FadeEntry(key, placer))
        ..placer = placer
        ..visible = true;
    });

    final out = <Widget>[];
    final gone = <Object>[];
    for (final e in _entries.values) {
      final p = e.placer(camera);
      if (p == null) {
        if (!e.visible) gone.add(e.key);
        continue;
      }
      out.add(
        _position(
          e.key,
          p,
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: e.visible && !e.settled ? 0.0 : 1.0,
              end: e.visible ? 1.0 : 0.0,
            ),
            duration: duration,
            onEnd: () => _onEnd(e),
            builder: (_, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: p.child,
          ),
        ),
      );
    }
    gone.forEach(_entries.remove);
    return out;
  }

  void _onEnd(_FadeEntry e) {
    if (e.visible) {
      e.settled = true;
    } else if (_entries.remove(e.key) != null) {
      notifyListeners();
    }
  }

  Widget _position(Object key, PlacedLabel p, Widget child) =>
      Positioned.fromRect(
        key: ObjectKey(key),
        rect: p.rect,
        child: p.angle == 0
            ? child
            : Transform.rotate(angle: p.angle, child: child),
      );
}
