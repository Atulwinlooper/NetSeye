import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/camera_store.dart';
import '../../services/network_status.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../settings/camera_editor.dart';
import '../settings/settings_screen.dart';
import '../viewer/viewer_screen.dart';
import 'camera_tile.dart';
import 'feed_pool.dart';
import 'password_gate.dart';
import '../../services/device.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.connect = true});
  final CameraStore store;
  final bool connect;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FeedPool _pool = FeedPool(widget.store, connect: widget.connect);

  @override
  void dispose() {
    _pool.dispose();
    super.dispose();
  }

  /// Show another screen over the grid. Grid connections stay up the whole
  /// time: the viewer shows them directly, and coming back is instant.
  Future<void> _cover(Route<void> route) => Navigator.of(context).push(route);

  void _open(int index) =>
      _cover(fadeThroughRoute<void>(ViewerScreen(store: widget.store, pool: _pool, initialIndex: index)));

  void _settings() => _cover(slideRoute<void>(SettingsScreen(store: widget.store)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.store, _pool]),
        builder: (context, _) {
          // First open on this device: get the camera password first.
          if (widget.store.needsPassword) return PasswordGate(store: widget.store);
          final cams = widget.store.cameras;
          return LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              // Wide landscape screens (TVs, tablets) show up to three cameras in
              // one row so nothing is cut off below the fold.
              final wideLandscape = w >= 900 && w > box.maxHeight * 1.3;
              final columns = w < 640 ? 1 : ((w < 1100 && !wideLandscape) ? 2 : 3);
              final gutter = w < 640 ? 16.0 : 28.0;
              final content = w.clamp(0, 1440).toDouble();
              final side = (w - content) / 2 + gutter;

              // Each tile repaints on its own video frames without dragging
              // the rest of the screen along.
              Widget tile(int i) => RepaintBoundary(
                child: CameraTile(
                  key: ValueKey(cams[i].id),
                  camera: cams[i],
                  feed: _pool[cams[i].id],
                  autofocus: i == 0,
                  onOpen: () => _open(i),
                  onEdit: () => _cover(slideRoute<void>(CameraEditor(store: widget.store, camera: cams[i]))),
                ),
              );

              // TV / wide screen with three or four cameras: a full-screen
              // 2 × 2 wall, every camera an equal quarter. With three, the
              // fourth quarter carries the clock, status and settings.
              final wall = wideLandscape && box.maxHeight >= 500 && (cams.length == 3 || cams.length == 4);
              if (wall) {
                return _Wall(
                  cells: [
                    for (var i = 0; i < cams.length; i++) _Arrive(index: i, child: tile(i)),
                    if (cams.length == 3)
                      _Arrive(
                        index: 3,
                        child: _InfoPanel(health: _pool.health, total: cams.length, onSettings: _settings),
                      ),
                  ],
                );
              }

              return RefreshIndicator(
                color: Palette.accent,
                backgroundColor: Palette.slate,
                onRefresh: () async {
                  _pool.reconnectAll();
                  await Future<void>.delayed(const Duration(milliseconds: 700));
                },
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverSafeArea(
                      bottom: false,
                      sliver: SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 12, side, 22),
                        sliver: SliverToBoxAdapter(
                          child: _Header(count: cams.length, health: _pool.health, onSettings: _settings),
                        ),
                      ),
                    ),
                    if (cams.isEmpty)
                      SliverFillRemaining(hasScrollBody: false, child: _Empty(onAdd: _settings))
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 0, side, 40),
                        sliver: SliverGrid.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: gutter * 0.8,
                            crossAxisSpacing: gutter * 0.8,
                            childAspectRatio: 16 / 9,
                          ),
                          itemCount: cams.length,
                          itemBuilder: (context, i) => _Arrive(index: i, child: tile(i)),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Four equal quarters filling the screen, no scrolling.
class _Wall extends StatelessWidget {
  const _Wall({required this.cells});
  final List<Widget> cells;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    Widget row(int from) => Expanded(
      child: Row(
        children: [
          Expanded(child: cells[from]),
          const SizedBox(width: _gap),
          Expanded(child: cells[from + 1]),
        ],
      ),
    );
    // On a TV the wall sits on a solid base: video frames redraw the screen
    // continuously, and blending every tile over the lit backdrop costs an
    // old TV GPU ~15 ms a frame. The wall covers nearly all of it anyway.
    return ColoredBox(
      color: Device.isTv ? const Color(0xFF0B0D14) : Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_gap),
          child: Column(
            children: [
              row(0),
              const SizedBox(height: _gap),
              row(2),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wall's fourth quarter: network, time and camera health, rather
/// than an empty hole.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.health, required this.total, required this.onSettings});
  final ValueListenable<CameraHealth> health;
  final int total;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Glass(
      blur: false,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(30, 24, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _NetworkLine(size: 13)),
              const SizedBox(width: 12),
              _SettingsButton(onTap: onSettings),
            ],
          ),
          const Spacer(),
          const RepaintBoundary(child: _Clock(large: true)),
          const SizedBox(height: 14),
          _HealthChips(health: health, total: total, large: true),
          const SizedBox(height: 16),
          Text('NetSeye', style: Typo.display(26, color: Palette.ash)),
        ],
      ),
    );
  }
}

