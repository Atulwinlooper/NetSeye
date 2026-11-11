import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device.dart';

/// How a stream is played, all with Android's own media stack (Media3):
/// RTP over the RTSP connection (TCP) direct to the camera, the same through
/// a small local relay that repairs a firmware quirk (needed by the older
/// "gvminirtsp" cameras), or RTP over UDP as a last resort. LiveFeed tries
/// them in turn and remembers what works per camera.
enum EngineKind { exoTcp, exoTcpRelay, exoUdp }

/// Events an engine reports back to its feed.
abstract interface class EngineListener {
  /// Frames are arriving (called repeatedly while healthy).
  void onProgress();

  /// The stream stopped by itself.
  void onEnded(String reason);
}

abstract class Engine {
  Engine(EngineListener l) : _listener = l;
  EngineListener? _listener;

  /// Reports go to the feed only while this engine is the current one.
  EngineListener get listener => _listener ?? const _Ignore();

  /// Stop reporting (called the moment the feed gives up on this engine,
  /// before it is disposed, so stale events can't flip the state).
  void detach() => _listener = null;

  static Engine create(EngineKind kind, EngineListener l) =>
      ExoEngine(l, tcp: kind != EngineKind.exoUdp, relay: kind == EngineKind.exoTcpRelay);

  Future<void> start(String url, {required bool audio, required bool muted, bool grid = false});
  Future<void> setMuted(bool muted);

  /// The picture, scaled like an image (cover in tiles, contain full screen).
  Widget view(BoxFit fit);

  /// End the stream but keep showing its last picture (until [dispose]).
  Future<void> stop();
  Future<void> dispose();
}

class _Ignore implements EngineListener {
  const _Ignore();
  @override
  void onProgress() {}
  @override
  void onEnded(String reason) {}
}

// -------------------------------------------------- Android media (Media3)

/// Plays a camera with Android's own media stack (ExoPlayer, native side in
/// ExoStreams.kt): hardware decoding straight into a Flutter texture.
class ExoEngine extends Engine {
  ExoEngine(super.listener, {required this.tcp, this.relay = false});
  final bool tcp;
  final bool relay;

  static const _channel = MethodChannel('netseye/exo');
  static final _live = <int, ExoEngine>{};
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final m = (call.arguments as Map).cast<String, Object?>();
      _live[(m['id']! as num).toInt()]?._event(m);
    });
  }

  int? _id;
  bool _disposed = false;
  final _size = ValueNotifier<Size>(const Size(1280, 720));
  final _texture = ValueNotifier<int?>(null);

  void _event(Map<String, Object?> m) {
    switch (m['type']) {
      case 'progress':
        listener.onProgress();
      case 'size':
        _size.value = Size((m['w']! as num).toDouble(), (m['h']! as num).toDouble());
      case 'error':
        listener.onEnded('exo ${m['message']}');
    }
  }

  @override
  Future<void> start(String url, {required bool audio, required bool muted, bool grid = false}) async {
    _wire();
    final id = await _channel.invokeMethod<int>('create', {
      'url': url,
      'tcp': tcp,
      'relay': relay,
      'muted': muted,
      // Grid tiles (no sound) on a TV: software decoder, keeping the TV's
      // usually single hardware decoder free for the full-screen HD view.
      'preferSoftware': grid && Device.isTv,
    });
    if (id == null) return;
    if (_disposed) {
      await _channel.invokeMethod<void>('dispose', {'id': id});
      return;
    }
    _id = id;
    _live[id] = this;
    _texture.value = id; // show the picture now that it exists
  }

  @override
  Future<void> setMuted(bool muted) async {
    final id = _id;
    if (id != null) await _channel.invokeMethod<void>('volume', {'id': id, 'muted': muted});
  }

  @override
  Widget view(BoxFit fit) => ListenableBuilder(
    listenable: Listenable.merge([_size, _texture]),
    builder: (_, _) {
      final id = _texture.value, size = _size.value;
      if (id == null) return const SizedBox.shrink();
      return ClipRect(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Texture(textureId: id),
          ),
        ),
      );
    },
  );

  @override
  Future<void> stop() async {
    _disposed = true; // ignore its events from now on
    final id = _id;
    if (id != null) await _channel.invokeMethod<void>('stop', {'id': id});
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final id = _id;
    _id = null;
    _texture.value = null;
    if (id == null) return;
    _live.remove(id);
    await _channel.invokeMethod<void>('dispose', {'id': id});
  }
}
