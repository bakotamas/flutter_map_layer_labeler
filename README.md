# flutter_map_layer_labeler

Collision-free labels for [`flutter_map`](https://pub.dev/packages/flutter_map) markers.

Each marker gets a label on the first free side (right, left, bottom, top by default). If no side is free, the label is simply not shown. Collisions are solved across **all** participating layers at once, so labels never cover markers or labels of other layers.

## Features

- Labels never overlap other labels or any marker (including markers of other layers).
- Text labels with halo, padding and decoration, or arbitrary sized widgets as labels.
- Per-marker text styling through a callback.
- Priority based: higher-priority labels win conflicts.
- Configurable candidate sides and their order.
- Shared solver for any number of layers.
- Cheap during gestures: placements are recomputed only when the camera moved past a threshold, labels still follow their markers every frame.
- Labels stay visible while they are partly on screen, even if their marker has already left the viewport.

## Usage

Create one `LabelCollisionController`, share it between your layers, and dispose it with its owner.

```dart
class _MyMapState extends State<MyMap> {
  final _labels = LabelCollisionController();

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        LabeledMarkerLayer<Poi>(
          controller: _labels,
          markers: _markers,
          priority: _priorityOf,
        ),
      ],
    );
  }
}
```

### Labeled markers

Markers are wrapped in `LabeledMarker`. A marker with a text label:

```dart
final _markers = [
  for (final poi in pois)
    LabeledMarker<Poi>(
      marker: Marker(
        point: poi.position,
        width: 32,
        height: 32,
        child: const Icon(Icons.place),
      ),
      labelText: poi.name,
      data: poi, // passed to the priority and style callbacks
    ),
];

double _priorityOf(LabeledMarker<Poi> m) => m.data?.importance ?? 0;
```

A marker with a widget label. The collision detection needs the size before the widget is laid out, so it has to be provided, and the widget is given exactly this size:

```dart
LabeledMarker<Poi>.widget(
  marker: marker,
  labelWidget: const Chip(label: Text('Open now')),
  labelSize: const Size(96, 32),
  ignorePointer: false, // the label can receive taps
  spacing: 4,
)
```

A marker without a label still blocks the labels of other markers. To get one, set `label` to `null` (the unnamed `LabeledMarker` constructors always create a label).

### Styling text labels

`LabeledMarkerLayer.labelStyle` is the default style of all text labels:

| `LabelStyle` field | Default | Description |
|---|---|---|
| `textStyle` | required (first positional argument) | Merged into the ambient `DefaultTextStyle`. |
| `padding` | `symmetric(h: 4, v: 2)` | Padding around the text, included in the collision size. |
| `halo` | `TextLabelHalo()` | Outline around the text. `TextLabelHalo.zero()` for none, `TextLabelHalo.custom(...)` for your own. |
| `decoration` | `null` | `BoxDecoration` of the label box (background, border, radius). |
| `spacing` | `2` | Distance between marker and label. |

To style labels per marker, pass a `labelStyleCallback`. Return `null` to keep the layer's `labelStyle`, or a complete `LabelStyle`; use `copyWith` to change only a part of the default:

```dart
LabeledMarkerLayer<Poi>(
  controller: _labels,
  markers: _markers,
  labelStyle: const LabelStyle(TextStyle(fontSize: 12)),
  labelStyleCallback: (m) => m.data?.isCapital == true
      ? const LabelStyle(TextStyle(fontSize: 14, fontWeight: FontWeight.bold))
      : null,
)
```

`LabelStyle` has no effect on widget labels, which use their own `spacing`.

### Multiple layers

Pass the same controller to every layer. Conflicts are decided by priority first, then by the order the layers were attached, then by marker index.

```dart
LabeledMarkerLayer<City>(controller: _labels, markers: _cities, priority: _byPopulation),
LabeledMarkerLayer<Shop>(controller: _labels, markers: _shops),
```

A layer with `displayLabels: false` behaves like a plain `MarkerLayer`: it draws no labels and does not take part in the collision solving (its markers do not block other layers' labels either).

### Dense areas: hiding weaker markers

By default every marker is shown and is an obstacle for all labels, so in a dense area the label of a strong marker can lose all its free sides. Set `alwaysShowAllMarkers: false` to process the markers by priority instead: a marker that overlaps a higher-priority marker or label is hidden together with its label.

- Provide a `priority`, otherwise the order of the list decides which markers win.
- A marker whose label finds no free side is not hidden, only its label is left out.
- Markers of layers with `alwaysShowAllMarkers: true` are never hidden, and they block the markers and labels of this layer.
- Hidden markers cannot be tapped. If the child widgets of your markers are stateful, give the markers a `key`.
- The hidden markers are updated together with the labels, so while zooming they only change when the zoom threshold is crossed. Use a smaller `zoomThreshold` on the controller if this is noticeable.

## Keeping labels up to date

The solver re-runs automatically when the **camera** moves past a threshold, when the viewport size changes, and when the layer's `sides`, `alwaysShowAllMarkers`, `labelStyle` or the ambient text style change.

It does **not** detect changes to `markers`, `priority` or the results of `labelStyleCallback`. When any of them changes, call:

```dart
_labels.invalidate();
```

Until the next recalculation (at the latest the next camera threshold update), labels of changed markers may be hidden or missing.

Rules for `markers`:

- Do not modify the list in place; pass a new list when the content changes, then call `invalidate()`.
- Cache the list (and ideally the `LabeledMarker` instances) in your state instead of rebuilding it on every `build`. A label is only kept for as long as its marker instance is the same one the placement was calculated for, so rebuilding the instances hides the labels until the next recalculation.

For `priority` and `labelStyleCallback`, prefer a top-level function, a static method or a tear-off of an instance method over an inline closure. Both are evaluated once per recalculation for every marker in the calculated area, so keep them pure and fast.

## Layer parameters

| Parameter | Default | Description |
|---|---|---|
| `controller` | required | Shared `LabelCollisionController`. |
| `markers` | required | `List<LabeledMarker<T>>`. |
| `displayLabels` | `true` | `false`: plain marker layer, excluded from collision solving. |
| `priority` | `null` | `double Function(LabeledMarker<T>)`. Higher value is placed earlier and wins conflicts. |
| `labelStyle` | 12 px black `LabelStyle` | Default style of text labels. |
| `labelStyleCallback` | `null` | `LabelStyle? Function(LabeledMarker<T>)`. Per-marker text label style, `null` uses `labelStyle`. |
| `sides` | right, left, bottom, top | Candidate sides, tried in order. |
| `alwaysShowAllMarkers` | `true` | `false`: markers overlapping a stronger marker or label are hidden with their label. |

## Controller parameters

| Parameter | Default | Description |
|---|---|---|
| `bufferFactor` | `0.5` | Extra area around the viewport (fraction of its width/height) that is included in the solving. |
| `moveThreshold` | `128` | Pan distance in screen pixels that triggers a recalculation. Keep it below the buffer size, otherwise labels pop in at the edges. |
| `zoomThreshold` | `0.5` | Zoom level difference that triggers a recalculation. |
| `rotationThreshold` | `15` | Rotation difference in degrees that triggers a recalculation. |
| `cellSize` | `64` | Cell size of the spatial grid, in pixels. Keep it near the typical marker/label size. |

## How it works

1. Every layer reports the markers whose screen rectangle overlaps the viewport plus the buffer area (`LabelLayerHost.collect`). At this point the label's style, size and spacing are resolved once and kept for painting, so the solver and the drawn labels always use the same values.
2. The rectangles of the markers that are always shown, from all layers, are added to a `RectGrid` as obstacles.
3. Candidates are sorted by priority (ties: layer order, then marker index), so the result is deterministic and labels do not flicker.
4. Greedy placement: markers of layers with `alwaysShowAllMarkers: false` are first checked against the grid, and hidden (with their label) if they overlap a stronger marker or label, otherwise they are added to it. Then for each candidate the sides are tried in order; the first label rectangle that does not hit anything in the grid is accepted and added to the grid as a new obstacle. If no side is free, the marker gets no label.
5. The solver stores only the chosen **side** per marker. Each frame, the layer recomputes the label position from the current camera, so labels follow their markers during gestures without re-solving.

`RectGrid` is a sparse uniform grid (spatial hash): a rectangle is registered in every cell it touches, and a lookup only checks the entries in the cells of the queried rectangle, instead of comparing against all rectangles.

Labels are drawn in a separate, screen-space overlay above the markers rather than inside them, because `MarkerLayer` culls a marker as soon as its own box leaves the viewport, which would also drop a label that is still partly visible.

## Limitations

- The placement is greedy, not optimal: a high-priority label that takes a bad side can block lower-priority ones.
- Text labels are single-line and are not wrapped or truncated. Label sizes are measured without text scaling.
- When the map is rotated, markers that are not counter rotated are treated as swapped width/height close to a quarter turn; other angles are approximated.
