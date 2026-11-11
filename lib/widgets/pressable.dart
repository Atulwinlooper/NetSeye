import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Gentle press feedback: the surface sinks a little under the finger and
/// settles back. Also the app's focus target for TV remotes and keyboards:
/// the focused control lifts slightly and gets a sodium outline, and
/// OK / Enter / Space activate it. (The outline only shows when navigating
/// by keys, never on touch.)
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.depth = 0.97,
    this.haptic = true,
    this.focusNode,
    this.autofocus = false,
    this.focusRadius = 16,
    this.focusColor = Palette.accent,
  });

  /// Outline colour when focused. Use a contrasting one on controls that
  /// are themselves sodium (a toggled-on button), or the ring disappears.
  final Color focusColor;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double depth;
  final bool haptic;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Corner radius of the focus outline (match the child's shape).
  final double focusRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  void _activate() {
    if (widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final lift = _down ? widget.depth : (_focused ? 1.035 : 1.0);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate())},
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null ? null : _activate,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: lift,
          duration: _down ? Motion.quick : Motion.base,
          curve: Motion.ease,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.4,
            duration: Motion.base,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.focusRadius),
                border: Border.all(color: _focused ? widget.focusColor : Colors.transparent, width: 2.5),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
