import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any screen asks for it.
///
/// Counted, so leaving the full-screen viewer doesn't switch it off while
/// the TV grid underneath still wants it. On a TV used as a camera monitor
/// that matters: without it Android TV starts its screen saver and then
/// sleeps after the idle timeout (2 hours on many sets), the app is sent to
/// the background, and on a low-memory TV the system soon closes it.
abstract final class ScreenAwake {
  static int _holds = 0;

  static void hold() {
    if (_holds++ == 0) _set(true);
  }

  static void release() {
    if (_holds == 0) return;
    if (--_holds == 0) _set(false);
  }

  @visibleForTesting
  static int get holds => _holds;

  static void _set(bool on) {
    // Not available in tests or on desktop: never let that matter.
    WakelockPlus.toggle(enable: on).catchError((Object _) {});
  }
}
