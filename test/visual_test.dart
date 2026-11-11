@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';
import 'package:netseye/features/home/home_screen.dart';
import 'package:netseye/features/settings/camera_editor.dart';
import 'package:netseye/features/settings/settings_screen.dart';
import 'package:netseye/widgets/glass.dart';
import 'package:netseye/widgets/remote_keyboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Renders screens to PNGs (test/goldens) so the design can be checked
/// without a phone. Excluded from normal runs (the header shows a live
/// clock). Run: flutter test --update-goldens --tags visual
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Inter', ['assets/fonts/InterVariable.ttf']);
  await load('PlexMono', ['assets/fonts/IBMPlexMono-Regular.ttf']);
  // Real icon glyphs instead of test boxes.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/Users/swati/Documents/flutter';
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester t, Widget page, Size size, String name) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = size * 3;
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 24 * 3.0, bottom: 16 * 3.0);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => Backdrop(child: child!),
        home: page,
      ),
    );
    await t.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('home phone', (t) async {
    final store = await testStore();
    await shoot(t, HomeScreen(store: store, connect: false), const Size(390, 844), 'home_phone');
  });

  testWidgets('home tablet', (t) async {
    final store = await testStore();
    await shoot(t, HomeScreen(store: store, connect: false), const Size(1194, 834), 'home_tablet');
  });

  testWidgets('home tv wall', (t) async {
    final store = await testStore();
    await shoot(t, HomeScreen(store: store, connect: false), const Size(1280, 720), 'home_tv');
  });

  testWidgets('tv keyboard', (t) async {
    await shoot(
      t,
      const RemoteKeyboard(
        label: 'Name',
        initial: 'Front door',
        capitalize: true,
        suggestions: [
          'Front door',
          'Hall',
          'Rooftop',
          'Gate',
          'Parking',
          'Living room',
          'Kitchen',
          'Backyard',
        ],
      ),
      const Size(1280, 720),
      'tv_keyboard',
    );
  });

  testWidgets('settings tv', (t) async {
    final store = await testStore();
    await shoot(t, SettingsScreen(store: store), const Size(1280, 720), 'settings_tv');
  });

  testWidgets('editor tv', (t) async {
    final store = await testStore();
    await shoot(t, CameraEditor(store: store, camera: store.cameras[2]), const Size(1280, 720), 'editor_tv');
  });

  testWidgets('settings', (t) async {
    final store = await testStore();
    await shoot(t, SettingsScreen(store: store), const Size(390, 844), 'settings');
  });

  testWidgets('editor', (t) async {
    final store = await testStore();
    await shoot(t, CameraEditor(store: store, camera: store.cameras[2]), const Size(390, 844), 'editor');
  });
}
