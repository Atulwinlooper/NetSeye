import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/camera_store.dart';
import '../../models/camera.dart';
import '../../services/live_feed.dart';
import '../../services/onvif.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../home/feed_pool.dart';
import 'ptz_driver.dart';
import 'ptz_pad.dart';
import '../../services/device.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.store, required this.pool, required this.initialIndex});

  final CameraStore store;
  final FeedPool pool;
  final int initialIndex;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  bool _chrome = true; // controls visible
  bool _listen = false;

  /// TVs start on the light stream: these cameras' HD (2304×1296) is
  /// beyond most TV video decoders (1080p max), and a 720p/1080p TV screen
  /// can't show the extra detail anyway. HD is still one press away.
  bool _hd = !Device.isTv;
  bool _move = false; // drag / arrows / remote steer the camera
  Timer? _hideTimer;

  /// Digital zoom for the camera on screen (reset when switching).
  final _zoom = TransformationController();
  double _scale = 1;

  final _keys = FocusNode(debugLabel: 'viewer');
  final _dockFocus = FocusNode(debugLabel: 'dock');
  PtzDriver? _driver;
  final _held = <LogicalKeyboardKey>{};

  List<Camera> get _cams => widget.store.cameras;
  Camera get _cam => _cams[_index.clamp(0, _cams.length - 1)];
  PtzDriver get _ptz => _driver ??= PtzDriver(OnvifClient.of(_cam));

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _zoom.addListener(() {
      final s = _zoom.value.getMaxScaleOnAxis();
      if ((s - _scale).abs() > 0.01) setState(() => _scale = s);
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _driver?.stop();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    _zoom.dispose();
    _keys.dispose();
    _dockFocus.dispose();
    super.dispose();
  }

  /// Last input came from a remote / keyboard rather than touch.
  bool _keyboard = false;

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_move) return; // keep controls while steering
    // Remote users read the screen from across the room: give them longer.
    _hideTimer = Timer(Duration(seconds: _keyboard ? 8 : 4), () {
      if (mounted) {
        setState(() => _chrome = false);
        _keys.requestFocus();
      }
    });
  }

  void _toggleChrome() {
    _keyboard = false; // a tap means touch
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  void _poke() {
    if (!_chrome) setState(() => _chrome = true);
    _scheduleHide();
  }

  bool? _immersive;

  /// Wide window (landscape phone, tablet, TV): hide system bars so the
  /// picture gets the whole screen. Runs on size changes, not in build.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final immersive = size.width > size.height;
    if (immersive != _immersive) {
      _immersive = immersive;
      SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  /// Pan/tilt support per camera, looked up once instead of every build.
  final _ptzSupport = <String, Future<bool>>{};
  Future<bool> _ptzFor(Camera c) => _ptzSupport[c.id] ??= OnvifClient.of(c).hasPtz();

  void _goTo(int i) {
    if (i < 0 || i >= _cams.length) return;
    _pages.animateToPage(i, duration: Motion.slow, curve: Motion.glide);
  }

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    _driver?.stop();
    _driver = null;
    _zoom.value = Matrix4.identity();
    setState(() {
      _index = i;
      _move = false;
    });
    _poke();
  }

  void _setMove(bool on) {
    if (!on) _driver?.stop();
    setState(() => _move = on);
    _poke();
  }

  // Zoom ----------------------------------------------------------------

  void _zoomBy(double factor, {Offset? focal}) {
    final size = MediaQuery.sizeOf(context);
    final f = focal ?? size.center(Offset.zero);
    final target = (_scale * factor).clamp(1.0, 4.0);
    final m = Matrix4.identity()
      ..translateByDouble(f.dx, f.dy, 0, 1)
      ..scaleByDouble(target / _scale, target / _scale, 1, 1)
      ..translateByDouble(-f.dx, -f.dy, 0, 1);
    final next = m.multiplied(_zoom.value);
    _zoom.value = target <= 1.001 ? Matrix4.identity() : _clampToView(next, size, target);
    _poke();
  }

  /// Keep the zoomed picture covering the screen (no empty edges).
  Matrix4 _clampToView(Matrix4 m, Size size, double scale) {
    final t = m.getTranslation();
    final minX = size.width - size.width * scale, minY = size.height - size.height * scale;
    return Matrix4.identity()
      ..translateByDouble(t.x.clamp(minX, 0.0), t.y.clamp(minY, 0.0), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _doubleTapZoom(Offset at) => _scale > 1.2 ? _zoomBy(1 / _scale) : _zoomBy(2.5, focal: at);

  // TV remote / keyboard ------------------------------------------------

  static final _arrows = {
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
  };

  static bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  /// Put the remote's focus on the controls (first dock button).
  void _focusControls() {
    _poke();
    _dockFocus.requestFocus();
  }

  /// Leave move mode and land back on the Move button's row.
  void _endMove() {
    _held.clear();
    _setMove(false);
    if (_keys.hasPrimaryFocus) _dockFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    final isArrow = _arrows.containsKey(k);
    _keyboard = true;
    // Move mode: arrows turn the camera; OK finishes.
    if (_move && _isOk(k)) {
      if (e is KeyDownEvent) _endMove();
      return KeyEventResult.handled;
    }
    if (_move && isArrow) {
      if (e is KeyDownEvent || e is KeyRepeatEvent) {
        _held.add(k);
        var v = Offset.zero;
        for (final h in _held) {
          v += _arrows[h]!;
        }
        _ptz.drive(v);
      } else if (e is KeyUpEvent) {
        _held.remove(k);
        if (_held.isEmpty) _driver?.stop();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // Focus is on the picture itself (no button picked yet — just opened,
    // or the controls faded): left/right switch cameras, OK / up / down
    // bring up the controls with the first button selected.
    if (_keys.hasPrimaryFocus) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        _goTo(_index - 1);
      } else if (k == LogicalKeyboardKey.arrowRight) {
        _goTo(_index + 1);
      } else if (isArrow || _isOk(k)) {
        _focusControls();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    // A button has focus: let normal remote navigation move between them.
    _poke(); // any key keeps the controls up
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final locked = _move || _scale > 1.01; // picture gestures own the drag
    // Back while steering just leaves move mode.
    return PopScope(
      canPop: !_move,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _move) _endMove();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _keys,
          autofocus: true,
          // The picture holds focus only as a resting place. Keep it out of
          // arrow-key traversal: being full-screen, it would otherwise be
          // picked as "the thing to the right" of a dock button, and the
          // next arrow would switch cameras.
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: _cams.length,
                physics: locked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                onPageChanged: _onPage,
                itemBuilder: (context, i) => _CameraPage(
                  camera: _cams[i],
                  store: widget.store,
                  pool: widget.pool,
                  active: i == _index,
                  hd: _hd,
                  listen: _listen,
                  zoom: i == _index ? _zoom : null,
                  move: i == _index && _move,
                  onTap: _toggleChrome,
                  onDoubleTap: _doubleTapZoom,
                  onSteer: (v) {
                    _ptz.drive(v);
                    _poke();
                  },
                  onSteerEnd: () => _driver?.stop(),
                ),
              ),
              // Move-mode hint, so it's clear the picture now steers.
              IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, -0.62),
                  child: AnimatedOpacity(
                    opacity: _move ? 1 : 0,
                    duration: Motion.base,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _keyboard
                            ? 'Hold the arrows to turn the camera  ·  OK when done'
                            : 'Drag the picture to turn the camera',
                        style: Typo.small.copyWith(color: Palette.bone),
                      ),
                    ),
                  ),
                ),
              ),
              // Top bar
              _Fade(
                visible: _chrome,
                alignment: Alignment.topCenter,
                child: _TopBar(
                  camera: _cam,
                  index: _index,
                  total: _cams.length,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),
              // Zoom controls, right edge
              _Fade(
                visible: _chrome,
                alignment: Alignment.centerRight,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _ZoomRail(
                      scale: _scale,
                      onIn: () => _zoomBy(1.5),
                      onOut: () => _zoomBy(1 / 1.5),
                      onReset: () => _zoomBy(1 / _scale),
                    ),
                  ),
                ),
              ),
              // Bottom dock
              _Fade(
                visible: _chrome,
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 18),
                  child: FocusTraversalGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSize(
                          duration: Motion.base,
                          curve: Motion.glide,
                          child: _move
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: ArrowPad(driver: _ptz, onInteract: _poke),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        _Dock(
                          listen: _listen,
                          hd: _hd,
                          ptzOpen: _move,
                          ptzSupported: _ptzFor(_cam),
                          firstFocus: _dockFocus,
                          onListen: () {
                            setState(() => _listen = !_listen);
                            _poke();
                          },
                          onQuality: () {
                            setState(() => _hd = !_hd);
                            _poke();
                          },
                          onPtz: () => _setMove(!_move),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One camera, full screen, in HD (or light quality when chosen), with
/// pinch / double-tap zoom and, in move mode, drag-to-steer.
class _CameraPage extends StatefulWidget {
  const _CameraPage({
    required this.camera,
    required this.store,
    required this.pool,
    required this.active,
    required this.hd,
    required this.listen,
    required this.zoom,
    required this.move,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSteer,
    required this.onSteerEnd,
  });

  final Camera camera;
  final CameraStore store;
  final bool active;
  final bool hd;
  final bool listen;
  final TransformationController? zoom;
  final FeedPool pool;
  final bool move;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDoubleTap;
  final ValueChanged<Offset> onSteer;
  final VoidCallback onSteerEnd;

  @override
  State<_CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<_CameraPage> {
  LiveFeed? _feed;
  Offset? _dragStart;
  Offset? _doubleTapAt;

  /// True when [_feed] is the grid's own connection (borrowed, not ours).
  bool _shared = false;

  @override
  void initState() {
    super.initState();
    _syncFeed();
  }

  @override
  void didUpdateWidget(covariant _CameraPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.hd != widget.hd) _syncFeed();
    if (old.listen != widget.listen) _feed?.setMuted(!widget.listen);
  }

  void _release() {
    final f = _feed;
    _feed = null;
    if (f == null) return;
    if (_shared) {
      f.setMuted(true); // hand it back to the grid, silent
    } else {
      f.dispose();
    }
    _shared = false;
  }

  void _syncFeed() {
    _release();
    if (!widget.active || !widget.camera.hasStreams) {
      if (mounted) setState(() {});
      return;
    }
    // Light quality: show the grid's existing connection. No reconnect, no
    // black flash: the picture is already there, in and out of full screen.
    final pooled = widget.hd ? null : widget.pool[widget.camera.id];
    if (pooled != null) {
      _feed = pooled..setMuted(!widget.listen);
      _shared = true;
    } else {
      // HD is a separate stream, so it needs its own connection. If this
      // device can't decode it (TVs), fall back to light.
      final urls = [
        ...widget.store.urlsFor(widget.camera, hd: widget.hd),
        if (widget.hd && Device.isTv) ...widget.store.urlsFor(widget.camera, hd: false),
      ];
      _feed = LiveFeed(withAudio: true, urls: urls)..setMuted(!widget.listen);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _endSteer() {
    if (_dragStart == null) return;
    _dragStart = null;
    widget.onSteerEnd();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    if (feed == null) return const ColoredBox(color: Colors.black);
    final picture = IgnorePointer(
      child: FeedView(feed: feed, fit: BoxFit.contain, compact: false),
    );
    final move = widget.move;

    // One fixed structure in both modes: changing the widgets around the
    // video would tear down the native player view (black picture).
    // Steering uses raw pointer events (a Listener isn't part of the
    // gesture arena, so the zoom widget can't steal the drag); in move
    // mode the zoom widget simply has pinch and pan switched off.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: move ? null : (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: move ? null : () => widget.onDoubleTap(_doubleTapAt ?? Offset.zero),
      child: Listener(
        onPointerDown: move ? (e) => _dragStart = e.localPosition : null,
        onPointerMove: move
            ? (e) {
                final start = _dragStart;
                if (start == null) return;
                // Distance from where the finger went down sets direction
                // and speed (120 px = full speed).
                final v = (e.localPosition - start) / 120;
                widget.onSteer(v.distance > 1 ? v / v.distance : v);
              }
            : null,
        onPointerUp: move ? (_) => _endSteer() : null,
        onPointerCancel: move ? (_) => _endSteer() : null,
        child: InteractiveViewer(
          transformationController: widget.zoom,
          minScale: 1,
          maxScale: 4,
          panEnabled: !move,
          scaleEnabled: !move,
          child: picture,
        ),
      ),
    );
  }
}

/// + / − and the current zoom level, stacked on the right edge.
class _ZoomRail extends StatelessWidget {
  const _ZoomRail({required this.scale, required this.onIn, required this.onOut, required this.onReset});
  final double scale;
  final VoidCallback onIn, onOut, onReset;

  @override
  Widget build(BuildContext context) {
    final zoomed = scale > 1.01;
    return FocusTraversalGroup(
      child: Glass(
        pill: true,
        tint: const Color(0x59000000), // keeps it legible over bright video
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RailButton(icon: Icons.add_rounded, label: 'Zoom in', onTap: scale < 3.99 ? onIn : null),
            Semantics(
              button: zoomed,
              label: zoomed ? 'Zoom ${scale.toStringAsFixed(1)} times, reset' : 'Not zoomed',
              excludeSemantics: true,
              onTap: zoomed ? onReset : null,
              child: Pressable(
                onTap: zoomed ? onReset : null,
                child: SizedBox(
                  width: 48,
                  height: 30,
                  child: Center(
                    child: Text(
                      '${scale.toStringAsFixed(1)}×',
                      style: Typo.mono(size: 11, color: zoomed ? Palette.accent : Palette.ash),
                    ),
                  ),
                ),
              ),
            ),
            _RailButton(icon: Icons.remove_rounded, label: 'Zoom out', onTap: zoomed ? onOut : null),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      focusRadius: 100,
      child: SizedBox(width: 48, height: 48, child: Icon(icon, color: Palette.bone, size: 22)),
    ),
  );
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.alignment, required this.child});
  final bool visible;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fromTop = alignment == Alignment.topCenter;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : Offset(0, fromTop ? -0.15 : 0.15),
          duration: Motion.base,
          curve: Motion.ease,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: Motion.base,
            curve: Motion.ease,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.camera, required this.index, required this.total, required this.onBack});
  final Camera camera;
  final int index;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 36),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Back to all cameras',
                excludeSemantics: true,
                onTap: onBack,
                child: Pressable(
                  onTap: onBack,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back_rounded, color: Palette.bone),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.base,
                  layoutBuilder: (cur, prev) =>
                      Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                  child: Column(
                    key: ValueKey(camera.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        camera.name,
                        style: Typo.display(26),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [if (camera.room.isNotEmpty) camera.room.toUpperCase(), camera.host].join('  ·  '),
                        style: Typo.label(size: 10),
                      ),
                    ],
                  ),
                ),
              ),
              if (total > 1)
                Row(
                  children: List.generate(total, (i) {
                    final on = i == index;
                    return AnimatedContainer(
                      duration: Motion.base,
                      curve: Motion.ease,
                      margin: const EdgeInsets.only(left: 5),
                      width: on ? 16 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: on ? Palette.bone : Palette.bone.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.listen,
    required this.hd,
    required this.ptzOpen,
    required this.ptzSupported,
    required this.firstFocus,
    required this.onListen,
    required this.onQuality,
    required this.onPtz,
  });

  final bool listen, hd, ptzOpen;
  final Future<bool> ptzSupported;
  final FocusNode firstFocus;
  final VoidCallback onListen, onQuality, onPtz;

  @override
  Widget build(BuildContext context) {
    return Glass(
      pill: true,
      tint: const Color(0x59000000), // keeps it legible over bright video
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DockButton(
            icon: listen ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            label: listen ? 'Listening' : 'Listen',
            on: listen,
            onTap: onListen,
            focusNode: firstFocus,
          ),
          _DockButton(icon: Icons.high_quality_rounded, label: hd ? 'HD' : 'Light', on: hd, onTap: onQuality),
          FutureBuilder<bool>(
            future: ptzSupported,
            builder: (_, snap) => AnimatedSize(
              duration: Motion.base,
              curve: Motion.ease,
              child: snap.data == true
                  ? _DockButton(icon: Icons.control_camera_rounded, label: 'Move', on: ptzOpen, onTap: onPtz)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.focusNode,
  });
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        focusNode: focusNode,
        focusRadius: 100,
        focusColor: on ? Palette.bone : Palette.accent,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.ease,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: on ? Palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: on ? Palette.onAccent : Palette.bone),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: Motion.base,
                style: Typo.button.copyWith(color: on ? Palette.onAccent : Palette.bone),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
