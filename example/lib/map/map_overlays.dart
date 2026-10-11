import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Zoom and rotation buttons, and the current zoom and rotation of the map.
///
/// The thresholds of the controller are easier to try with fixed steps.
class MapControls extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final controller = MapController.of(context);
    final theme = Theme.of(context);

    void zoomBy(double delta) =>
        controller.move(camera.center, camera.zoom + delta);

    final rotation = (camera.rotation % 360 + 360) % 360;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Zoom in (+0.25)',
                    icon: const Icon(Icons.add),
                    onPressed: () => zoomBy(.25),
                  ),
                  IconButton(
                    tooltip: 'Zoom out (-0.25)',
                    icon: const Icon(Icons.remove),
                    onPressed: () => zoomBy(-.25),
                  ),
                  const SizedBox(width: 32, child: Divider(height: 1)),
                  IconButton(
                    tooltip: 'Rotate left (5°)',
                    icon: const Icon(Icons.rotate_left),
                    onPressed: () => controller.rotate(camera.rotation - 5),
                  ),
                  IconButton(
                    tooltip: 'Rotate right (5°)',
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () => controller.rotate(camera.rotation + 5),
                  ),
                  IconButton(
                    tooltip: 'North up',
                    icon: Transform.rotate(
                      angle: camera.rotationRad,
                      child: const Icon(Icons.navigation_outlined),
                    ),
                    onPressed: () => controller.rotate(0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              child: _Box(
                child: Text(
                  'zoom ${camera.zoom.toStringAsFixed(2)}\n'
                  'rotation ${rotation.toStringAsFixed(0)}°',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sources of the data shown on the map.
class MapAttribution extends StatelessWidget {
  const new({required this.showTiles, super.key});

  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _Box(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Data: ', style: style),
              _Link('Natural Earth', 'https://www.naturalearthdata.com'),
              if (showTiles) ...[
                Text(' · Tiles: © ', style: style),
                _Link(
                  'OpenStreetMap contributors',
                  'https://www.openstreetmap.org/copyright',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: child,
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const new(this.text, this.url);

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
