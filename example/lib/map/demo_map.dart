import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';
import 'package:latlong2/latlong.dart';

import '../data/gis_data.dart';
import '../settings.dart';
import 'label_widgets.dart';
import 'map_overlays.dart';

const _water = Color(0xFFC9DFF0);
const _border = Color(0xFFAFA59B);
const _riverColor = Color(0xFF5B9BD5);

/// The fill colors of the countries, by [Country.colorIndex].
const _land = [
  Color(0xFFF6E7C8),
  Color(0xFFE3EDCF),
  Color(0xFFF5D9CF),
  Color(0xFFE6DCEF),
  Color(0xFFFBF0B8),
  Color(0xFFD8ECE4),
  Color(0xFFF2D6E0),
];

/// The map of the demo: countries, rivers and cities, labeled by one shared
/// [LabelCollisionController].
class DemoMap extends StatefulWidget {
  const new({
    required this.data,
    required this.settings,
    required this.mapController,
    super.key,
  });

  final GisData data;
  final DemoSettings settings;
  final MapController mapController;

  @override
  State<DemoMap> createState() => _DemoMapState();
}

class _DemoMapState extends State<DemoMap> {
  LabelCollisionController? _controller;
  Object? _solverKey;

  // The item lists are cached: a label is only kept while its item is the
  // same instance the placement was calculated for.
  var _cities = <LabeledMarker<City>>[];
  var _rivers = <LabeledPolyline<River>>[];
  var _countries = <LabeledPolygon<Country>>[];
  Object? _cityKey, _riverKey, _countryKey;

  // The styles the style callbacks return, built once per settings change.
  late LabelStyle _capitalStyle, _majorRiverStyle;
  late LabelStyle _largeCountryStyle, _mediumCountryStyle;

