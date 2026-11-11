import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/glass.dart';
import 'ptz_driver.dart';

/// Four hold-to-move arrows. Press and hold an arrow and the camera turns
/// that way; let go and it stops. Works by touch and with a TV remote
/// (focus an arrow, hold OK).
class ArrowPad extends StatelessWidget {
  const ArrowPad({super.key, required this.driver, this.onInteract});
  final PtzDriver driver;
  final VoidCallback? onInteract;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, Offset dir, String label) => _HoldButton(
      icon: icon,
      label: label,
      onHold: () {
        driver.drive(dir);
        onInteract?.call();
      },
      onRelease: driver.stop,
    );

    return Glass(
      pill: true,
      tint: const Color(0x59000000),
      child: SizedBox(
        width: 168,
        height: 168,
        child: FocusTraversalGroup(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: arrow(Icons.keyboard_arrow_up_rounded, const Offset(0, -1), 'Turn up'),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: arrow(Icons.keyboard_arrow_down_rounded, const Offset(0, 1), 'Turn down'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: arrow(Icons.keyboard_arrow_left_rounded, const Offset(-1, 0), 'Turn left'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: arrow(Icons.keyboard_arrow_right_rounded, const Offset(1, 0), 'Turn right'),
              ),
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.slate),
                  child: const Icon(Icons.control_camera_rounded, size: 20, color: Palette.ash),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button that keeps acting while held (touch, or OK held on a remote).
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.icon, required this.label, required this.onHold, required this.onRelease});
  final IconData icon;
  final String label;
  final VoidCallback onHold;
  final VoidCallback onRelease;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;
  bool _focused = false;
  Timer? _repeat;

  void _press() {
    if (_down) return;
    setState(() => _down = true);
    widget.onHold();
    // Re-send while held so the camera keeps turning.
    _repeat = Timer.periodic(const Duration(milliseconds: 600), (_) => widget.onHold());
  }

  void _release() {
    if (!_down) return;
    _repeat?.cancel();
    setState(() => _down = false);
    widget.onRelease();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    if (_down) widget.onRelease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (!f) _release();
        },
        onKeyEvent: (node, e) {
          final k = e.logicalKey;
          final ok =
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter;
          if (!ok) return KeyEventResult.ignored;
          if (e is KeyDownEvent) _press();
          if (e is KeyUpEvent) _release();
          return KeyEventResult.handled;
        },
        child: Listener(
          onPointerDown: (_) => _press(),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: AnimatedContainer(
            duration: Motion.quick,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _down ? Palette.accent : Colors.transparent,
              border: Border.all(color: _focused ? Palette.accent : Colors.transparent, width: 2.5),
            ),
            child: Icon(widget.icon, size: 30, color: _down ? Palette.onAccent : Palette.bone),
          ),
        ),
      ),
    );
  }
}