/// Phone / tablet header: network and clock, the name, camera health.
class _Header extends StatelessWidget {
  const _Header({required this.count, required this.health, required this.onSettings});
  final int count;
  final ValueListenable<CameraHealth> health;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(child: _NetworkLine()),
            SizedBox(width: 12),
            _Clock(),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text('NetSeye', style: Typo.display(40))),
            _SettingsButton(onTap: onSettings),
          ],
        ),
        const SizedBox(height: 14),
        _HealthChips(health: health, total: count),
      ],
    );
  }
}

/// "Wi-Fi · Home_5G" with a dot that's green when connected.
class _NetworkLine extends StatelessWidget {
  const _NetworkLine({this.size = 12});
  final double size;

  @override
  Widget build(BuildContext context) {
    final net = NetworkStatus.instance;
    return ListenableBuilder(
      listenable: net,
      builder: (_, _) => Semantics(
        label: 'Connected to ${net.summary}',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              net.type == 'ethernet' ? Icons.settings_ethernet_rounded : Icons.wifi_rounded,
              size: size + 3,
              color: net.connected ? Palette.moss : Palette.ember,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                net.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Typo.label(
                  color: Palette.bone.withValues(alpha: 0.85),
                  size: size,
                ).copyWith(letterSpacing: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass pills: "3 online", "1 offline", "1 connecting".
class _HealthChips extends StatelessWidget {
  const _HealthChips({required this.health, required this.total, this.large = false});
  final ValueListenable<CameraHealth> health;
  final int total;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraHealth>(
      valueListenable: health,
      builder: (_, h, _) {
        final chips = [
          _chip(h.live, 'online', Palette.moss),
          if (h.offline > 0) _chip(h.offline, 'offline', Palette.ember),
          if (h.connecting > 0) _chip(h.connecting, 'connecting', Palette.ash),
        ];
        return Semantics(
          label:
              '${h.live} of $total cameras online'
              '${h.offline > 0 ? ', ${h.offline} offline' : ''}'
              '${h.connecting > 0 ? ', ${h.connecting} connecting' : ''}',
          excludeSemantics: true,
          child: Wrap(spacing: 8, runSpacing: 8, children: chips),
        );
      },
    );
  }

  Widget _chip(int n, String word, Color dot) => Glass(
    pill: true,
    blur: false,
    padding: EdgeInsets.symmetric(horizontal: large ? 14 : 12, vertical: large ? 8 : 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text('$n', style: Typo.bodyStrong.copyWith(fontSize: large ? 15 : 13)),
        const SizedBox(width: 4),
        Text(word, style: Typo.small.copyWith(fontSize: large ? 14 : 12.5)),
      ],
    ),
  );
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Settings',
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      focusRadius: 100,
      child: const Glass(
        pill: true,
        blur: false,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.tune_rounded, size: 20, color: Palette.bone),
        ),
      ),
    ),
  );
}

/// 12-hour clock. Small in the phone header; big on the TV wall.
class _Clock extends StatefulWidget {
  const _Clock({this.large = false});
  final bool large;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final ampm = _now.hour < 12 ? 'AM' : 'PM';
    final hm = '$h:${two(_now.minute)}';
    const tabular = [FontFeature.tabularFigures()];
    if (widget.large) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: hm,
              style: Typo.display(84).copyWith(fontFeatures: tabular),
            ),
            TextSpan(
              text: ' $ampm',
              style: Typo.display(28, color: Palette.ash),
            ),
            TextSpan(
              text: '  ${two(_now.second)}',
              style: Typo.label(size: 14, color: Palette.dusk).copyWith(fontFeatures: tabular),
            ),
          ],
        ),
      );
    }
    return Text(
      '$hm:${two(_now.second)} $ampm',
      style: Typo.label(size: 12, color: Palette.ash).copyWith(fontFeatures: tabular),
    );
  }
}

/// Tiles drift up into place one after another on first load.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + index * 90),
      curve: Interval((index * 90) / (520 + index * 90), 1, curve: Motion.glide),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Nothing to watch yet', style: Typo.display(32)),
          const SizedBox(height: 8),
          Text('Add a camera from settings to begin.', style: Typo.small),
          const SizedBox(height: 20),
          Pressable(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(color: Palette.accent, borderRadius: BorderRadius.circular(100)),
              child: Text('Open settings', style: Typo.button.copyWith(color: Palette.onAccent)),
            ),
          ),
        ],
      ),
    );
  }
}
