import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/camera_store.dart';
import '../../data/validate.dart';
import '../../models/camera.dart';
import '../../services/onvif.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../../widgets/remote_keyboard.dart';
import '../../services/device.dart';

/// Add or edit one camera. "Find streams" asks the camera itself for
/// its video links, so nobody has to type long RTSP addresses.
class CameraEditor extends StatefulWidget {
  const CameraEditor({super.key, required this.store, this.camera});
  final CameraStore store;
  final Camera? camera;

  @override
  State<CameraEditor> createState() => _CameraEditorState();
}

class _CameraEditorState extends State<CameraEditor> {
  final _form = GlobalKey<FormState>();
  late final Camera? _orig = widget.camera;
  late final _name = TextEditingController(text: _orig?.name ?? '');
  late final _room = TextEditingController(text: _orig?.room ?? '');
  late final _host = TextEditingController(text: _orig?.host ?? '');
  late final _user = TextEditingController(text: _orig?.onvifUser ?? 'admin');
  late final _pass = TextEditingController(text: _orig?.onvifPassword ?? '');
  late final _main = TextEditingController(text: _orig?.mainUrl ?? '');
  late final _sub = TextEditingController(text: _orig?.subUrl ?? '');

  static const _nameIdeas = [
    'Front door',
    'Hall',
    'Rooftop',
    'Gate',
    'Parking',
    'Living room',
    'Kitchen',
    'Backyard',
  ];
  static const _roomIdeas = ['Entrance', 'Hall', 'Terrace', 'Garden', 'Garage', 'Kitchen', 'Stairs'];

  bool _finding = false;
  bool _saving = false;
  bool _showPass = false;
  String? _note;
  bool _noteIsError = false;

  @override
  void dispose() {
    for (final c in [_name, _room, _host, _user, _pass, _main, _sub]) {
      c.dispose();
    }
    super.dispose();
  }

  Camera _draft() => Camera(
    id: _orig?.id ?? widget.store.newId(),
    name: _name.text.trim().isEmpty ? 'Camera' : _name.text.trim(),
    room: _room.text.trim(),
    host: _host.text.trim(),
    mainUrl: _main.text.trim(),
    subUrl: _sub.text.trim().isEmpty ? _main.text.trim() : _sub.text.trim(),
    onvifPort: _orig?.onvifPort ?? 8000,
    onvifUser: _user.text.trim(),
    onvifPassword: _pass.text,
    // Same address: still the same camera. A new address the user typed:
    // learn which camera is there afresh.
    mac: _orig != null && _orig.host == _host.text.trim() ? _orig.mac : '',
  );

  void _say(String text, {bool error = false}) => setState(() {
    _note = text;
    _noteIsError = error;
  });

