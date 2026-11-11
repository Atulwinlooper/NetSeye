import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engines.dart';

enum FeedState { connecting, live, retrying, failed }

/// Diagnostics for support: on in debug builds, or in any build made with
/// --dart-define=PEHRA_LOG=true. Never logs passwords (URLs carry none).
const bool _logOn = kDebugMode || bool.fromEnvironment('PEHRA_LOG');
void _log(String m) {
  if (_logOn) debugPrint('NetSeye: $m');
}

/// One live camera picture. Picks the engine/transport that works for this
/// camera (see [EngineKind]), handles hub -> direct fallback, and
/// reconnects quietly. Every attempt gets a fresh engine, so a wedged
/// stream can never linger.
class LiveFeed extends ChangeNotifier implements EngineListener {
  LiveFeed({required List<String> urls, this.withAudio = false, this.grid = false})
    : assert(urls.isNotEmpty),
      urls = List.unmodifiable(urls) {
    _health = Timer.periodic(_tick, (_) => _checkHealth());
    _open();
  }

  /// Candidate URLs in order of preference (hub first, then camera).
  final List<String> urls;
  final bool withAudio;

  /// A small always-on grid stream (TVs decode these in software, keeping
  /// the hardware decoder for HD).
  final bool grid;

  static const _tick = Duration(seconds: 2);
  static const _firstFrameTimeout = Duration(seconds: 20);
  static const _stallTimeout = Duration(seconds: 12);

  /// An engine counts as working for a camera once its stream has stayed
  /// up this long.
  static const _provenAfter = Duration(seconds: 20);

  /// Order to try transports in. TCP through the local relay first: the
  /// relay sends the camera the RTCP receiver reports Android's player
  /// omits (CP Plus "minirtsp" firmware stops streaming without them) and
  /// repairs the older firmware's stream description. Plain TCP and UDP
  /// follow; whatever stays up for 20 s is remembered per camera.
  static const _order = [
    EngineKind.exoTcpRelay,
    EngineKind.exoTcpRelay,
    EngineKind.exoTcp,
    EngineKind.exoTcpRelay,
    EngineKind.exoUdp,
  ];

  /// What worked, per camera host. Saved on the phone, so after the
  /// first run each camera starts straight on its working engine.
  static final Map<String, EngineKind> _proven = {};
  static SharedPreferences? _prefs;
  static const _kProven = 'engines.v4'; // v1: VLC/mpv; v2: could pin UDP

  /// Load remembered engines (call once at startup).
  static Future<void> loadMemory() async {
    _prefs = await SharedPreferences.getInstance();
    for (final entry in _prefs!.getStringList(_kProven) ?? const <String>[]) {
      final parts = entry.split('=');
      if (parts.length != 2) continue;
      final kind = EngineKind.values.where((k) => k.name == parts[1]);
      if (kind.isNotEmpty) _proven[parts[0]] = kind.first;
    }
  }

  static void _remember() =>
      _prefs?.setStringList(_kProven, [for (final e in _proven.entries) '${e.key}=${e.value.name}']);

  Engine? _engine;
  int _engineToken = 0; // bumps on every new engine, so views remount

  /// While reconnecting: the previous stream, stopped, still showing its
  /// last picture so the tile never goes black. Dropped once live again.
  Engine? _previous;
  int _previousToken = 0;

  /// True when there's a picture to show (live, or the last frame held
  /// while reconnecting).
  bool get hasPicture => _state == FeedState.live || _previous != null;
  int _tryIndex = 0;

  FeedState _state = FeedState.connecting;
  FeedState get state => _state;

  bool _muted = true;
  bool get muted => _muted;

  int _urlIndex = 0;
  int _attempt = 0;
  bool _disposed = false;
  Timer? _retry;
  late final Timer _health;

  DateTime _openedAt = DateTime.now();

  /// The current engine has shown at least one frame.
  bool _engineShowed = false;
  DateTime _lastProgressAt = DateTime.now();
  DateTime _liveSince = DateTime.now();

  String get _host => Uri.tryParse(urls[_urlIndex])?.host ?? '?';
  EngineKind get _kind => _proven[_host] ?? _order[_tryIndex % _order.length];

  /// The live picture for this feed.
  Widget view(BoxFit fit) {
    final prev = _previous;
    if (_state != FeedState.live && prev != null) {
      return KeyedSubtree(key: ValueKey(_previousToken), child: prev.view(fit));
    }
    final e = _engine;
    if (e == null) return const SizedBox.shrink();
    return KeyedSubtree(key: ValueKey(_engineToken), child: e.view(fit));
  }

