import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/camera_store.dart';
import '../../services/device.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../../widgets/remote_keyboard.dart';

/// First open on a device: ask for the cameras' password once. It's never
/// shipped inside the app; it's checked against the cameras and stored
/// encrypted on this device only.
class PasswordGate extends StatefulWidget {
  const PasswordGate({super.key, required this.store});
  final CameraStore store;

  @override
  State<PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends State<PasswordGate> {
  final _pass = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect({bool force = false}) async {
    if (_busy || _pass.text.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await widget.store.setPassword(_pass.text, force: force);
    if (!mounted) return;
    // On success the home screen replaces this one.
    if (!ok) setState(() => _failed = true);
    setState(() => _busy = false);
  }

  Future<void> _typeOnTv() async {
    // On a TV the password is typed with the remote, so it's shown while
    // typing (dots would make remote typing guesswork).
    await RemoteEntry.open(context, _pass, label: 'Camera password', mono: true);
    if (mounted && _pass.text.isNotEmpty) await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final cams = widget.store.cameras.length;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Glass(
                blur: false,
                radius: 26,
                padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NetSeye', style: Typo.display(34)),
                    const SizedBox(height: 10),
                    Text(
                      'Enter the camera password once to connect '
                      '${cams == 1 ? 'your camera' : 'your $cams cameras'}. '
                      'It stays encrypted on this device and is never shared.',
                      style: Typo.small.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    RemoteEntry(
                      onOpen: _typeOnTv,
                      child: TextField(
                        controller: _pass,
                        autofocus: true,
                        readOnly: Device.isTv,
                        onTap: Device.isTv ? _typeOnTv : null,
                        obscureText: !_show,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: Typo.mono(color: Palette.bone, size: 15),
                        onSubmitted: (_) => _connect(),
                        onChanged: (_) {
                          if (_failed) setState(() => _failed = false);
                        },
                        decoration: InputDecoration(
                          labelText: 'Camera password',
                          suffixIcon: Device.isTv
                              ? null
                              : IconButton(
                                  tooltip: _show ? 'Hide password' : 'Show password',
                                  onPressed: () => setState(() => _show = !_show),
                                  icon: Icon(
                                    _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 18,
                                    color: Palette.ash,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          "No camera accepted that password. Check it, and that this device is on the home Wi-Fi.",
                          style: Typo.small.copyWith(color: Palette.ember),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Semantics(
                      button: true,
                      label: 'Connect',
                      excludeSemantics: true,
                      onTap: _busy ? null : _connect,
                      child: Pressable(
                        onTap: _busy ? null : _connect,
                        focusRadius: 14,
                        focusColor: Palette.bone,
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Palette.accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Palette.onAccent),
                                )
                              : Text('Connect', style: Typo.button.copyWith(color: Palette.onAccent)),
                        ),
                      ),
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 8),
                      Pressable(
                        onTap: _busy ? null : () => _connect(force: true),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'Cameras are off right now? Save it anyway',
                            textAlign: TextAlign.center,
                            style: Typo.small.copyWith(color: Palette.accent),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
