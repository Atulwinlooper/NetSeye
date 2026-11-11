import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/routes.dart';
import '../app/theme.dart';
import '../services/device.dart';
import 'pressable.dart';

/// On a TV, text fields don't open the system keyboard: Flutter takes the
/// remote's arrow keys before the system keyboard can, so it can't be used.
/// Instead OK on a field opens [RemoteKeyboard], built for a remote.
///
/// Wrap a field with this and give the field `readOnly: Device.isTv` and
/// `onTap: () => RemoteEntry.open(...)`.
class RemoteEntry extends StatelessWidget {
  const RemoteEntry({super.key, required this.onOpen, required this.child});
  final VoidCallback onOpen;
  final Widget child;

  static Future<void> open(
    BuildContext context,
    TextEditingController c, {
    required String label,
    List<String> suggestions = const [],
    bool mono = false,
    bool obscure = false,
    bool capitalize = false,
    VoidCallback? onChanged,
  }) async {
    final text = await Navigator.of(context).push<String>(
      fadeThroughRoute(
        RemoteKeyboard(
          label: label,
          initial: c.text,
          suggestions: suggestions,
          mono: mono,
          obscure: obscure,
          capitalize: capitalize,
        ),
      ),
    );
    if (text != null && text != c.text) {
      c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Device.isTv) return child;
    void go() => onOpen();
    // The field is read-only on a TV, so arrows have no cursor to move:
    // make them move between controls instead of getting stuck in the field.
    void move(TraversalDirection d) => FocusManager.instance.primaryFocus?.focusInDirection(d);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.select): go,
        const SingleActivator(LogicalKeyboardKey.enter): go,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): go,
        const SingleActivator(LogicalKeyboardKey.gameButtonA): go,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(TraversalDirection.right),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => move(TraversalDirection.down),
      },
      child: child,
    );
  }
}

/// A full-screen keyboard you drive with arrows and OK. Quick picks first
/// (most names are one of a few), then the letters. Back cancels.
class RemoteKeyboard extends StatefulWidget {
  const RemoteKeyboard({
    super.key,
    required this.label,
    required this.initial,
    this.suggestions = const [],
    this.mono = false,
    this.obscure = false,
    this.capitalize = false,
  });

  final String label;
  final String initial;
  final List<String> suggestions;
  final bool mono, obscure, capitalize;

  @override
  State<RemoteKeyboard> createState() => _RemoteKeyboardState();
}

class _RemoteKeyboardState extends State<RemoteKeyboard> {
  late String _text = widget.initial;
  bool _shift = false;
  bool _symbols = false;

  static const _letters = ['abcdefghijklm', 'nopqrstuvwxyz'];
  static const _digits = '1234567890';
  static const _marks = '.-_:/@+&#\'()';

  /// Capital at the start of each word for names, unless shift says otherwise.
  bool get _upper {
    final autoCap = widget.capitalize && (_text.isEmpty || _text.endsWith(' '));
    return autoCap != _shift;
  }

  void _type(String s) {
    HapticFeedback.selectionClick();
    setState(() {
      _text += _upper && s.length == 1 ? s.toUpperCase() : s;
      _shift = false;
    });
  }

  void _back() => setState(() {
    if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
  });

  void _done() => Navigator.of(context).pop(_text.trim());

  @override
  Widget build(BuildContext context) {
    final shown = widget.obscure ? '•' * _text.length : _text;
    final upper = _upper;
    // Typed characters (a keyboard, or the phone remote app's text box) go
    // straight in; arrows/OK still drive the on-screen keys.
    return Focus(
      // Only listens to keys bubbling up from the on-screen keys; never
      // takes focus itself.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final ch = e.character;
        if (e.logicalKey == LogicalKeyboardKey.backspace) {
          _back();
          return KeyEventResult.handled;
        }
        if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x20 && ch.codeUnitAt(0) != 0x7f) {
          setState(() {
            _text += ch;
            _shift = false;
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label.toUpperCase(), style: Typo.label(color: Palette.accent)),
                    const SizedBox(height: 10),
                    // What's been typed, with a caret.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Palette.coal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: shown,
                              style: widget.mono
                                  ? Typo.mono(size: 24, color: Palette.bone)
                                  : Typo.display(36),
                            ),
                            TextSpan(
                              text: '|',
                              style: Typo.display(36, color: Palette.accent),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      // One row of quick picks; scrolls sideways if it must.
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        child: Row(
                          children: [
                            for (final (i, s) in widget.suggestions.indexed) ...[
                              if (i > 0) const SizedBox(width: 8),
                              _Key(
                                label: s,
                                wide: true,
                                autofocus: i == 0,
                                onTap: () => setState(() {
                                  _text = s;
                                  _shift = false;
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: FocusTraversalGroup(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!_symbols)
                              for (final (r, row) in _letters.indexed)
                                _row([
                                  for (final (i, ch) in row.split('').indexed)
                                    _Key(
                                      label: upper ? ch.toUpperCase() : ch,
                                      autofocus: r == 0 && i == 0 && widget.suggestions.isEmpty,
                                      onTap: () => _type(ch),
                                    ),
                                ])
                            else ...[
                              _row([
                                for (final ch in _digits.split('')) _Key(label: ch, onTap: () => _type(ch)),
                              ]),
                              _row([
                                for (final ch in _marks.split('')) _Key(label: ch, onTap: () => _type(ch)),
                              ]),
                            ],
                            if (!_symbols)
                              _row([
                                for (final ch in _digits.split('')) _Key(label: ch, onTap: () => _type(ch)),
                              ]),
                            _row([
                              _Key(
                                icon: Icons.arrow_upward_rounded,
                                label: 'Shift',
                                on: upper,
                                onTap: () => setState(() => _shift = !_shift),
                              ),
                              _Key(
                                label: _symbols ? 'abc' : '.-@',
                                onTap: () => setState(() => _symbols = !_symbols),
                              ),
                              _Key(label: 'Space', flex: 4, onTap: () => _type(' ')),
                              _Key(icon: Icons.backspace_outlined, label: 'Delete', onTap: _back),
                              _Key(label: 'Clear', onTap: () => setState(() => _text = '')),
                              _Key(label: 'Done', flex: 2, primary: true, onTap: _done),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Back to cancel', style: Typo.small.copyWith(color: Palette.dusk)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        for (final (i, k) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(flex: k is _Key ? k.flex : 1, child: k),
        ],
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.icon,
    this.flex = 1,
    this.wide = false,
    this.on = false,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final int flex;
  final bool wide, on, primary, autofocus;

  @override
  Widget build(BuildContext context) {
    final filled = primary || on;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        autofocus: autofocus,
        focusRadius: 12,
        focusColor: filled ? Palette.bone : Palette.accent,
        haptic: false,
        child: Container(
          height: 48,
          padding: wide ? const EdgeInsets.symmetric(horizontal: 18) : EdgeInsets.zero,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Palette.accent : Palette.slate,
            borderRadius: BorderRadius.circular(12),
          ),
          child: icon != null && label.length > 1 && !primary
              ? Icon(icon, size: 20, color: filled ? Palette.onAccent : Palette.bone)
              : Text(
                  label,
                  style: (label.length == 1 ? Typo.mono(size: 18) : Typo.button).copyWith(
                    color: filled ? Palette.onAccent : Palette.bone,
                  ),
                ),
        ),
      ),
    );
  }
}
