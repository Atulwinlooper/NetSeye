import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which network this device is on: "Wi-Fi · Home_5G", or the device's
/// own address when Android won't share the Wi-Fi name.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();
  static final instance = NetworkStatus._();

  static const _channel = MethodChannel('netseye/device');
  static const _askedKey = 'asked.location.v1';

  String type = 'unknown'; // wifi | ethernet | none | other | unknown
  String? ssid;
  String? address; // this device's LAN address, e.g. 192.168.1.40
  Timer? _timer;

  /// One line for the UI.
  String get summary {
    final where = switch (type) {
      'wifi' => ssid != null ? 'Wi-Fi · $ssid' : 'Wi-Fi',
      'ethernet' => 'Ethernet',
      'none' => 'No network',
      _ => 'Home network',
    };
    return ssid == null && address != null && type != 'none' ? '$where · $address' : where;
  }

  bool get connected => type == 'wifi' || type == 'ethernet' || type == 'other';

  /// Start watching. Asks once (ever) for the permission Android requires
  /// before it will tell an app the Wi-Fi name.
  Future<void> start() async {
    await refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    try {
      final prefs = await SharedPreferences.getInstance();
      if (type == 'wifi' && ssid == null && !(prefs.getBool(_askedKey) ?? false)) {
        await prefs.setBool(_askedKey, true);
        await _channel.invokeMethod<bool>('askLocation');
        await refresh();
      }
    } on Exception {
      // Not Android (tests, desktop): the address alone is fine.
    }
  }

  Future<void> refresh() async {
    var changed = false;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('network');
      final t = m?['type'] as String? ?? 'unknown';
      final s = m?['ssid'] as String?;
      changed = t != type || s != ssid;
      type = t;
      ssid = s;
    } on Exception {
      // Not Android (tests, desktop): leave as unknown.
    }
    final a = await _lanAddress();
    if (a != address) {
      address = a;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  static Future<String?> _lanAddress() async {
    try {
      final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? fallback;
      for (final i in all) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (a.isLoopback) continue;
          final private = ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.');
          if (!private) continue;
          if (i.name.startsWith('wlan') || i.name.startsWith('eth')) return ip;
          fallback ??= ip;
        }
      }
      return fallback;
    } on Exception {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
