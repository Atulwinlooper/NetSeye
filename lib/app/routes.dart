import 'package:flutter/material.dart';

import 'theme.dart';
import '../services/device.dart';

/// Opening a camera: the tile's picture flies up (Hero) while the
/// surroundings dissolve, so it feels like leaning in, not changing page.
/// TVs: a quick fade of the new screen over the old one (opacity only, no
/// movement, so it's cheap for a TV GPU and never flickers).
Route<T> _tvRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 180),
  reverseTransitionDuration: const Duration(milliseconds: 150),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
    child: child,
  ),
);

Route<T> fadeThroughRoute<T>(Widget page) => Device.isTv
    ? _tvRoute<T>(page)
    : PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 460),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, anim, _, child) {
          final a = CurvedAnimation(parent: anim, curve: Motion.glide, reverseCurve: Motion.ease);
          return FadeTransition(opacity: a, child: child);
        },
      );

/// Secondary screens glide in from the side with a soft fade, while
/// the screen underneath drifts back a touch.
Route<T> slideRoute<T>(Widget page) => Device.isTv
    ? _tvRoute<T>(page)
    : PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, anim, secondary, child) {
          final a = CurvedAnimation(parent: anim, curve: Motion.glide, reverseCurve: Motion.ease);
          final back = CurvedAnimation(parent: secondary, curve: Motion.glide);
          return SlideTransition(
            position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(a),
            child: FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: Offset.zero, end: const Offset(-0.04, 0)).animate(back),
                child: child,
              ),
            ),
          );
        },
      );
