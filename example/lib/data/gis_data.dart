import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// Coordinates are stored as integers: degrees multiplied by this
/// (see tool/build_data.dart).
const _scale = 1000;

/// A populated place.
class City {
  const new({
    required this.name,
    required this.point,
    required this.population,
    required this.isCapital,
  });

  final String name;
  final LatLng point;
  final int population;

  /// Whether it is the capital of a country.
  final bool isCapital;
}

/// A river, or a part of it.
class River {
  const new({required this.name, required this.rank, required this.points});

  /// Empty if the river has no name.
  final String name;

  /// The scale rank of Natural Earth: 0 is the most important.
  final int rank;

  final List<LatLng> points;
}

/// One polygon of a country: the mainland or an island.
class CountryPart {
  const new(this.points, this.holes);

  final List<LatLng> points;
  final List<List<LatLng>> holes;
}

class Country {
  const new({
    required this.name,
    required this.continent,
    required this.population,
    required this.areaKm2,
    required this.colorIndex,
    required this.parts,
  });

  final String name;
  final String continent;
  final int population;
  final int areaKm2;

  /// 1-7: neighbors have different values.
  final int colorIndex;

  /// The polygons of the country, the largest first.
  final List<CountryPart> parts;
}

/// The data of the demo, from Natural Earth (public domain).
class GisData {
  const new({
    required this.cities,
    required this.rivers,
    required this.countries,
  });

  /// Parses the files written by tool/build_data.dart.
  factory fromJson({
    required String cities,
    required String rivers,
    required String countries,
  }) => GisData(
    cities: [
      for (final c in (jsonDecode(cities) as List).cast<List<dynamic>>())
        City(
          name: c[0] as String,
          point: LatLng((c[2] as num).toDouble(), (c[1] as num).toDouble()),
          population: (c[3] as num).toInt(),
          isCapital: c[4] == 1,
        ),
    ],
    rivers: [
      for (final r
          in (jsonDecode(rivers) as List).cast<Map<String, dynamic>>())
        River(
          name: r['n'] as String,
          rank: (r['r'] as num).toInt(),
          points: _decode(r['p'] as List),
        ),
    ],
    countries: [
      for (final c
          in (jsonDecode(countries) as List).cast<Map<String, dynamic>>())
        Country(
          name: c['n'] as String,
          continent: c['c'] as String,
          population: (c['pop'] as num).toInt(),
          areaKm2: (c['a'] as num).toInt(),
          colorIndex: (c['col'] as num).toInt(),
          parts: [
            for (final rings in (c['g'] as List).cast<List<dynamic>>())
              CountryPart(_decode(rings.first as List), [
                for (final hole in rings.skip(1)) _decode(hole as List),
              ]),
          ],
        ),
    ],
  );

  static Future<GisData> load(AssetBundle bundle) async {
    final [cities, rivers, countries] = await Future.wait([
      for (final name in const ['cities', 'rivers', 'countries'])
        bundle.loadString('assets/data/$name.json'),
    ]);
    return GisData.fromJson(
      cities: cities,
      rivers: rivers,
      countries: countries,
    );
  }

  final List<City> cities;
  final List<River> rivers;
  final List<Country> countries;
}

/// The points of a flat list: the first one as it is, the others as the
/// difference from the previous point.
List<LatLng> _decode(List<dynamic> deltas) {
  final out = <LatLng>[];
  var x = 0, y = 0;
  for (var i = 0; i + 1 < deltas.length; i += 2) {
    x += (deltas[i] as num).toInt();
    y += (deltas[i + 1] as num).toInt();
    out.add(LatLng(y / _scale, x / _scale));
  }
  return out;
}
