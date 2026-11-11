import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';
import 'package:netseye/widgets/remote_keyboard.dart';

/// On a TV the name is typed with the remote alone: arrows + OK.
void main() {
  late TextEditingController c;

  Future<void> open(WidgetTester t, {List<String> suggestions = const []}) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    c = TextEditingController(text: 'Camera one');
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    RemoteEntry.open(context, c, label: 'Name', suggestions: suggestions, capitalize: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  /// Label of the key the remote is on.
  String focused() {
    final node = FocusManager.instance.primaryFocus;
    String? label;
    node?.context?.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Semantics && w.properties.label != null) {
        label = w.properties.label;
        return false;
      }
      return true;
    });
    return label ?? '(none: $node)';
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }

  /// Walk like a person would: down to the bottom row, then right to [label].
  Future<void> walkTo(WidgetTester t, String label) async {
    final path = <String>[focused()];
    for (var i = 0; i < 8 && focused() != label; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
      path.add(focused());
    }
    for (var i = 0; i < 10 && focused() != label; i++) {
      await press(t, LogicalKeyboardKey.arrowRight);
      path.add(focused());
    }
    expect(focused(), label, reason: 'remote path: ${path.join(' → ')}');
  }

  const ok = LogicalKeyboardKey.select;

  testWidgets('quick pick, then Done: renamed in a few presses', (t) async {
    await open(t, suggestions: ['Front door', 'Hall']);
    expect(focused(), 'Front door', reason: 'starts on the first quick pick');
    await press(t, ok);
    await walkTo(t, 'Done');
    await press(t, ok);
    expect(find.text('open'), findsOneWidget, reason: 'keyboard closed');
    expect(c.text, 'Front door');
  });

  testWidgets('typing letters with OK, first letter capitalised', (t) async {
    await open(t);
    expect(focused(), 'a');
    await walkTo(t, 'Clear');
    await press(t, ok);
    // Back up to the letters: "a" is top-left.
    for (var i = 0; i < 6; i++) {
      await press(t, LogicalKeyboardKey.arrowUp);
    }
    for (var i = 0; i < 12; i++) {
      await press(t, LogicalKeyboardKey.arrowLeft);
    }
    expect(focused(), 'A', reason: 'shift shows capitals at the start of a word');
    await press(t, ok); // A
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, ok); // b
    await walkTo(t, 'Done');
    await press(t, ok);
    expect(c.text, 'Ab');
  });

  testWidgets('Back cancels and keeps the old name', (t) async {
    await open(t);
    await press(t, ok);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(c.text, 'Camera one');
  });
}
