import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';
import 'package:netseye/data/camera_store.dart';
import 'package:netseye/data/defaults.dart';
import 'package:netseye/features/home/home_screen.dart';
import 'package:netseye/widgets/remote_keyboard.dart';

import 'support.dart';

/// The camera password is never part of the app: a fresh device asks for
/// it once and keeps it in the encrypted vault.
void main() {
  final noPassword = [for (final c in sampleCameras) c.copyWith(onvifPassword: '', mainUrl: '', subUrl: '')];

  test('built-in cameras carry no password', () {
    for (final c in defaultCameras()) {
      expect(c.onvifPassword, isEmpty);
    }
  });

  test('a fresh device needs the password; a set-up one does not', () async {
    expect((await testStore(cameras: noPassword)).needsPassword, isTrue);
    expect((await testStore()).needsPassword, isFalse);
  });

  test('saving the password stores it in the encrypted vault only', () async {
    final vault = MemoryVault();
    final store = await testStore(cameras: noPassword, vault: vault);
    // No camera to check against here, so save without verifying.
    expect(await store.setPassword('pa55', force: true), isTrue);
    expect(store.needsPassword, isFalse);
    expect(store.cameras.every((c) => c.onvifPassword == 'pa55'), isTrue);
    expect(await vault.read('cameras.v1'), contains('pa55'));
    // Reloading from the vault keeps it.
    final again = await CameraStore.load(vault: vault);
    expect(again.needsPassword, isFalse);
  });

  testWidgets('home shows the password screen until it is entered', (t) async {
    final store = await testStore(cameras: noPassword);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: HomeScreen(store: store, connect: false),
      ),
    );
    await t.pump();
    expect(find.text('Camera password'), findsOneWidget);
    await store.setPassword('pa55', force: true);
    await t.pump();
    expect(find.text('Camera password'), findsNothing);
  });

  testWidgets('remote keyboard also takes typed characters', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => RemoteEntry.open(context, c, label: 'Camera password'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'Z');
    await t.sendKeyEvent(LogicalKeyboardKey.digit7, character: '7');
    await t.sendKeyEvent(LogicalKeyboardKey.digit2, physicalKey: PhysicalKeyboardKey.digit2, character: '@');
    await t.pump();
    expect(find.textContaining('Z7@'), findsOneWidget);
  });
}
