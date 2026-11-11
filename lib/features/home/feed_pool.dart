import 'package:flutter/widgets.dart';

import '../../data/camera_store.dart';
import '../../services/live_feed.dart';

/// Keeps one light (sub-stream) feed per camera for the grid, and
/// releases every connection when the app goes to the background.
/// That matters: some cameras only allow one viewer at a time, so an
/// idle phone must not hold on to them.
class FeedPool extends ChangeNotifier {
  FeedPool(this.store, {this.connect = true}) {
    store.addListener(_sync);
    _lifecycle = AppLifecycleListener(
      onHide: _releaseAll,
      onShow: () {
        _sync();
        store.discoverMissingStreams();
      },
    );
    _sync();
    store.discoverMissingStreams();
  }

  final CameraStore store;

  /// False in previews and tests: no network connections are made.
  final bool connect;
  late final AppLifecycleListener _lifecycle;
  final Map<String, LiveFeed> _feeds = {};
  final Map<String, String> _urlsFor = {};
  bool _hidden = false;

  LiveFeed? operator [](String cameraId) => _feeds[cameraId];

  /// How many cameras are live, still connecting, or offline. Updates on
  /// every feed state change (without rebuilding the whole grid).
  final health = ValueNotifier<CameraHealth>(const CameraHealth(0, 0, 0));

  void _recount() {
    var live = 0, offline = 0;
    for (final cam in store.cameras) {
      final s = _feeds[cam.id]?.state;
      if (s == FeedState.live) {
        live++;
      } else if (s == FeedState.failed) {
        offline++;
      }
    }
    health.value = CameraHealth(live, store.cameras.length - live - offline, offline);
  }

  LiveFeed _watch(LiveFeed f) => f..addListener(_recount);

  void _sync() {
    _hidden = false;
    if (!connect) return _recount();
    final wanted = <String>{};
    for (final cam in store.cameras) {
      if (!cam.hasStreams) continue; // still being discovered
      wanted.add(cam.id);
      final urls = store.urlsFor(cam, hd: false);
      final key = urls.join('|');
      if (_urlsFor[cam.id] != key) {
        _feeds.remove(cam.id)?.dispose();
        _feeds[cam.id] = _watch(LiveFeed(urls: urls, grid: true));
        _urlsFor[cam.id] = key;
      }
    }
    for (final id in _feeds.keys.toList()) {
      if (!wanted.contains(id)) {
        _feeds.remove(id)?.dispose();
        _urlsFor.remove(id);
      }
    }
    _recount();
    notifyListeners();
  }

  void _releaseAll() {
    if (_hidden) return;
    _hidden = true;
    for (final f in _feeds.values) {
      f.dispose();
    }
    _feeds.clear();
    _urlsFor.clear();
    _recount();
    notifyListeners();
  }

  void reconnectAll() {
    store.discoverMissingStreams();
    for (final f in _feeds.values) {
      f.reconnect();
    }
  }

  @override
  void dispose() {
    store.removeListener(_sync);
    _lifecycle.dispose();
    for (final f in _feeds.values) {
      f.dispose();
    }
    health.dispose();
    super.dispose();
  }
}

/// Counts for the "2 online · 1 offline" summary.
@immutable
class CameraHealth {
  const CameraHealth(this.live, this.connecting, this.offline);
  final int live, connecting, offline;

  @override
  bool operator ==(Object other) =>
      other is CameraHealth &&
      other.live == live &&
      other.connecting == connecting &&
      other.offline == offline;

  @override
  int get hashCode => Object.hash(live, connecting, offline);
}
