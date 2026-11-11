@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/app/theme.dart';

/// Renders the Android TV launcher banner (320x180 dp, xhdpi) from the
/// app's own fonts and palette. Regenerate with:
///   flutter test --tags visual --run-skipped --update-goldens test/tv_banner_test.dart
void main() {
  setUpAll(() async {
    Future<void> load(String family, List<String> files) async {
      final l = FontLoader(family);
      for (final f in files) {
        l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
      }
      await l.load();
    }

    await load('Inter', ['assets/fonts/InterVariable.ttf']);
    await load('PlexMono', ['assets/fonts/IBMPlexMono-Regular.ttf']);
  });

  testWidgets('tv banner', (t) async {
    t.view.physicalSize = const Size(640, 360);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Palette.ink,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                const _Lens(),
                const SizedBox(width: 22),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NetSeye', style: Typo.display(40)),
                    const SizedBox(height: 6),
                    Text('HOME CAMERAS', style: Typo.label(color: Palette.ash, size: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(ColoredBox).first,
      matchesGoldenFile('../android/app/src/main/res/drawable-xhdpi/tv_banner.png'),
    );
  });
}

/// The app mark: an open lens in system blue.
class _Lens extends StatelessWidget {
  const _Lens();
  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Palette.accent, width: 4),
    ),
    alignment: Alignment.center,
    child: Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
      alignment: const Alignment(0.45, -0.45),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.ink),
      ),
    ),
  );
}