  Future<void> _find() async {
    final problem = Validate.host(_host.text);
    if (problem != null) return _say(problem, error: true);
    setState(() {
      _finding = true;
      _note = null;
    });
    try {
      final (hd, light) = await OnvifClient(_draft()).discoverStreams();
      if (hd == null) throw const FormatException('no streams');
      _main.text = hd;
      _sub.text = light ?? hd;
      _say('Found the streams.');
    } on Exception {
      _say(
        "Couldn't ask the camera. Check the address, and that ONVIF is on with this password.",
        error: true,
      );
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await widget.store.upsert(_draft());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Palette.coal,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove ${_orig!.name}?', style: Typo.display(30)),
              const SizedBox(height: 8),
              Text('It disappears from this phone only. The camera itself keeps working.', style: Typo.small),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(label: 'Keep it', onTap: () => Navigator.pop(ctx, false)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetButton(label: 'Remove', danger: true, onTap: () => Navigator.pop(ctx, true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await widget.store.remove(_orig!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    if (size.width >= 900 && size.width > size.height * 1.3) return _wide(context);
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  // Header stays put, so Save is always within reach.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Close without saving',
                          excludeSemantics: true,
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Pressable(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.close_rounded, color: Palette.bone),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Semantics(
                          button: true,
                          label: 'Save camera',
                          excludeSemantics: true,
                          onTap: _saving ? null : _save,
                          child: Pressable(
                            onTap: _saving ? null : _save,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                              decoration: BoxDecoration(
                                color: Palette.accent,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text('Save', style: Typo.button.copyWith(color: Palette.onAccent)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Form(
                      key: _form,
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + bottomInset),
                        children: [
                          ListenableBuilder(
                            listenable: _name,
                            builder: (_, _) => Text(
                              _name.text.trim().isNotEmpty
                                  ? _name.text.trim()
                                  : (_orig == null ? 'New camera' : 'Camera'),
                              style: Typo.display(40),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _group('Name it'),
                          _field(
                            _name,
                            'Name',
                            hint: 'Front door',
                            capitalize: true,
                            suggestions: _nameIdeas,
                          ),
                          _field(
                            _room,
                            'Where it is',
                            hint: 'Entrance, hall, rooftop',
                            capitalize: true,
                            suggestions: _roomIdeas,
                          ),
                          _group('Connection'),
                          _field(
                            _host,
                            'Camera address',
                            hint: '192.168.1.33',
                            mono: true,
                            keyboard: TextInputType.url,
                            validator: Validate.host,
                          ),
                          _field(_user, 'ONVIF username', mono: true),
                          _field(
                            _pass,
                            'ONVIF password',
                            mono: true,
                            obscure: !_showPass,
                            suffix: IconButton(
                              tooltip: _showPass ? 'Hide password' : 'Show password',
                              onPressed: () => setState(() => _showPass = !_showPass),
                              icon: Icon(
                                _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 18,
                                color: Palette.ash,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Pressable(
                            onTap: _finding ? null : _find,
                            child: Container(
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Palette.accent.withValues(alpha: 0.6)),
                              ),
                              alignment: Alignment.center,
                              child: _finding
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.accent),
                                    )
                                  : Text('Find streams', style: Typo.button.copyWith(color: Palette.accent)),
                            ),
                          ),
                          AnimatedSize(
                            duration: Motion.base,
                            curve: Motion.ease,
                            child: _note == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _note!,
                                        style: Typo.small.copyWith(
                                          color: _noteIsError ? Palette.ember : Palette.moss,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          _group('Streams'),
                          _field(
                            _main,
                            'HD stream',
                            mono: true,
                            small: true,
                            maxLines: 4,
                            validator: Validate.stream,
                          ),
                          _field(
                            _sub,
                            'Light stream',
                            mono: true,
                            small: true,
                            maxLines: 4,
                            validator: (v) => Validate.stream(v, optional: true),
                          ),
                          if (_orig != null) ...[
                            const SizedBox(height: 32),
                            Center(
                              child: Pressable(
                                onTap: _delete,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'Remove this camera',
                                    style: Typo.button.copyWith(color: Palette.ember),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// TV / wide layout: one screen, three glass panels side by side
  /// (name, connection, streams) under a header with Close and Save.
  Widget _wide(BuildContext context) {
    Widget panel(String title, List<Widget> children) => Glass(
      blur: false,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: Typo.label(color: Palette.accent)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 36, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Close without saving',
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
                            child: Icon(Icons.close_rounded, color: Palette.bone),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _name,
                        builder: (_, _) => Text(
                          _name.text.trim().isNotEmpty
                              ? _name.text.trim()
                              : (_orig == null ? 'New camera' : 'Camera'),
                          style: Typo.display(32),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_orig != null) ...[
                      Pressable(
                        onTap: _delete,
                        focusRadius: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          child: Text('Remove', style: Typo.button.copyWith(color: Palette.ember)),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Semantics(
                      button: true,
                      label: 'Save camera',
                      excludeSemantics: true,
                      onTap: _saving ? null : _save,
                      child: Pressable(
                        onTap: _saving ? null : _save,
                        focusRadius: 100,
                        focusColor: Palette.bone,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                          decoration: BoxDecoration(
                            color: Palette.accent,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text('Save', style: Typo.button.copyWith(color: Palette.onAccent)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: panel('Name it', [
                          _field(
                            _name,
                            'Name',
                            hint: 'Front door',
                            capitalize: true,
                            suggestions: _nameIdeas,
                          ),
                          _field(
                            _room,
                            'Where it is',
                            hint: 'Entrance, hall, rooftop',
                            capitalize: true,
                            suggestions: _roomIdeas,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Press OK on a field to type with the remote.',
                              style: Typo.small.copyWith(color: Palette.dusk),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: panel('Connection', [
                          _field(
                            _host,
                            'Camera address',
                            hint: '192.168.1.33',
                            mono: true,
                            keyboard: TextInputType.url,
                            validator: Validate.host,
                          ),
                          _field(_user, 'ONVIF username', mono: true),
                          _field(_pass, 'ONVIF password', mono: true, obscure: true),
                          Pressable(
                            onTap: _finding ? null : _find,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Palette.accent.withValues(alpha: 0.6)),
                              ),
                              alignment: Alignment.center,
                              child: _finding
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.accent),
                                    )
                                  : Text('Find streams', style: Typo.button.copyWith(color: Palette.accent)),
                            ),
                          ),
                          if (_note != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _note!,
                                  style: Typo.small.copyWith(
                                    color: _noteIsError ? Palette.ember : Palette.moss,
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: panel('Streams', [
                          _field(
                            _main,
                            'HD stream',
                            mono: true,
                            small: true,
                            maxLines: 3,
                            validator: Validate.stream,
                          ),
                          _field(
                            _sub,
                            'Light stream',
                            mono: true,
                            small: true,
                            maxLines: 3,
                            validator: (v) => Validate.stream(v, optional: true),
                          ),
                          Text(
                            '"Find streams" fills these in from the camera.',
                            style: Typo.small.copyWith(color: Palette.dusk),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(String t) => Padding(
    padding: const EdgeInsets.only(top: 32, bottom: 12),
    child: Semantics(
      header: true,
      child: Text(t.toUpperCase(), style: Typo.label(color: Palette.accent)),
    ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool mono = false,
    bool small = false,
    bool obscure = false,
    bool capitalize = false,
    int maxLines = 1,
    TextInputType? keyboard,
    Widget? suffix,
    String? Function(String)? validator,
    List<String> suggestions = const [],
  }) {
    void openRemote() => RemoteEntry.open(
      context,
      c,
      label: label,
      suggestions: suggestions,
      mono: mono,
      obscure: obscure,
      capitalize: capitalize,
      onChanged: () => setState(() {}),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RemoteEntry(
        onOpen: openRemote,
        child: TextFormField(
          controller: c,
          // TV: no system keyboard (unusable with a remote); OK opens ours.
          readOnly: Device.isTv,
          // TV: start on the name, the thing most people come here to change.
          autofocus: Device.isTv && identical(c, _name),
          onTap: Device.isTv ? openRemote : null,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          minLines: 1,
          keyboardType: keyboard,
          autocorrect: !mono,
          enableSuggestions: !mono && !obscure,
          textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator == null ? null : (v) => validator(v ?? ''),
          style: mono ? Typo.mono(color: Palette.bone, size: small ? 12.5 : 14) : Typo.body,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: suffix,
            errorStyle: Typo.small.copyWith(color: Palette.ember, fontSize: 12),
            errorMaxLines: 2,
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger ? Palette.ember : Palette.slate,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label, style: Typo.button.copyWith(color: Palette.bone)),
      ),
    );
  }
}
