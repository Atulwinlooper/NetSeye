import 'package:flutter/services.dart';

/// What kind of device we're on. Loaded once at start-up.
abstract final class Device {
  static bool isTv = false;

  static Future<void> load() async {
    try {
      isTv = await const MethodChannel('netseye/device').invokeMethod<bool>('isTv') ?? false;
    } on Exception {
      isTv = false; // desktop, tests, older builds
    }
  }
}
