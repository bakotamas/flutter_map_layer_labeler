import 'dart:ui';

/// A spatial grid to track rectangles and overlaps.
class RectGrid {
  new(this.cell);

  final double cell;
  final _cells = <int, List<_Entry>>{};

  /// Computes the grid keys that [r] occupies.
  Iterable<int> _keys(Rect r) sync* {
    final x0 = (r.left / cell).floor(), x1 = (r.right / cell).floor();
    final y0 = (r.top / cell).floor(), y1 = (r.bottom / cell).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        yield x * 1_000_000 + y;
      }
    }
  }

  /// Adds [rect] to the grid, owned by [owner].
  void add(Rect rect, int owner) {
    final e = _Entry(rect, owner);
    for (final k in _keys(rect)) {
      (_cells[k] ??= []).add(e);
    }
  }

  /// Returns true if [rect] overlaps another not owned by [ignoreOwner].
  bool hits(Rect rect, {required int ignoreOwner}) {
    for (final k in _keys(rect)) {
      final list = _cells[k];
      if (list == null) continue;
      for (final e in list) {
        if (e.owner != ignoreOwner && e.rect.overlaps(rect)) return true;
      }
    }
    return false;
  }
}

/// An entry in the [RectGrid], representing a rectangle and its owner.
class _Entry {
  new(this.rect, this.owner);
  final Rect rect;
  final int owner;
}
