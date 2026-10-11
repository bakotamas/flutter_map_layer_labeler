// Builds the compact data files of the demo (assets/data/*.json) from
// Natural Earth (https://www.naturalearthdata.com, public domain).
//
// Run it from the example directory:
//
//     dart run tool/build_data.dart
//
// The downloaded GeoJSON files are cached in .dart_tool/natural_earth.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _source =
    'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson';
const _cacheDir = '.dart_tool/natural_earth';
const _outDir = 'assets/data';

/// Coordinates are stored as integers: degrees multiplied by this.
const _scale = 1000;

/// Cities below this population are left out (capitals are always kept).
const _minCityPopulation = 100000;

/// Rivers with a higher scale rank (less important ones) are left out.
const _maxRiverRank = 8;

/// Douglas–Peucker tolerance of the rivers, in scaled units.
const _riverTolerance = 4.0;

/// Parts of a country smaller than this (in scaled units, both ways) are left
/// out, unless they are the largest part of the country.
const _minPartExtent = 60;

typedef _Pt = (int, int);

Future<void> main() async {
  Directory(_outDir).createSync(recursive: true);

  final cities = _cities(await _load('ne_10m_populated_places_simple'));
  _write('cities.json', cities);

  final rivers = _rivers(await _load('ne_10m_rivers_lake_centerlines'));
  _write('rivers.json', rivers);

  final countries = _countries(await _load('ne_50m_admin_0_countries'));
  _write('countries.json', countries);
}

Future<List<Map<String, dynamic>>> _load(String name) async {
  final file = File('$_cacheDir/$name.geojson');
  if (!file.existsSync()) {
    stdout.writeln('Downloading $name ...');
    file.parent.createSync(recursive: true);
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$_source/$name.geojson'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $name');
    }
    await response.pipe(file.openWrite());
    client.close();
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json['features'] as List).cast<Map<String, dynamic>>();
}

void _write(String name, Object data) {
  final file = File('$_outDir/$name')..writeAsStringSync(jsonEncode(data));
  final count = data is List ? data.length : 1;
  stdout.writeln(
    '$name: $count items, ${(file.lengthSync() / 1024).round()} kB',
  );
}

_Pt _pt(List<dynamic> c) => (
  ((c[0] as num) * _scale).round(),
  ((c[1] as num) * _scale).round(),
);

/// Scales the coordinates and drops the repeated points.
List<_Pt> _line(List<dynamic> coordinates) {
  final out = <_Pt>[];
  for (final c in coordinates) {
    final p = _pt(c as List);
    if (out.isEmpty || out.last != p) out.add(p);
  }
  return out;
}

/// Flat list of the points: the first one as it is, the others as the
/// difference from the previous point.
List<int> _encode(List<_Pt> points) {
  final out = <int>[];
  var px = 0, py = 0;
  for (final (x, y) in points) {
    out
      ..add(x - px)
      ..add(y - py);
    px = x;
    py = y;
  }
  return out;
}

// ---------------------------------------------------------------- cities ---

/// `[name, longitude, latitude, population, capital (0/1)]`, the largest first.
List<List<Object>> _cities(List<Map<String, dynamic>> features) {
  final out = <List<Object>>[];
  for (final f in features) {
    final p = f['properties'] as Map<String, dynamic>;
    final population = (p['pop_max'] as num?)?.round() ?? 0;
    final capital = p['adm0cap'] == 1;
    if (population < _minCityPopulation && !capital) continue;
    final c = (f['geometry'] as Map)['coordinates'] as List;
    out.add([
      p['name'] as String,
      double.parse((c[0] as num).toStringAsFixed(4)),
      double.parse((c[1] as num).toStringAsFixed(4)),
      population,
      capital ? 1 : 0,
    ]);
  }
  out.sort((a, b) => (b[3] as int).compareTo(a[3] as int));
  return out;
}

// ---------------------------------------------------------------- rivers ---

/// `{n: name, r: scale rank (0 is the most important), p: points}`.
///
/// The parts of a river (also the ones of other features with the same name)
/// are joined into as long lines as possible, so a river is labeled as a whole.
List<Map<String, Object>> _rivers(List<Map<String, dynamic>> features) {
  final groups = <String, List<(int, List<_Pt>)>>{};
  var unnamed = 0;
  for (final f in features) {
    final p = f['properties'] as Map<String, dynamic>;
    final name = (p['name_en'] ?? p['name'] ?? '') as String;
    final rank = (p['scalerank'] as num).round();
    if (rank > _maxRiverRank) continue;
    final g = f['geometry'] as Map<String, dynamic>;
    final parts = g['type'] == 'LineString'
        ? [g['coordinates'] as List]
        : (g['coordinates'] as List).cast<List<dynamic>>();
    // Unnamed rivers are not joined with each other.
    final key = name.isEmpty ? '#${unnamed++}' : name;
    for (final part in parts) {
      final line = _line(part);
      if (line.length >= 2) (groups[key] ??= []).add((rank, line));
    }
  }

  final out = <Map<String, Object>>[];
  var before = 0, after = 0;
  groups.forEach((key, parts) {
    for (final (rank, line) in _join(parts)) {
      before += line.length;
      final simple = _simplify(line, _riverTolerance);
      after += simple.length;
      out.add({
        'n': key.startsWith('#') ? '' : key,
        'r': rank,
        'p': _encode(simple),
      });
    }
  });
  out.sort((a, b) => (a['r']! as int).compareTo(b['r']! as int));
  stdout.writeln('rivers: $before points simplified to $after');
  return out;
}

