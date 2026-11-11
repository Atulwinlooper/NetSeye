import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../services/onvif.dart';

/// Turns a direction (from a drag on the picture, an arrow button or a TV
/// remote key) into pan/tilt commands. Directions snap to 8 ways and 2
/// speeds and repeats are rate-limited, so the camera isn't flooded.
class PtzDriver {
  PtzDriver(this.client);
  final OnvifClient client;

  Offset _sent = Offset.zero;
  DateTime _lastSend = DateTime(0);
  bool get moving => _sent != Offset.zero;

  /// [v] in screen terms: x right, y down; length 0..1 (1 = full speed).
  void drive(Offset v) {
    if (v.distance < 0.15) return;
    final angle = (math.atan2(v.dy, v.dx) / (math.pi / 4)).round() * (math.pi / 4);
    final speed = v.distance > 0.7 ? 1.0 : 0.5;
    final q = Offset(math.cos(angle) * speed, math.sin(angle) * speed);
    final now = DateTime.now();
    if ((q - _sent).distance < 0.05 && now.difference(_lastSend).inMilliseconds < 800) return;
    if (!moving) HapticFeedback.lightImpact();
    _sent = q;
    _lastSend = now;
    client.move(q.dx, -q.dy); // screen down = camera down
  }

  void stop() {
    if (!moving) return;
    _sent = Offset.zero;
    client.stop();
  }
}
