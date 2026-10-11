import 'package:flutter/material.dart';
import 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';

import '../data/gis_data.dart';
import '../settings.dart';
import 'controls.dart';

/// The settings of the demo: one tab per layer, one for the controller and
/// one for the map.
class SettingsPanel extends StatelessWidget {
  const new({required this.settings, required this.data, super.key});

  final DemoSettings settings;
  final GisData data;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Markers'),
              Tab(text: 'Polylines'),
              Tab(text: 'Polygons'),
              Tab(text: 'Controller'),
              Tab(text: 'Map'),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => TabBarView(
                children: [
                  _CityTab(settings, data),
                  _RiverTab(settings, data),
                  _CountryTab(settings, data),
                  _SolverTab(settings),
                  _MapTab(settings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The content of a tab: what it is about, a reset button and the controls.
class _TabBody extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.onReset,
    required this.children,
  });

  final String title;
  final String subtitle;
  final VoidCallback onReset;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

const _priorityBoostHint =
    'Added to the priority of every item of the layer. The priorities are '
    'compared across all layers, so the layer with the highest boost wins.';

const _fadeHint = 'Duration.zero turns the animation off.';

// ---------------------------------------------------------------- cities ---

class _CityTab extends StatelessWidget {
  const new(this.settings, this.data);

  final DemoSettings settings;
  final GisData data;

  @override
  Widget build(BuildContext context) {
    final s = settings.cities;
    final change = settings.change;
    return _TabBody(
      title: 'LabeledMarkerLayer',
      subtitle: '${data.cities.length} cities. Tap a marker for its details.',
      onReset: () => change(() => settings.cities = CitySettings()),
      children: [
        const Section('Layer'),
        ParamSwitch(
          name: 'Show the layer',
          value: s.visible,
          onChanged: (v) => change(() => s.visible = v),
        ),
        ParamSwitch(
          name: 'displayLabels',
          hint:
              'false: a plain MarkerLayer, which does not take part in the '
              'collision detection.',
          value: s.displayLabels,
          onChanged: (v) => change(() => s.displayLabels = v),
        ),
        ParamSwitch(
          name: 'alwaysShowAllMarkers',
          hint:
              'false: a marker that overlaps a stronger marker or label is '
              'hidden with its label.',
          value: s.alwaysShowAllMarkers,
          onChanged: (v) => change(() => s.alwaysShowAllMarkers = v),
        ),
        ParamOptionalSlider(
          name: 'minZoomForLabels',
          hint: 'Below it only the markers are shown.',
          value: s.minZoomForLabels,
          initial: 5,
          min: 2,
          max: 12,
          step: .5,
          digits: 1,
          onChanged: (v) => change(() {
            s.minZoomForLabels = v;
            final max = s.maxZoomForLabels;
            if (v != null && max != null && max < v) s.maxZoomForLabels = v;
          }),
        ),
        ParamOptionalSlider(
          name: 'maxZoomForLabels',
          hint: 'Above it only the markers are shown.',
          value: s.maxZoomForLabels,
          initial: 8,
          min: 2,
          max: 12,
          step: .5,
          digits: 1,
          onChanged: (v) => change(() {
            s.maxZoomForLabels = v;
            final min = s.minZoomForLabels;
            if (v != null && min != null && min > v) s.minZoomForLabels = v;
          }),
        ),
        ParamSlider(
          name: 'labelFadeDuration',
          hint: _fadeHint,
          value: s.fadeMs.toDouble(),
          min: 0,
          max: 1000,
          step: 50,
          unit: ' ms',
          onChanged: (v) => change(() => s.fadeMs = v.round()),
        ),

        const Section('Placement'),
        SidesEditor(
          order: s.sideOrder,
          enabled: s.enabledSides,
          onChanged: (order, enabled) => change(() {
            s.sideOrder = order;
            s.enabledSides = enabled;
          }),
        ),
        ParamChoice<CityPriority>(
          name: 'priority',
          hint:
              'Which labels win the conflicts. Without a priority the order '
              'of the list decides (here it is alphabetical).',
          value: s.priority,
          options: const {
            .population: 'population',
            .capitalsFirst: 'capitals first',
            .none: 'none',
          },
          onChanged: (v) => change(() => s.priority = v),
        ),
        ParamSlider(
          name: 'Priority boost',
          hint: _priorityBoostHint,
          value: s.priorityBoost.toDouble(),
          min: 0,
          max: 3,
          onChanged: (v) => change(() => s.priorityBoost = v.round()),
        ),

        const Section('labelStyle', note: 'The default style of the labels.'),
        LabelStyleEditor(style: s.style, onChanged: change),

        const Section(
          'labelStyleCallback',
          note: 'The style of single markers, decided from their data.',
        ),
        ParamSwitch(
          name: 'Capitals: larger and bold',
          hint: 'A copyWith of the default style.',
          value: s.emphasizeCapitals,
          onChanged: (v) => change(() => s.emphasizeCapitals = v),
        ),
        ParamChoice<int>(
          name: 'LabelStyle.hidden() below',
          hint:
              'Smaller cities get no label, but their markers still block '
              'the other labels.',
          value: s.hideLabelsBelow,
          options: const {
            0: 'off',
            500000: '500k',
            1000000: '1M',
            5000000: '5M',
          },
          onChanged: (v) => change(() => s.hideLabelsBelow = v),
        ),

        const Section('Markers', note: 'A new list, then invalidate().'),
        ParamChoice<int>(
          name: 'Cities with at least',
          value: s.minPopulation,
          options: const {
            0: 'all',
            100000: '100k',
            250000: '250k',
            1000000: '1M',
            5000000: '5M',
          },
          onChanged: (v) => change(() => s.minPopulation = v),
        ),
        ParamSlider(
          name: 'Marker size',
          value: s.markerSize,
          min: 4,
          max: 32,
          step: 2,
          unit: ' px',
          onChanged: (v) => change(() => s.markerSize = v),
        ),
        ParamSwitch(
          name: 'Marker.rotate',
          hint: 'Counter rotated markers stay upright on a rotated map.',
          value: s.counterRotate,
          onChanged: (v) => change(() => s.counterRotate = v),
        ),
        ParamChoice<LabelKind>(
          name: 'Label',
          hint: 'Widget labels are not affected by the label style.',
          value: s.labelKind,
          options: const {
            .text: 'LabeledMarker()',
            .widget: 'LabeledMarker.widget()',
          },
          onChanged: (v) => change(() => s.labelKind = v),
        ),
        if (s.labelKind == LabelKind.widget) ...[
          ParamSwitch(
            name: 'ignorePointer',
            hint: 'false: the label can be tapped.',
            value: !s.widgetLabelsTappable,
            onChanged: (v) => change(() => s.widgetLabelsTappable = !v),
          ),
          ParamSlider(
            name: 'spacing',
            hint: 'The distance of the widget label from its marker.',
            value: s.widgetSpacing,
            min: 0,
            max: 16,
            onChanged: (v) => change(() => s.widgetSpacing = v),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- rivers ---

class _RiverTab extends StatelessWidget {
  const new(this.settings, this.data);

  final DemoSettings settings;
  final GisData data;

  @override
  Widget build(BuildContext context) {
    final s = settings.rivers;
    final change = settings.change;
    final curved = s.followLine && s.rotateLabels;
    return _TabBody(
      title: 'LabeledPolylineLayer',
      subtitle: '${data.rivers.length} rivers.',
      onReset: () => change(() => settings.rivers = RiverSettings()),
      children: [
        const Section('Layer'),
        ParamSwitch(
          name: 'Show the layer',
          value: s.visible,
          onChanged: (v) => change(() => s.visible = v),
        ),
        ParamSwitch(
          name: 'displayLabels',
          hint: 'false: a plain PolylineLayer.',
          value: s.displayLabels,
          onChanged: (v) => change(() => s.displayLabels = v),
        ),
        ParamSlider(
          name: 'labelFadeDuration',
          hint: _fadeHint,
          value: s.fadeMs.toDouble(),
          min: 0,
          max: 1000,
          step: 50,
          unit: ' ms',
          onChanged: (v) => change(() => s.fadeMs = v.round()),
        ),

        const Section('Placement'),
        ParamChoice<LabelAlignment>(
          name: 'labelAlignment',
          value: s.labelAlignment,
          options: const {
            .onLine: 'onLine',
            .aboveLine: 'aboveLine',
            .belowLine: 'belowLine',
          },
          onChanged: (v) => change(() => s.labelAlignment = v),
        ),
        ParamSwitch(
          name: 'rotateLabels',
          hint: 'false: the labels are horizontal.',
          value: s.rotateLabels,
          onChanged: (v) => change(() => s.rotateLabels = v),
        ),
        ParamSwitch(
          name: 'followLine',
          hint:
              'The text bends with the line, glyph by glyph. Needs '
              'rotateLabels, widget labels are always straight.',
          value: s.followLine,
          onChanged: (v) => change(() => s.followLine = v),
        ),
        ParamSlider(
          name: 'cornerRadius',
          hint:
              'How much the corners of the line are rounded under a text '
              'that follows it, in text heights.',
          value: s.cornerRadius,
          min: 0,
          max: 6,
          step: .5,
          digits: 1,
          onChanged: (v) => change(() => s.cornerRadius = v),
        ),
        ParamOptionalSlider(
          name: 'labelRepeat',
          hint:
              'The smallest distance of the labels of a line, in viewport '
              'lengths. null: one label per line.',
          value: s.labelRepeat,
          initial: .8,
          min: .2,
          max: 2,
          step: .1,
          digits: 1,
          onChanged: (v) => change(() => s.labelRepeat = v),
        ),
        ParamSlider(
          name: 'maxLabelsPerLine',
          value: s.maxLabelsPerLine.toDouble(),
          min: 1,
          max: 32,
          onChanged: (v) => change(() => s.maxLabelsPerLine = v.round()),
        ),
        ParamSwitch(
          name: 'hideLabelIfLongerThanLine',
          value: s.hideLabelIfLongerThanLine,
          onChanged: (v) => change(() => s.hideLabelIfLongerThanLine = v),
        ),
        ParamChoice<RiverPriority>(
          name: 'priority',
          hint: 'The first label of every line is placed before the repeats.',
          value: s.priority,
          options: const {.importance: 'importance', .none: 'none'},
          onChanged: (v) => change(() => s.priority = v),
        ),
        ParamSlider(
          name: 'Priority boost',
          hint: _priorityBoostHint,
          value: s.priorityBoost.toDouble(),
          min: 0,
          max: 3,
          onChanged: (v) => change(() => s.priorityBoost = v.round()),
        ),

        const Section(
          'Simplification',
          note:
              'Only for the placement of the labels, the lines are drawn '
              'unchanged.',
        ),
        ParamSlider(
          name: 'simplificationTolerance',
          hint: 'In screen pixels. 0 turns it off.',
          value: s.simplificationTolerance,
          min: 0,
          max: 40,
          unit: ' px',
          onChanged: (v) => change(() => s.simplificationTolerance = v),
        ),
        ParamSlider(
          name: 'simplificationMinPoints',
          hint:
              'A line is simplified if more of its points are in the '
              'viewport.',
          value: s.simplificationMinPoints.toDouble(),
          min: 0,
          max: 1000,
          step: 25,
          onChanged: (v) => change(() => s.simplificationMinPoints = v.round()),
        ),

        const Section('labelStyle', note: 'The default style of the labels.'),
        LabelStyleEditor(
          style: s.style,
          onChanged: change,
          spacingHint:
              'The gap between the line and a label above or below it.',
          boxNote: curved
              ? 'Ignored now: the text follows the line (followLine).'
              : null,
        ),

        const Section(
          'labelStyleCallback',
          note: 'The style of single lines, decided from their data.',
        ),
        ParamSwitch(
          name: 'Major rivers: larger and bold',
          value: s.emphasizeMajor,
          onChanged: (v) => change(() => s.emphasizeMajor = v),
        ),
        ParamSlider(
          name: 'LabelStyle.hidden() above rank',
          hint: 'Less important rivers (higher rank) get no label.',
          value: s.hideLabelsAboveRank.toDouble(),
          min: 0,
          max: 8,
          onChanged: (v) => change(() => s.hideLabelsAboveRank = v.round()),
        ),

        const Section('Polylines', note: 'A new list, then invalidate().'),
        ParamSlider(
          name: 'Rivers up to rank',
          hint: '0 is the most important.',
          value: s.maxRank.toDouble(),
          min: 1,
          max: 8,
          onChanged: (v) => change(() => s.maxRank = v.round()),
        ),
        ParamSlider(
          name: 'Polyline.strokeWidth',
          hint: 'Labels above or below the line keep clear of the stroke.',
          value: s.strokeWidth,
          min: .5,
          max: 12,
          step: .5,
          digits: 1,
          unit: ' px',
          onChanged: (v) => change(() => s.strokeWidth = v),
        ),
        ParamChoice<LabelKind>(
          name: 'Label',
          hint: 'Widget labels are not affected by the label style.',
          value: s.labelKind,
          options: const {
            .text: 'LabeledPolyline()',
            .widget: 'LabeledPolyline.widget()',
          },
          onChanged: (v) => change(() => s.labelKind = v),
        ),
        if (s.labelKind == LabelKind.widget)
          ParamSlider(
            name: 'spacing',
            hint: 'The gap between the line and a widget label.',
            value: s.widgetSpacing,
            min: 0,
            max: 16,
            onChanged: (v) => change(() => s.widgetSpacing = v),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- countries ---

class _CountryTab extends StatelessWidget {
  const new(this.settings, this.data);

  final DemoSettings settings;
  final GisData data;

  @override
  Widget build(BuildContext context) {
    final s = settings.countries;
    final change = settings.change;
    return _TabBody(
      title: 'LabeledPolygonLayer',
      subtitle:
          '${data.countries.length} countries. Only the largest part of a '
          'country is labeled.',
      onReset: () => change(() => settings.countries = CountrySettings()),
      children: [
        const Section('Layer'),
        ParamSwitch(
          name: 'Show the layer',
          value: s.visible,
          onChanged: (v) => change(() => s.visible = v),
        ),
        ParamSwitch(
          name: 'displayLabels',
          hint: 'false: a plain PolygonLayer.',
          value: s.displayLabels,
          onChanged: (v) => change(() => s.displayLabels = v),
        ),
        ParamSlider(
          name: 'labelFadeDuration',
          hint: _fadeHint,
          value: s.fadeMs.toDouble(),
          min: 0,
          max: 1000,
          step: 50,
          unit: ' ms',
          onChanged: (v) => change(() => s.fadeMs = v.round()),
        ),

        const Section('Placement'),
        ParamChoice<PolygonLabelAnchor>(
          name: 'labelAnchor',
          hint: 'The place of the label on the whole polygon.',
          value: s.labelAnchor,
          options: const {
            .centroid: 'centroid',
            .boundingBoxCenter: 'boundingBoxCenter',
          },
          onChanged: (v) => change(() => s.labelAnchor = v),
        ),
        ParamSwitch(
          name: 'hideLabelIfLargerThanPolygon',
          hint: 'Compared with the bounding box of the polygon on the screen.',
          value: s.hideLabelIfLargerThanPolygon,
          onChanged: (v) => change(() => s.hideLabelIfLargerThanPolygon = v),
        ),
        ParamChoice<CountryPriority>(
          name: 'priority',
          value: s.priority,
          options: const {
            .population: 'population',
            .area: 'area',
            .none: 'none',
          },
          onChanged: (v) => change(() => s.priority = v),
        ),
        ParamSlider(
          name: 'Priority boost',
          hint: _priorityBoostHint,
          value: s.priorityBoost.toDouble(),
          min: 0,
          max: 3,
          onChanged: (v) => change(() => s.priorityBoost = v.round()),
        ),

        const Section('labelStyle', note: 'The default style of the labels.'),
        LabelStyleEditor(
          style: s.style,
          onChanged: change,
          spacingHint: 'Not used by polygon labels.',
        ),

        const Section(
          'labelStyleCallback',
          note: 'The style of single polygons, decided from their data.',
        ),
        ParamSwitch(
          name: 'Larger countries: larger text',
          value: s.scaleByArea,
          onChanged: (v) => change(() => s.scaleByArea = v),
        ),
        ParamChoice<int>(
          name: 'LabelStyle.hidden() below',
          hint: 'Countries with fewer people get no label.',
          value: s.hideLabelsBelow,
          options: const {
            0: 'off',
            1000000: '1M',
            10000000: '10M',
            50000000: '50M',
          },
          onChanged: (v) => change(() => s.hideLabelsBelow = v),
        ),

        const Section('Polygons', note: 'A new list, then invalidate().'),
        ParamSwitch(
          name: 'Upper case names',
          value: s.upperCase,
          onChanged: (v) => change(() => s.upperCase = v),
        ),
        ParamSlider(
          name: 'Fill opacity',
          value: s.fillOpacity,
          min: 0,
          max: 1,
          step: .1,
          digits: 1,
          onChanged: (v) => change(() => s.fillOpacity = v),
        ),
        ParamChoice<LabelKind>(
          name: 'Label',
          hint: 'Widget labels are not affected by the label style.',
          value: s.labelKind,
          options: const {
            .text: 'LabeledPolygon()',
            .widget: 'LabeledPolygon.widget()',
          },
          onChanged: (v) => change(() => s.labelKind = v),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ controller ---

class _SolverTab extends StatelessWidget {
  const new(this.settings);

  final DemoSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings.solver;
    final change = settings.change;
    return _TabBody(
      title: 'LabelCollisionController',
      subtitle:
          'Shared by the three layers. Its parameters are final, so the demo '
          'creates a new controller when one of them changes.',
      onReset: () => change(() => settings.solver = SolverSettings()),
      children: [
        const Section(
          'Recalculation',
          note:
              'The labels are placed again when the camera moved past one '
              'of the thresholds. Between two recalculations they only '
              'follow their items. Use the buttons on the map to move in '
              'fixed steps.',
        ),
        ParamSlider(
          name: 'moveThreshold',
          hint: 'Pan distance in screen pixels. Keep it below the buffer.',
          value: s.moveThreshold,
          min: 16,
          max: 1024,
          step: 16,
          unit: ' px',
          onChanged: (v) => change(() => s.moveThreshold = v),
        ),
        ParamSlider(
          name: 'zoomThreshold',
          hint: 'Zoom level difference.',
          value: s.zoomThreshold,
          min: .05,
          max: 3,
          step: .05,
          digits: 2,
          onChanged: (v) => change(() => s.zoomThreshold = v),
        ),
        ParamSlider(
          name: 'rotationThreshold',
          hint: 'Rotation difference in degrees.',
          value: s.rotationThreshold,
          min: 1,
          max: 90,
          unit: '°',
          onChanged: (v) => change(() => s.rotationThreshold = v),
        ),

        const Section('Solved area'),
        ParamSlider(
          name: 'bufferFactor',
          hint:
              'Extra area around the viewport that is solved too, as a '
              'fraction of its size. With 0 the labels pop in at the edges.',
          value: s.bufferFactor,
          min: 0,
          max: 2,
          step: .1,
          digits: 1,
          onChanged: (v) => change(() => s.bufferFactor = v),
        ),
        ParamSlider(
          name: 'cellSize',
          hint:
              'The cell size of the spatial grid in pixels. It only affects '
              'the speed: keep it near the typical marker and label size.',
          value: s.cellSize,
          min: 8,
          max: 512,
          step: 8,
          unit: ' px',
          onChanged: (v) => change(() => s.cellSize = v),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- map ---

class _MapTab extends StatelessWidget {
  const new(this.settings);

  final DemoSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings.map;
    final change = settings.change;
    return _TabBody(
      title: 'Map',
      subtitle: 'Settings of the demo, not of the package.',
      onReset: () => change(() {
        settings.map = MapSettings();
        settings.countries.fillOpacity = 1;
      }),
      children: [
        const Section('Base map'),
        ParamSwitch(
          name: 'OpenStreetMap tiles',
          hint:
              'Below the layers of the demo. The countries become '
              'translucent, so the tiles can be seen.',
          value: s.showTiles,
          onChanged: (v) => change(() {
            s.showTiles = v;
            settings.countries.fillOpacity = v ? .3 : 1;
          }),
        ),
        const Section('Gestures'),
        ParamSwitch(
          name: 'Rotate with gestures',
          hint:
              'With two fingers, or by dragging with the Ctrl key pressed. '
              'The buttons on the map always work.',
          value: s.rotateGesture,
          onChanged: (v) => change(() => s.rotateGesture = v),
        ),
      ],
    );
  }
}