/// Joins the lines that continue each other. The rank of a joined line is the
/// best (lowest) one of its parts.
List<(int, List<_Pt>)> _join(List<(int, List<_Pt>)> parts) {
  final chains = [for (final (r, l) in parts) (r, [...l])];
  var merged = true;
  while (merged) {
    merged = false;
    outer:
    for (var i = 0; i < chains.length; i++) {
      for (var j = 0; j < chains.length; j++) {
        if (i == j) continue;
        final (ra, a) = chains[i];
        final (rb, b) = chains[j];
        List<_Pt>? joined;
        if (a.last == b.first) {
          joined = [...a, ...b.skip(1)];
        } else if (a.last == b.last) {
          joined = [...a, ...b.reversed.skip(1)];
        } else if (a.first == b.first) {
          joined = [...a.reversed, ...b.skip(1)];
        }
        if (joined == null) continue;
        chains[i] = (math.min(ra, rb), joined);
        chains.removeAt(j);
        merged = true;
        break outer;
      }
    }
  }
  return chains;
}

/// Douglas–Peucker simplification.
List<_Pt> _simplify(List<_Pt> points, double tolerance) {
  if (points.length < 3) return points;
  final keep = List.filled(points.length, false)
    ..first = true
    ..last = true;
  final stack = [(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (from, to) = stack.removeLast();
    var worst = 0.0, index = -1;
    for (var i = from + 1; i < to; i++) {
      final d = _distance(points[i], points[from], points[to]);
      if (d > worst) {
        worst = d;
        index = i;
      }
    }
    if (index < 0 || worst <= tolerance) continue;
    keep[index] = true;
    stack
      ..add((from, index))
      ..add((index, to));
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

/// The distance of [p] from the segment [a]-[b].
double _distance(_Pt p, _Pt a, _Pt b) {
  final dx = (b.$1 - a.$1).toDouble(), dy = (b.$2 - a.$2).toDouble();
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final x = a.$1 + t * dx - p.$1, y = a.$2 + t * dy - p.$2;
  return math.sqrt(x * x + y * y);
}

// ------------------------------------------------------------- countries ---

/// `{n: name, c: continent, pop: population, a: area (km²), col: map color
/// (1-7), g: parts}`. A part is a list of rings (the outer one, then the
/// holes), the largest part of the country is the first one.
List<Map<String, Object>> _countries(List<Map<String, dynamic>> features) {
  final out = <Map<String, Object>>[];
  var points = 0;
  for (final f in features) {
    final p = f['properties'] as Map<String, dynamic>;
    final g = f['geometry'] as Map<String, dynamic>;
    final polygons = g['type'] == 'Polygon'
        ? [g['coordinates'] as List]
        : (g['coordinates'] as List).cast<List<dynamic>>();

    final parts = <(double, List<List<_Pt>>)>[];
    for (final polygon in polygons) {
      final rings = [
        for (final ring in polygon)
          if (_line(ring as List) case final r when r.length >= 4) r,
      ];
      if (rings.isEmpty) continue;
      parts.add((_areaKm2(rings.first), rings));
    }
    if (parts.isEmpty) continue;
    parts.sort((a, b) => b.$1.compareTo(a.$1));

    final kept = [
      for (final (i, (_, rings)) in parts.indexed)
        if (i == 0 || !_isTiny(rings.first)) rings,
    ];
    for (final rings in kept) {
      for (final ring in rings) {
        points += ring.length;
      }
    }
    out.add({
      'n': p['NAME'] as String,
      'c': p['CONTINENT'] as String,
      'pop': (p['POP_EST'] as num).round(),
      'a': parts.fold(0.0, (sum, part) => sum + part.$1).round(),
      'col': (p['MAPCOLOR7'] as num).round(),
      'g': [
        for (final rings in kept) [for (final ring in rings) _encode(ring)],
      ],
    });
  }
  out.sort((a, b) => (a['n']! as String).compareTo(b['n']! as String));
  stdout.writeln('countries: $points points');
  return out;
}

bool _isTiny(List<_Pt> ring) {
  var minX = ring.first.$1, maxX = minX, minY = ring.first.$2, maxY = minY;
  for (final (x, y) in ring) {
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  return maxX - minX < _minPartExtent && maxY - minY < _minPartExtent;
}

/// The area of a ring on the sphere, in km².
double _areaKm2(List<_Pt> ring) {
  const radius = 6371.0088;
  double rad(int v) => v / _scale * math.pi / 180;
  var sum = 0.0;
  for (var i = 0; i + 1 < ring.length; i++) {
    final (x1, y1) = ring[i];
    final (x2, y2) = ring[i + 1];
    sum += (rad(x2) - rad(x1)) * (2 + math.sin(rad(y1)) + math.sin(rad(y2)));
  }
  return (sum * radius * radius / 2).abs();
}