  void _dropPrevious() {
    final p = _previous;
    _previous = null;
    if (p != null) unawaited(p.dispose());
  }

  Future<void> _open() async {
    if (_disposed) return;
    _setState(_attempt == 0 ? FeedState.connecting : FeedState.retrying);
    final old = _engine;
    final oldShowed = _engineShowed;
    _engineShowed = false;
    final kind = _kind;
    final e = Engine.create(kind, this);
    _engine = e;
    _engineToken++;
    _openedAt = DateTime.now();
    _lastProgressAt = DateTime.now();
    _log('[$_host] opening ${Uri.tryParse(urls[_urlIndex])?.pathSegments.last} with ${kind.name}');
    if (old != null) {
      // Hold the old picture (if it ever showed one) while the new stream
      // connects; end its camera session right away.
      if (_previous == null && oldShowed) {
        _previous = old;
        _previousToken = _engineToken - 1;
        unawaited(old.stop());
      } else {
        unawaited(old.dispose());
      }
    }
    notifyListeners(); // the view must mount the new engine
    await e.start(urls[_urlIndex], audio: withAudio, muted: _muted, grid: grid);
  }

  // EngineListener ------------------------------------------------------

  @override
  void onProgress() {
    if (_disposed) return;
    _lastProgressAt = DateTime.now();
    _engineShowed = true;
    if (_state != FeedState.live) _liveSince = DateTime.now();
    _setState(FeedState.live);
    if (_previous != null) {
      _dropPrevious();
      notifyListeners();
    }
  }

  @override
  void onEnded(String reason) => _fail(reason);

  // ---------------------------------------------------------------------

  void _checkHealth() {
    if (_disposed || _retry?.isActive == true) return;
    final now = DateTime.now();
    if (_state == FeedState.live) {
      if (!_proven.containsKey(_host) &&
          _kind == EngineKind.exoTcp &&
          now.difference(_liveSince) > _provenAfter) {
        _proven[_host] = _kind;
        _remember();
        _log('[$_host] ${_kind.name} proven');
      }
      if (now.difference(_lastProgressAt) > _stallTimeout) _fail('stalled');
    } else if (now.difference(_openedAt) > _firstFrameTimeout) {
      _fail('no picture');
    }
  }

  void _fail(String reason) {
    if (_disposed || _retry?.isActive == true) return;
    _engine?.detach(); // ignore anything the failing engine still reports
    _log('[$_host] $reason with ${_kind.name} (attempt ${_attempt + 1})');
    final wasLive = _state == FeedState.live;
    final shortLived = !wasLive || DateTime.now().difference(_liveSince) < _provenAfter;
    _attempt++;
    if (shortLived) {
      // This engine doesn't suit the camera: forget it, try the next one.
      if (_proven.remove(_host) != null) _remember();
      _tryIndex++;
    }
    // Hub didn't answer: move on to the camera itself.
    if (_urlIndex < urls.length - 1) _urlIndex++;
    // Quick at first (a camera that dropped us usually returns at once),
    // then a calm retry every few seconds. Never give up on a home camera;
    // after a while just show "can't reach" while still retrying.
    _setState(_attempt >= 6 ? FeedState.failed : FeedState.retrying);
    // At least 3 s: lets the camera let go of the dead session first.
    final wait = Duration(seconds: _attempt <= 2 ? 3 : 5);
    _retry = Timer(wait, _open);
  }

  /// Manual retry from the UI.
  void reconnect() {
    _retry?.cancel();
    _attempt = 0;
    _urlIndex = 0;
    _open();
  }

  Future<void> setMuted(bool value) async {
    _muted = value;
    await _engine?.setMuted(value);
    notifyListeners();
  }

  void _setState(FeedState s) {
    if (_disposed) return;
    if (s == FeedState.live) _attempt = 0;
    // Don't keep showing an old picture once the camera is truly unreachable.
    if (s == FeedState.failed) _dropPrevious();
    if (s != _state) {
      _log('[$_host] ${_state.name} -> ${s.name}');
      _state = s;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _health.cancel();
    final e = _engine;
    _engine = null;
    if (e != null) unawaited(e.dispose());
    _dropPrevious();
    super.dispose();
  }
}
