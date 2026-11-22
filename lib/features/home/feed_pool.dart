import 'dart:async';

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
        unawaited(store.verifyLocations());
      },
    );
    if (connect) {
      // Before showing any video, check each address still belongs to the
      // same camera (routers reshuffle addresses). Capped at 3 s so a
      // camera that's off doesn't hold up the others.
      unawaited(
        Future.any([store.verifyLocations(force: true), Future<void>.delayed(const Duration(seconds: 3))])
            .whenComplete(() {
              _started = true;
              _sync();
            }),
      );
      // Cheap re-check now and then (one small request per camera), so a
      // reshuffle while the app runs for days is caught too.
      _recheck = Timer.periodic(const Duration(minutes: 5), (_) => store.verifyLocations());
      if (_churnSeconds > 0) {
        _churn = Timer.periodic(const Duration(seconds: _churnSeconds), (_) {
          for (final f in _feeds.values) {
            f.reconnect();
          }
        });
      }
    } else {
      _started = true;
      _sync();
    }
    store.discoverMissingStreams();
  }

  bool _started = false;
  Timer? _recheck;

  /// Test builds only (--dart-define=PEHRA_CHURN=N, in seconds): reconnect every
  /// camera on a timer, to compress days of real-world reconnects into
  /// minutes when hunting slow leaks.
  static const _churnSeconds = int.fromEnvironment('PEHRA_CHURN');
  Timer? _churn;

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
    // A camera that can't be reached may simply have a new address.
    if (offline > 0 && connect) unawaited(store.verifyLocations());
  }

  LiveFeed _watch(LiveFeed f) => f..addListener(_recount);

  void _sync() {
    if (!_started) return;
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
    unawaited(store.verifyLocations(force: true));
    store.discoverMissingStreams();
    for (final f in _feeds.values) {
      f.reconnect();
    }
  }

  @override
  void dispose() {
    store.removeListener(_sync);
    _lifecycle.dispose();
    _recheck?.cancel();
    _churn?.cancel();
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
