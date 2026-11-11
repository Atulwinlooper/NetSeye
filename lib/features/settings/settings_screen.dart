import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/camera_store.dart';
import '../../data/validate.dart';
import '../../models/camera.dart';
import '../../services/network_status.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../../widgets/remote_keyboard.dart';
import 'camera_editor.dart';
import '../../services/device.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final CameraStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _hub = TextEditingController(text: widget.store.hub);
  String? _hubError;

  Future<void> _hubOnTv() async {
    await RemoteEntry.open(context, _hub, label: 'Hub address', mono: true);
    _saveHub();
  }

  void _saveHub() {
    final value = _hub.text.trim();
    if (value == widget.store.hub) return;
    final problem = Validate.host(value, optional: true);
    setState(() => _hubError = problem);
    if (problem == null) widget.store.setHub(value);
  }

  @override
  void dispose() {
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final size = MediaQuery.sizeOf(context);
    // TV / wide landscape: a full-width grid instead of a phone column.
    if (size.width >= 900 && size.width > size.height * 1.3) {
      return Scaffold(
        body: ListenableBuilder(listenable: store, builder: (context, _) => _wide(context)),
      );
    }
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Semantics(
                            button: true,
                            label: 'Back',
                            excludeSemantics: true,
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Pressable(
                              onTap: () => Navigator.of(context).maybePop(),
                              child: const SizedBox.square(
                                dimension: 44,
                                child: Icon(Icons.arrow_back_rounded, color: Palette.bone),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(child: Text('Settings', style: Typo.display(44))),
                ),
                _section('Cameras', 'Drag to reorder. Tap to rename or change.'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverReorderableList(
                    itemCount: store.cameras.length,
                    onReorderItem: store.reorder,
                    proxyDecorator: (child, _, anim) => AnimatedBuilder(
                      animation: anim,
                      builder: (_, c) => Transform.scale(
                        scale: 1 + 0.03 * Curves.easeOut.transform(anim.value),
                        child: Material(color: Colors.transparent, child: c),
                      ),
                      child: child,
                    ),
                    itemBuilder: (context, i) {
                      final cam = store.cameras[i];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(cam.id),
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Pressable(
                            onTap: () =>
                                Navigator.of(context)
                                    .push(slideRoute<void>(CameraEditor(store: store, camera: cam))),
                            child: _Row(
                              title: cam.name,
                              subtitle: [if (cam.room.isNotEmpty) cam.room, cam.host].join('  ·  '),
                              trailing: const Icon(
                                Icons.drag_indicator_rounded,
                                color: Palette.dusk,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Pressable(
                      onTap: () => Navigator.of(context).push(slideRoute<void>(CameraEditor(store: store))),
                      child: Glass(
                        blur: false,
                        radius: 18,
                        child: Container(
                          height: 64,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_rounded, color: Palette.accent, size: 20),
                              const SizedBox(width: 8),
                              Text('Add a camera', style: Typo.button.copyWith(color: Palette.accent)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _section(
                  'Home hub',
                  'Optional. If a computer at home is sharing the cameras, enter its address so the whole family can watch at once. Leave empty to connect straight to the cameras.',
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _hubField()),
                ),
                SliverSafeArea(
                  top: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Text('NetSeye', style: Typo.display(24, color: Palette.dusk)),
                          const SizedBox(height: 6),
                          Text(
                            'Everything stays on your home Wi-Fi.',
                            style: Typo.small.copyWith(color: Palette.dusk),
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
      ),
    );
  }

  Widget _hubField() => RemoteEntry(
    onOpen: _hubOnTv,
    child: TextField(
      controller: _hub,
      readOnly: Device.isTv,
      onTap: Device.isTv ? _hubOnTv : null,
      keyboardType: TextInputType.url,
      autocorrect: false,
      enableSuggestions: false,
      style: Typo.mono(color: Palette.bone, size: 15),
      decoration: InputDecoration(
        labelText: 'Hub address',
        hintText: 'e.g. 192.168.1.41',
        errorText: _hubError,
        errorStyle: Typo.small.copyWith(color: Palette.ember, fontSize: 12),
        errorMaxLines: 2,
      ),
      onChanged: (_) {
        if (_hubError != null) setState(() => _hubError = null);
      },
      onSubmitted: (_) => _saveHub(),
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
        _saveHub();
      },
    ),
  );

  void _edit(Camera? cam) =>
      Navigator.of(context).push(slideRoute<void>(CameraEditor(store: widget.store, camera: cam)));

  /// TV layout: header, a grid of camera cards (plus "Add"), then the home
  /// hub and network details side by side. The first card takes focus so
  /// the remote starts somewhere useful.
  Widget _wide(BuildContext context) {
    final cams = widget.store.cameras;
    final w = MediaQuery.sizeOf(context).width;
    final columns = w >= 1500 ? 4 : 3;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 12, 36, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Pressable(
                          onTap: () => Navigator.of(context).maybePop(),
                          focusRadius: 100,
                          child: const Glass(
                            pill: true,
                            blur: false,
                            child: SizedBox.square(
                              dimension: 44,
                              child: Icon(Icons.arrow_back_rounded, color: Palette.bone),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Text('Settings', style: Typo.display(32)),
                      const Spacer(),
                      Text(
                        '${cams.length} ${cams.length == 1 ? 'camera' : 'cameras'}',
                        style: Typo.small.copyWith(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              _wideLabel('Cameras', 'Select a camera to rename it or change how it connects.'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: 88,
                  ),
                  itemCount: cams.length + 1,
                  itemBuilder: (context, i) {
                    if (i == cams.length) {
                      return _CameraCard.add(onTap: () => _edit(null), autofocus: cams.isEmpty);
                    }
                    final cam = cams[i];
                    return _CameraCard(
                      key: ValueKey(cam.id),
                      title: cam.name,
                      subtitle: [if (cam.room.isNotEmpty) cam.room, cam.host].join('  ·  '),
                      autofocus: i == 0,
                      onTap: () => _edit(cam),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(36, 14, 36, 20),
                sliver: SliverToBoxAdapter(
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Glass(
                            blur: false,
                            radius: 22,
                            padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('HOME HUB', style: Typo.label(color: Palette.accent)),
                                const SizedBox(height: 6),
                                Text(
                                  'Optional. A computer at home that shares the cameras with the whole family. Leave empty to connect straight to the cameras.',
                                  style: Typo.small,
                                ),
                                const SizedBox(height: 12),
                                _hubField(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: Glass(
                            blur: false,
                            radius: 22,
                            padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                            child: ListenableBuilder(
                              listenable: NetworkStatus.instance,
                              builder: (_, _) {
                                final net = NetworkStatus.instance;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('THIS DEVICE', style: Typo.label(color: Palette.accent)),
                                    const SizedBox(height: 12),
                                    _fact(Icons.wifi_rounded, net.ssid ?? net.summary),
                                    if (net.address != null) _fact(Icons.router_outlined, net.address!),
                                    const Spacer(),
                                    Text('NetSeye', style: Typo.display(22, color: Palette.ash)),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Everything stays on your home Wi-Fi.',
                                      style: Typo.small.copyWith(color: Palette.dusk),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
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

  Widget _fact(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 17, color: Palette.ash),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Typo.body, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Widget _wideLabel(String title, String hint) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(36, 16, 36, 12),
    sliver: SliverToBoxAdapter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title.toUpperCase(), style: Typo.label(color: Palette.accent)),
          const SizedBox(width: 14),
          Flexible(child: Text(hint, style: Typo.small)),
        ],
      ),
    ),
  );

  Widget _section(String title, String hint) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 40, 20, 14),
    sliver: SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: Typo.label(color: Palette.accent)),
          const SizedBox(height: 6),
          Text(hint, style: Typo.small),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Glass(
      blur: false,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Typo.display(19)),
                const SizedBox(height: 4),
                Text(subtitle, style: Typo.mono(size: 12)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One camera on the TV settings grid (or the "Add a camera" card).
class _CameraCard extends StatelessWidget {
  const _CameraCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  }) : add = false;

  const _CameraCard.add({required this.onTap, this.autofocus = false})
    : title = 'Add a camera',
      subtitle = 'Find it on your Wi-Fi',
      add = true,
      super(key: const ValueKey('add'));

  final String title, subtitle;
  final VoidCallback onTap;
  final bool autofocus, add;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: add ? title : '$title, $subtitle. Opens camera settings',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        autofocus: autofocus,
        focusRadius: 22,
        child: Glass(
          blur: false,
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.accent.withValues(alpha: add ? 0.16 : 0.22),
                ),
                child: Icon(
                  add ? Icons.add_rounded : Icons.videocam_rounded,
                  color: add ? Palette.accent : Palette.bone,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Typo.display(19, color: add ? Palette.accent : Palette.bone),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: add ? Typo.small : Typo.mono(size: 12),
                    ),
                  ],
                ),
              ),
              if (!add) const Icon(Icons.chevron_right_rounded, color: Palette.dusk),
            ],
          ),
        ),
      ),
    );
  }
}
