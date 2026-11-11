import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera.dart';
import '../services/onvif.dart';
import 'defaults.dart';

/// Where the camera list lives. It holds ONVIF passwords and private
/// stream paths, so on devices it is the Android Keystore-backed
/// secure storage; tests use [MemoryVault].
abstract interface class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureVault implements Vault {
  const SecureVault();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryVault implements Vault {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Holds the camera list and app settings, saved on the phone.
class CameraStore extends ChangeNotifier {
  CameraStore._(this._prefs, this._vault);

  static const _kCameras = 'cameras.v1';
  static const _kHub = 'hub.v1';

  final SharedPreferences _prefs;
  final Vault _vault;
  List<Camera> _cameras = const [];
  String _hub = '';

  List<Camera> get cameras => List.unmodifiable(_cameras);

  /// Optional always-on relay (e.g. "192.168.1.41"). Empty = connect
  /// straight to the cameras.
  String get hub => _hub;
  bool get usesHub => _hub.isNotEmpty;

  static Future<CameraStore> load({Vault vault = const SecureVault()}) async {
    final prefs = await SharedPreferences.getInstance();
    final store = CameraStore._(prefs, vault);

    var saved = await vault.read(_kCameras);
    // Move lists saved by the first version (plain prefs) into the vault.
    final legacy = prefs.getString(_kCameras);
    if (saved == null && legacy != null) {
      saved = legacy;
      await vault.write(_kCameras, legacy);
    }
    if (legacy != null) await prefs.remove(_kCameras);

    store._cameras = saved == null ? defaultCameras() : Camera.decodeList(saved);
    store._hub = prefs.getString(_kHub) ?? '';
    return store;
  }

  Camera? byId(String id) {
    for (final c in _cameras) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The URL a player should open: through the hub when one is set,
  /// otherwise directly from the camera.
  String streamUrl(Camera c, {required bool hd}) {
    if (usesHub) return 'rtsp://$_hub:8554/${c.id}-${hd ? 'main' : 'sub'}';
    return directUrl(c, hd: hd);
  }

  /// Direct camera URL, also the fallback when the hub is unreachable.
  String directUrl(Camera c, {required bool hd}) => hd ? c.mainUrl : c.subUrl;

  /// Candidate URLs for a player, best first, without duplicates.
  List<String> urlsFor(Camera c, {required bool hd}) => {streamUrl(c, hd: hd), directUrl(c, hd: hd)}.toList();

  Future<void> upsert(Camera cam) async {
    final i = _cameras.indexWhere((c) => c.id == cam.id);
    _cameras = [..._cameras];
    if (i == -1) {
      _cameras.add(cam);
    } else {
      _cameras[i] = cam;
    }
    await _save();
  }

  Future<void> remove(String id) async {
    _cameras = _cameras.where((c) => c.id != id).toList();
    await _save();
  }

  /// [to] is the final index of the item (as given by onReorderItem).
  Future<void> reorder(int from, int to) async {
    final list = [..._cameras];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    _cameras = list;
    await _save();
  }

  /// Fill in stream links the cameras haven't told us yet, by asking
  /// each camera over ONVIF. Safe to call often: cameras that already
  /// have links, or can't be reached right now, are skipped.
  Future<void> discoverMissingStreams() async {
    if (_discovering) return;
    _discovering = true;
    try {
      for (final cam in _cameras.where((c) => !c.hasStreams && c.hasOnvif).toList()) {
        try {
          final (hd, light) = await OnvifClient.of(cam).discoverStreams();
          if (hd == null) continue;
          final current = byId(cam.id);
          if (current == null || current.hasStreams) continue;
          await upsert(current.copyWith(mainUrl: hd, subUrl: light ?? hd));
        } on Exception {
          // Camera offline right now; try again next launch or pull-to-refresh.
        }
      }
    } finally {
      _discovering = false;
    }
  }

  bool _discovering = false;

  /// First run on a device: cameras are known but the camera password
  /// isn't (it is never shipped inside the app).
  bool get needsPassword => _cameras.isNotEmpty && _cameras.every((c) => !c.hasOnvif);

  /// Checks [password] against the cameras and, if at least one accepts it,
  /// saves it (encrypted, on this device only) for every camera that has
  /// none yet, then fetches their stream links. Returns false if no camera
  /// accepted it (wrong password, or none reachable).
  Future<bool> setPassword(String password, {bool force = false}) async {
    final pending = _cameras.where((c) => !c.hasOnvif).toList();
    if (pending.isEmpty || password.isEmpty) return false;
    final found = <String, (String, String)>{};
    for (final cam in pending) {
      try {
        final (hd, light) = await OnvifClient(cam.copyWith(onvifPassword: password)).discoverStreams();
        if (hd != null) found[cam.id] = (hd, light ?? hd);
      } on Exception {
        // wrong password or offline; decided below
      }
    }
    if (found.isEmpty && !force) return false;
    _cameras = [
      for (final c in _cameras)
        if (c.hasOnvif)
          c
        else
          c.copyWith(
            onvifPassword: password,
            mainUrl: found[c.id]?.$1 ?? c.mainUrl,
            subUrl: found[c.id]?.$2 ?? c.subUrl,
          ),
    ];
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> setHub(String value) async {
    _hub = value.trim();
    await _prefs.setString(_kHub, _hub);
    notifyListeners();
  }

  Future<void> _save() async {
    await _vault.write(_kCameras, Camera.encodeList(_cameras));
    notifyListeners();
  }

  String newId() => 'cam${DateTime.now().millisecondsSinceEpoch}';
}
