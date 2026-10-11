import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/gis_data.dart';
import 'map/demo_map.dart';
import 'panel/settings_panel.dart';
import 'settings.dart';

const _repository = 'https://github.com/bakotamas/flutter_map_layer_labeler';

/// The width of the settings panel, and the window width above which it is
/// shown next to the map instead of in a drawer.
const _panelWidth = 400.0;
const _wideLayout = 960.0;

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const new({this.data, super.key});

  /// The data to show. If null, it is loaded from the assets.
  final GisData? data;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_map_layer_labeler demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B6CB0)),
      ),
      home: DemoPage(data: data),
    );
  }
}

class DemoPage extends StatefulWidget {
  const new({this.data, super.key});

  final GisData? data;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _settings = DemoSettings();
  final _mapController = MapController();
  late final Future<GisData> _data = widget.data != null
      ? Future.value(widget.data)
      : GisData.load(rootBundle);

  @override
  void dispose() {
    _mapController.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideLayout;
    return FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final panel = data == null
            ? null
            : SettingsPanel(settings: _settings, data: data);
        return Scaffold(
          appBar: AppBar(
            title: const Text('flutter_map_layer_labeler'),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            actions: [
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(_repository)),
                icon: const Icon(Icons.code, size: 18),
                label: const Text('GitHub'),
              ),
              if (!wide && panel != null)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.tune),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          endDrawer: wide || panel == null
              ? null
              : Drawer(
                  width: _panelWidth,
                  child: SafeArea(child: panel),
                ),
          // The map can be seen while the settings are changed.
          drawerScrimColor: Colors.transparent,
          body: switch (snapshot) {
            AsyncSnapshot(:final error?) => Center(
              child: Text('The data could not be loaded.\n$error'),
            ),
            AsyncSnapshot(data: null) => const Center(
              child: CircularProgressIndicator(),
            ),
            AsyncSnapshot(:final data?) => Row(
              children: [
                Expanded(
                  child: ClipRect(
                    child: DemoMap(
                      data: data,
                      settings: _settings,
                      mapController: _mapController,
                    ),
                  ),
                ),
                if (wide) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: _panelWidth, child: panel),
                ],
              ],
            ),
          },
        );
      },
    );
  }
}
