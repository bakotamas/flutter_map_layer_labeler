import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map_layer_labeler_example/data/gis_data.dart';
import 'package:flutter_map_layer_labeler_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

GisData _loadData() => GisData.fromJson(
  cities: File('assets/data/cities.json').readAsStringSync(),
  rivers: File('assets/data/rivers.json').readAsStringSync(),
  countries: File('assets/data/countries.json').readAsStringSync(),
);

Future<void> _pumpDemo(WidgetTester tester, GisData data) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(DemoApp(data: data));
  await tester.pumpAndSettle();
}

/// Scrolls the settings to [text], then taps it.
Future<void> _tapSetting(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  final data = _loadData();

  test('the data is complete', () {
    expect(data.cities.length, greaterThan(3000));
    expect(data.rivers.length, greaterThan(1000));
    expect(data.countries.length, greaterThan(200));
    final budapest = data.cities.singleWhere((c) => c.name == 'Budapest');
    expect(budapest.isCapital, isTrue);
    expect(budapest.point.latitude, closeTo(47.5, .1));
    final hungary = data.countries.singleWhere((c) => c.name == 'Hungary');
    expect(hungary.areaKm2, closeTo(93000, 2000));
  });

  testWidgets('the layers are labeled', (tester) async {
    await _pumpDemo(tester, data);

    expect(find.text('Budapest'), findsWidgets);
    expect(find.text('HUNGARY'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings change the labels', (tester) async {
    await _pumpDemo(tester, data);

    // A style callback result.
    await _tapSetting(tester, '5M');
    expect(find.text('Budapest'), findsNothing);
    expect(find.text('HUNGARY'), findsWidgets);

    // A new marker list with widget labels.
    await _tapSetting(tester, 'off');
    await _tapSetting(tester, 'LabeledMarker.widget()');
    expect(find.text('Budapest · 1.7M'), findsOneWidget);

    // Turning the labels of a layer off.
    await tester.tap(find.text('Polygons'));
    await tester.pumpAndSettle();
    await _tapSetting(tester, 'displayLabels');
    expect(find.text('HUNGARY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed controller parameter replaces the controller', (
    tester,
  ) async {
    await _pumpDemo(tester, data);

    await tester.tap(find.text('Controller'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(find.text('Budapest'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