  LabelCollisionController get _labels => _controller!;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _sync();
  }

  @override
  void didUpdateWidget(DemoMap old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      old.settings.removeListener(_onSettings);
      widget.settings.addListener(_onSettings);
    }
    if (old.settings != widget.settings || old.data != widget.data) {
      _cityKey = _riverKey = _countryKey = null;
      _sync();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _labels.dispose();
    super.dispose();
  }

  void _onSettings() => setState(_sync);

  /// Applies the settings to everything that is cached here.
  void _sync() {
    final s = widget.settings;

    // The parameters of the controller are final, so a change needs a new one.
    if (s.solver.key != _solverKey) {
      _solverKey = s.solver.key;
      _controller?.dispose();
      _controller = s.solver.build();
    }

    final city = s.cities.style;
    _capitalStyle = city.build().copyWith(
      textStyle: TextStyle(
        fontSize: city.fontSize + 2,
        fontWeight: FontWeight.w700,
        fontStyle: city.italic ? FontStyle.italic : FontStyle.normal,
        color: city.color,
        letterSpacing: city.letterSpacing,
      ),
    );
    final river = s.rivers.style;
    _majorRiverStyle = river.build().copyWith(
      textStyle: TextStyle(
        fontSize: river.fontSize + 2,
        fontWeight: FontWeight.w700,
        fontStyle: river.italic ? FontStyle.italic : FontStyle.normal,
        color: river.color,
        letterSpacing: river.letterSpacing,
      ),
    );
    final country = s.countries.style;
    LabelStyle larger(double by) => country.build().copyWith(
      textStyle: TextStyle(
        fontSize: country.fontSize + by,
        fontWeight: country.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: country.italic ? FontStyle.italic : FontStyle.normal,
        color: country.color,
        letterSpacing: country.letterSpacing + by / 2,
      ),
    );
    _largeCountryStyle = larger(5);
    _mediumCountryStyle = larger(2);

    if (s.cities.dataKey != _cityKey) {
      _cityKey = s.cities.dataKey;
      _cities = _buildCities();
    }
    if (s.rivers.dataKey != _riverKey) {
      _riverKey = s.rivers.dataKey;
      _rivers = _buildRivers();
    }
    if (s.countries.dataKey != _countryKey) {
      _countryKey = s.countries.dataKey;
      _countries = _buildCountries();
    }

    // The layers notice the changes of their own parameters, but not the
    // changes of the item lists and of the results of the priority and style
    // callbacks, so the controller has to be told about them.
    _labels.invalidate();
  }

  // ------------------------------------------------------------- cities ---

  List<LabeledMarker<City>> _buildCities() {
    final s = widget.settings.cities;
    // In alphabetical order, so the order of the list is a bad priority.
    final cities = [
      for (final c in widget.data.cities)
        if (c.population >= s.minPopulation) c,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final c in cities)
        if (_cityMarker(c, s) case final marker)
          switch (s.labelKind) {
            .text => LabeledMarker(marker: marker, labelText: c.name, data: c),
            .widget => LabeledMarker.widget(
              marker: marker,
              labelBuilder: (_, _) => CityChip(city: c, onTap: _showCity),
              labelSize: CityChip.sizeOf(c),
              ignorePointer: !s.widgetLabelsTappable,
              spacing: s.widgetSpacing,
              data: c,
            ),
          },
    ];
  }

  Marker _cityMarker(City c, CitySettings s) {
    final size = c.isCapital ? s.markerSize + 4 : s.markerSize;
    return Marker(
      point: c.point,
      width: size,
      height: size,
      rotate: s.counterRotate,
      child: CityMarker(city: c, size: size, onTap: _showCity),
    );
  }

  void _showCity(City c) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          width: 360,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            '${c.name}: ${groupedNumber(c.population)} people'
            '${c.isCapital ? ' (capital)' : ''}',
          ),
        ),
      );
  }

  // The callbacks are instance methods, so the layers get the same tear-offs
  // at every build. They are called for every item of the calculated area.

  double _cityPriority(LabeledMarker<City> m) {
    final s = widget.settings.cities;
    final c = m.data!;
    final size = _unit(c.population, 8);
    return s.priorityBoost +
        switch (s.priority) {
          .population => size,
          .capitalsFirst => (c.isCapital ? .5 : 0) + size / 2,
          .none => 0,
        };
  }

  LabelStyle? _cityStyle(LabeledMarker<City> m) {
    final s = widget.settings.cities;
    final c = m.data!;
    if (c.population < s.hideLabelsBelow) return const LabelStyle.hidden();
    return s.emphasizeCapitals && c.isCapital ? _capitalStyle : null;
  }

  // ------------------------------------------------------------- rivers ---

  List<LabeledPolyline<River>> _buildRivers() {
    final s = widget.settings.rivers;
    final rivers = [
      for (final r in widget.data.rivers)
        if (r.rank <= s.maxRank) r,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final r in rivers)
        if (Polyline(
              points: r.points,
              color: _riverColor,
              strokeWidth: s.strokeWidth * (r.rank <= 3 ? 1.6 : 1),
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            )
            case final line)
          if (s.labelKind == LabelKind.widget && r.name.isNotEmpty)
            LabeledPolyline.widget(
              polyline: line,
              labelBuilder: (_, _) => RiverTag(river: r),
              labelSize: RiverTag.sizeOf(r),
              ignorePointer: true,
              spacing: s.widgetSpacing,
              data: r,
            )
          else
            // An empty text is no label.
            LabeledPolyline(polyline: line, labelText: r.name, data: r),
    ];
  }

  double _riverPriority(LabeledPolyline<River> p) {
    final s = widget.settings.rivers;
    return s.priorityBoost +
        switch (s.priority) {
          .importance => (10 - p.data!.rank) / 11,
          .none => 0,
        };
  }

  LabelStyle? _riverStyle(LabeledPolyline<River> p) {
    final s = widget.settings.rivers;
    final r = p.data!;
    if (r.rank > s.hideLabelsAboveRank) return const LabelStyle.hidden();
    return s.emphasizeMajor && r.rank <= 3 ? _majorRiverStyle : null;
  }

  // ---------------------------------------------------------- countries ---

  List<LabeledPolygon<Country>> _buildCountries() {
    final s = widget.settings.countries;
    return [
      for (final c in widget.data.countries)
        for (final (i, part) in c.parts.indexed)
          if (Polygon(
                points: part.points,
                holePointsList: part.holes,
                color: _land[(c.colorIndex - 1) % _land.length].withValues(
                  alpha: s.fillOpacity,
                ),
                borderColor: _border,
                borderStrokeWidth: .8,
              )
              case final polygon)
            // Only the largest part of a country is labeled.
            if (i > 0)
              LabeledPolygon(polygon: polygon, labelText: '', data: c)
            else
              switch (s.labelKind) {
                .text => LabeledPolygon(
                  polygon: polygon,
                  labelText: s.upperCase ? c.name.toUpperCase() : c.name,
                  data: c,
                ),
                .widget => LabeledPolygon.widget(
                  polygon: polygon,
                  labelBuilder: (_, _) => CountryCard(country: c),
                  labelSize: CountryCard.sizeOf(c),
                  ignorePointer: true,
                  data: c,
                ),
              },
    ];
  }

  double _countryPriority(LabeledPolygon<Country> p) {
    final s = widget.settings.countries;
    final c = p.data!;
    return s.priorityBoost +
        switch (s.priority) {
          .population => _unit(c.population, 10),
          .area => _unit(c.areaKm2, 8),
          .none => 0,
        };
  }

  LabelStyle? _countryStyle(LabeledPolygon<Country> p) {
    final s = widget.settings.countries;
    final c = p.data!;
    if (c.population < s.hideLabelsBelow) return const LabelStyle.hidden();
    if (!s.scaleByArea) return null;
    if (c.areaKm2 > 2500000) return _largeCountryStyle;
    return c.areaKm2 > 300000 ? _mediumCountryStyle : null;
  }

  // ---------------------------------------------------------------- map ---

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: const LatLng(47.3, 14.5),
        initialZoom: 5.3,
        minZoom: 2,
        maxZoom: 12,
        backgroundColor: _water,
        // The labels are only drawn in the main world.
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(-85.05, -180),
            const LatLng(85.05, 180),
          ),
        ),
        interactionOptions: InteractionOptions(
          flags: s.map.rotateGesture
              ? InteractiveFlag.all
              : InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        if (s.map.showTiles)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName:
                'io.github.bakotamas.flutter_map_layer_labeler.example',
          ),
        if (s.countries.visible)
          LabeledPolygonLayer<Country>(
            controller: _labels,
            polygons: _countries,
            displayLabels: s.countries.displayLabels,
            priority: _countryPriority,
            labelStyle: s.countries.style.build(),
            labelStyleCallback: _countryStyle,
            labelAnchor: s.countries.labelAnchor,
            hideLabelIfLargerThanPolygon:
                s.countries.hideLabelIfLargerThanPolygon,
            labelFadeDuration: Duration(milliseconds: s.countries.fadeMs),
          ),
        if (s.rivers.visible)
          LabeledPolylineLayer<River>(
            controller: _labels,
            polylines: _rivers,
            displayLabels: s.rivers.displayLabels,
            priority: _riverPriority,
            labelStyle: s.rivers.style.build(),
            labelStyleCallback: _riverStyle,
            labelAlignment: s.rivers.labelAlignment,
            labelRepeat: s.rivers.labelRepeat,
            maxLabelsPerLine: s.rivers.maxLabelsPerLine,
            rotateLabels: s.rivers.rotateLabels,
            followLine: s.rivers.followLine,
            cornerRadius: s.rivers.cornerRadius,
            hideLabelIfLongerThanLine: s.rivers.hideLabelIfLongerThanLine,
            simplificationTolerance: s.rivers.simplificationTolerance,
            simplificationMinPoints: s.rivers.simplificationMinPoints,
            labelFadeDuration: Duration(milliseconds: s.rivers.fadeMs),
          ),
        if (s.cities.visible)
          LabeledMarkerLayer<City>(
            controller: _labels,
            markers: _cities,
            displayLabels: s.cities.displayLabels,
            priority: _cityPriority,
            labelStyle: s.cities.style.build(),
            labelStyleCallback: _cityStyle,
            sides: s.cities.sides,
            minZoomForLabels: s.cities.minZoomForLabels,
            maxZoomForLabels: s.cities.maxZoomForLabels,
            alwaysShowAllMarkers: s.cities.alwaysShowAllMarkers,
            labelFadeDuration: Duration(milliseconds: s.cities.fadeMs),
          ),
        const MapControls(),
        MapAttribution(showTiles: s.map.showTiles),
      ],
    );
  }
}

/// log10 of [value], scaled to 0-1 by [maxExponent].
double _unit(int value, int maxExponent) =>
    (math.log(value + 1) / math.ln10 / maxExponent).clamp(0, .999);
