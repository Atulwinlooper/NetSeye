import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app/theme.dart';
import 'data/camera_store.dart';
import 'features/home/home_screen.dart';
import 'services/live_feed.dart';
import 'services/network_status.dart';
import 'widgets/glass.dart';
import 'services/device.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(systemChrome);
  final store = await CameraStore.load();
  await LiveFeed.loadMemory();
  await Device.load();
  _followInputForFocusOutlines();
  _perfLog();
  runApp(NetSeyeApp(store: store));
  // After the first frame, so the permission prompt (asked once) appears
  // over the app rather than before it.
  WidgetsBinding.instance.addPostFrameCallback((_) => NetworkStatus.instance.start());
}

class NetSeyeApp extends StatelessWidget {
  const NetSeyeApp({super.key, required this.store});
  final CameraStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetSeye',
      // The lit backdrop sits behind every page; pages themselves are glass.
      builder: (context, child) => Backdrop(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(store: store),
    );
  }
}

/// Measurement builds only (--dart-define=PEHRA_PERF=true): log real frame
/// costs every second, so smoothness is measured rather than guessed.
void _perfLog() {
  if (!const bool.fromEnvironment('PEHRA_PERF')) return;
  final build = <int>[], raster = <int>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
      if (t.totalSpan.inMicroseconds > 16700) {
        debugPrint(
          'FRAME slow build=${t.buildDuration.inMilliseconds} raster=${t.rasterDuration.inMilliseconds} '
          'total=${t.totalSpan.inMilliseconds}',
        );
      }
    }
  });
  Timer.periodic(const Duration(seconds: 1), (_) {
    if (build.isEmpty) return;
    String ms(Iterable<int> v) => (v.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(0);
    final slow = [
      for (var i = 0; i < build.length; i++)
        if (build[i] + raster[i] > 16700) i,
    ].length;
    debugPrint(
      'PERF frames=${build.length} slow=$slow '
      'buildAvg=${(build.reduce((a, b) => a + b) / build.length / 1000).toStringAsFixed(1)} buildMax=${ms(build)} '
      'rasterAvg=${(raster.reduce((a, b) => a + b) / raster.length / 1000).toStringAsFixed(1)} rasterMax=${ms(raster)}',
    );
    build.clear();
    raster.clear();
  });
}

/// Show focus outlines while a TV remote / keyboard is in use, hide them on
/// touch. (Flutter's automatic mode stays in "touch" on Android D-pads, so
/// a remote user could never see where focus is.)
void _followInputForFocusOutlines() {
  final fm = FocusManager.instance;
  HardwareKeyboard.instance.addHandler((e) {
    if (e is KeyDownEvent && fm.highlightStrategy != FocusHighlightStrategy.alwaysTraditional) {
      fm.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }
    return false; // never consume the key
  });
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent &&
        event.kind == PointerDeviceKind.touch &&
        fm.highlightStrategy != FocusHighlightStrategy.alwaysTouch) {
      fm.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    }
  });
}
