import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/device.dart';

/// A pane of frosted glass: whatever is behind it is blurred and lifted,
/// with a soft sheen from the top and a bright hairline edge. Corners are
/// Apple-style continuous curves (superellipse), not plain circles.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = true,
    this.padding,
    this.tint,
    this.pill = false,
  });

  final Widget child;
  final double radius;

  /// Blur what's behind. Only worth it over pictures; over the plain
  /// backdrop the sheen alone reads as glass and costs nothing.
  final bool blur;
  final EdgeInsetsGeometry? padding;

  /// Optional colour wash (e.g. the accent for a selected control).
  final Color? tint;

  /// Fully rounded ends (buttons, docks).
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final r = pill ? BorderRadius.circular(999) : BorderRadius.circular(radius);
    final body = DecoratedBox(
      decoration: ShapeDecoration(
        shape: continuousShape(r, side: const BorderSide(color: Palette.line, width: 0.8)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tint == null
              ? const [Color(0x2EFFFFFF), Color(0x0FFFFFFF)]
              : [tint!.withValues(alpha: 0.95), tint!.withValues(alpha: 0.8)],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    // Live blur re-renders whatever is behind on every video frame: fine on
    // a phone, too much for a TV's GPU. On TV the tinted sheen stands in.
    if (blur && !Device.isTv) {
      // Blur needs a clip to stay inside the shape. Without blur the shape
      // already draws its own edge, so no (costly) clip is needed.
      return ClipRSuperellipse(
        borderRadius: r,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: body),
      );
    }
    return body;
  }
}

/// Apple-style continuous corners on phones. On TVs, plain rounded
/// rectangles: they look the same from the sofa, and old TV GPUs draw them
/// on a fast path where superellipse curves cost several ms per panel.
OutlinedBorder continuousShape(BorderRadius r, {BorderSide side = BorderSide.none}) => Device.isTv
    ? RoundedRectangleBorder(borderRadius: r, side: side)
    : RoundedSuperellipseBorder(borderRadius: r, side: side);

/// Clip to the same shape as [continuousShape].
Widget continuousClip(BorderRadius r, Widget child) =>
    Device.isTv ? ClipRRect(borderRadius: r, child: child) : ClipRSuperellipse(borderRadius: r, child: child);

/// The softly lit room behind every screen: deep ink with two slow pools
/// of colour, so glass panels have something to catch.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: _Glow()),
        child,
      ],
    );
  }
}

/// The glow is rendered once into a small image and stretched to fill the
/// screen. Drawing three full-screen gradients live costs ~30 ms a frame on a
/// TV GPU (every video frame redraws the screen); one stretched image costs
/// almost nothing and looks the same, since the glow is soft anyway.
class _Glow extends StatelessWidget {
  const _Glow();

  static final ui.Image _image = _render();

  static ui.Image _render() {
    const w = 320.0, h = 180.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h))..drawColor(Palette.ink, BlendMode.src);
    void pool(Alignment at, double radius, Color color) {
      final center = at.alongSize(const Size(w, h));
      final r = radius * h; // matches RadialGradient: fraction of the shorter side
      c.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()..shader = ui.Gradient.radial(center, r, [color, const Color(0x0007080C)]),
      );
    }

    pool(const Alignment(-0.85, -0.95), 1.25, const Color(0xFF16254F));
    pool(const Alignment(1.0, 1.0), 1.1, const Color(0xFF2A1745));
    pool(const Alignment(0.9, -0.6), 0.7, const Color(0x330B5563));
    return rec.endRecording().toImageSync(w.toInt(), h.toInt());
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, fit: BoxFit.fill, filterQuality: FilterQuality.low);
}
