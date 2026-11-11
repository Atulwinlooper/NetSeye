import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';
import 'package:netseye/features/home/home_screen.dart';

import 'support.dart';

/// A TV remote must always show where focus is: the focused control gets
/// a sodium outline.
Finder _outlined() => find.byWidgetPredicate((w) {
  if (w is! DecoratedBox || w.position != DecorationPosition.foreground) return false;
  final d = w.decoration;
  return d is BoxDecoration && d.border is Border && (d.border! as Border).top.color == Palette.accent;
});

void main() {
  testWidgets('remote arrows move a visible focus outline across camera tiles', (t) async {
    final store = await testStore();
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: HomeScreen(store: store, connect: false),
      ),
    );
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(_outlined(), findsOneWidget, reason: 'exactly one control shows focus after a remote key');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(_outlined(), findsOneWidget);
  });
}
