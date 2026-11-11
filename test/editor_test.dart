import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';
import 'package:netseye/features/settings/camera_editor.dart';
import 'package:netseye/features/settings/settings_screen.dart';

import 'support.dart';

Widget _app(Widget home) => MaterialApp(theme: buildTheme(), home: home);

void main() {
  testWidgets('editor refuses a bad address and keeps the camera unchanged', (tester) async {
    final store = await testStore();
    await tester.pumpWidget(_app(CameraEditor(store: store, camera: store.cameras.first)));

    await tester.enterText(find.widgetWithText(TextFormField, 'Camera address'), 'not an address!');
    await tester.tap(find.bySemanticsLabel('Save camera'));
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't look like an address"), findsOneWidget);
    expect(store.cameras.first.host, '192.168.1.33');
  });

  testWidgets('editor saves a rename', (tester) async {
    final store = await testStore();
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CameraEditor(store: store, camera: store.cameras[2]),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Terrace cam');
    await tester.tap(find.bySemanticsLabel('Save camera'));
    await tester.pumpAndSettle();

    expect(store.byId('cam57')!.name, 'Terrace cam');
    expect(find.byType(CameraEditor), findsNothing, reason: 'editor closes after saving');
  });

  testWidgets('Save stays on screen while scrolling the form', (tester) async {
    final store = await testStore();
    await tester.pumpWidget(_app(CameraEditor(store: store, camera: store.cameras.first)));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Save camera').hitTestable(), findsOneWidget);
  });

  testWidgets('settings rejects a malformed hub address', (tester) async {
    final store = await testStore();
    await tester.pumpWidget(_app(SettingsScreen(store: store)));
    final hub = find.widgetWithText(TextField, 'Hub address');
    await tester.scrollUntilVisible(hub, 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(hub, 'my hub');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.hub, isEmpty);
    expect(find.textContaining("doesn't look like an address"), findsOneWidget);
  });
}
