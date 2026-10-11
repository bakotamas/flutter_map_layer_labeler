import 'package:flutter/material.dart';
import 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';

/// Which constructor of [TextLabelHalo] is used.
enum HaloMode { standard, none, custom }

/// The [LabelStyle.decoration] of the demo.
enum BoxMode { none, filled, outlined }

/// Text labels or widget labels (the `.widget` constructors).
enum LabelKind { text, widget }

enum CityPriority { population, capitalsFirst, none }

enum RiverPriority { importance, none }

enum CountryPriority { population, area, none }

/// The editable fields of a [LabelStyle].
class LabelStyleSettings {
  new({
    this.fontSize = 12,
    this.bold = false,
    this.italic = false,
    this.color = const Color(0xFF212121),
    this.letterSpacing = 0,
    this.paddingH = 4,
    this.paddingV = 2,
    this.spacing = 2,
    this.halo = .standard,
    this.haloColor = const Color(0xFFFFFFFF),
    this.haloWidth = 3,
    this.box = .none,
    this.boxColor = const Color(0xFFFFFFFF),
    this.boxRadius = 4,
  });

  double fontSize;
  bool bold;
  bool italic;
  Color color;
  double letterSpacing;
  double paddingH;
  double paddingV;
  double spacing;
  HaloMode halo;
  Color haloColor;
  double haloWidth;
  BoxMode box;
  Color boxColor;
  double boxRadius;

  LabelStyle build() => LabelStyle(
    TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      letterSpacing: letterSpacing,
    ),
    padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
    halo: switch (halo) {
      .standard => const TextLabelHalo(),
      .none => const TextLabelHalo.zero(),
      .custom => TextLabelHalo.custom(color: haloColor, width: haloWidth),
    },
    decoration: switch (box) {
      .none => null,
      .filled => BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(boxRadius),
      ),
      .outlined => BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(boxRadius),
        border: Border.all(color: color),
      ),
    },
    spacing: spacing,
  );
}

/// The settings of the [LabeledMarkerLayer] of the cities.
class CitySettings {
  bool visible = true;
  bool displayLabels = true;
  CityPriority priority = .population;

  /// Added to the priority of every city: the priorities are compared across
  /// all layers of the controller.
  int priorityBoost = 2;

  /// All sides in the order they are tried, and the ones that are used.
  List<LabelSide> sideOrder = [.right, .left, .bottom, .top];
  Set<LabelSide> enabledSides = {.right, .left, .bottom, .top};

  double? minZoomForLabels;
  double? maxZoomForLabels;
  bool alwaysShowAllMarkers = false;
  int fadeMs = 200;
  final style = LabelStyleSettings();

  // Label style callback.
  bool emphasizeCapitals = true;
  int hideLabelsBelow = 0;

  // Markers.
  int minPopulation = 100000;
  double markerSize = 10;
  bool counterRotate = true;
  LabelKind labelKind = .text;
  bool widgetLabelsTappable = true;
  double widgetSpacing = 4;

  List<LabelSide> get sides => [
    for (final side in sideOrder)
      if (enabledSides.contains(side)) side,
  ];

  /// Changes when the list of the markers has to be built again.
  Object get dataKey => (
    minPopulation,
    markerSize,
    counterRotate,
    labelKind,
    widgetLabelsTappable,
    widgetSpacing,
  );
}

/// The settings of the [LabeledPolylineLayer] of the rivers.
class RiverSettings {
  bool visible = true;
  bool displayLabels = true;
  RiverPriority priority = .importance;
  int priorityBoost = 0;

  LabelAlignment labelAlignment = .aboveLine;
  double? labelRepeat = .8;
  int maxLabelsPerLine = 8;
  bool rotateLabels = true;
  bool followLine = true;
  double cornerRadius = 2;
  bool hideLabelIfLongerThanLine = true;
  double simplificationTolerance = 10;
  int simplificationMinPoints = 300;
  int fadeMs = 200;
  final style = LabelStyleSettings(
    italic: true,
    color: const Color(0xFF1565C0),
    letterSpacing: .5,
    paddingH: 2,
    paddingV: 0,
    spacing: 1,
  );

  // Label style callback.
  bool emphasizeMajor = true;
  int hideLabelsAboveRank = 8;

  // Polylines.
  int maxRank = 7;
  double strokeWidth = 1.5;
  LabelKind labelKind = .text;
  double widgetSpacing = 2;

  /// Changes when the list of the polylines has to be built again.
  Object get dataKey => (maxRank, strokeWidth, labelKind, widgetSpacing);
}

/// The settings of the [LabeledPolygonLayer] of the countries.
class CountrySettings {
  bool visible = true;
  bool displayLabels = true;
  CountryPriority priority = .population;
  int priorityBoost = 1;

  PolygonLabelAnchor labelAnchor = .centroid;
  bool hideLabelIfLargerThanPolygon = true;
  int fadeMs = 200;
  final style = LabelStyleSettings(
    fontSize: 11,
    bold: true,
    color: const Color(0xFF6D5A72),
    letterSpacing: 1.5,
  );

  // Label style callback.
  bool scaleByArea = true;
  int hideLabelsBelow = 0;

  // Polygons.
  bool upperCase = true;
  double fillOpacity = 1;
  LabelKind labelKind = .text;

  /// Changes when the list of the polygons has to be built again.
  Object get dataKey => (upperCase, fillOpacity, labelKind);
}

/// The parameters of the [LabelCollisionController].
class SolverSettings {
  double bufferFactor = .5;
  double moveThreshold = 128;
  double zoomThreshold = .5;
  double rotationThreshold = 15;
  double cellSize = 64;

  /// Changes when a new controller is needed: its parameters are final.
  Object get key => (
    bufferFactor,
    moveThreshold,
    zoomThreshold,
    rotationThreshold,
    cellSize,
  );

  LabelCollisionController build() => LabelCollisionController(
    bufferFactor: bufferFactor,
    moveThreshold: moveThreshold,
    zoomThreshold: zoomThreshold,
    rotationThreshold: rotationThreshold,
    cellSize: cellSize,
  );
}

class MapSettings {
  /// OpenStreetMap tiles below the layers of the demo.
  bool showTiles = false;

  /// Whether the map can be rotated with gestures.
  bool rotateGesture = true;
}

/// Everything that can be changed on the settings panel.
class DemoSettings extends ChangeNotifier {
  var cities = CitySettings();
  var rivers = RiverSettings();
  var countries = CountrySettings();
  var solver = SolverSettings();
  var map = MapSettings();

  /// Runs [update], then tells the map and the panel to rebuild.
  void change(VoidCallback update) {
    update();
    notifyListeners();
  }
}
