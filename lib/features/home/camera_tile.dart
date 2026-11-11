import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/camera.dart';
import '../../services/live_feed.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/glass.dart';
import '../../widgets/pressable.dart';
import '../../services/device.dart';

class CameraTile extends StatelessWidget {
  const CameraTile({
    super.key,
    required this.camera,
    required this.feed,
    required this.onOpen,
    required this.onEdit,
    this.autofocus = false,
  });

  final Camera camera;
  final LiveFeed? feed;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  /// First tile takes focus, so a TV remote starts on a camera.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Rebuild when the feed's state changes so the screen-reader label
    // ("live", "connecting"...) stays true. The picture itself is keyed per
    // engine, so this does not restart the video.
    final f = feed;
    if (f == null) return _tile(context);
    return ListenableBuilder(listenable: f, builder: (context, _) => _tile(context));
  }

  Widget _tile(BuildContext context) {
    final status = switch (feed?.state) {
      FeedState.live => 'live',
      FeedState.failed => "can't reach camera",
      null => 'looking for camera',
      _ => 'connecting',
    };
    return Semantics(
      button: true,
      label: [camera.name, if (camera.room.isNotEmpty) camera.room, status].join(', '),
      hint: 'Opens full screen',
      onLongPressHint: 'Edit camera',
      excludeSemantics: true,
      onTap: onOpen,
      onLongPress: onEdit,
      child: Pressable(
        autofocus: autofocus,
        focusRadius: 26,
        onTap: onOpen,
        onLongPress: onEdit,
        depth: 0.975,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          // Glass edge drawn over the picture, Apple-style continuous corners.
          decoration: ShapeDecoration(
            shape: continuousShape(
              BorderRadius.circular(26),
              side: const BorderSide(color: Palette.line, width: 0.8),
            ),
          ),
          // TV: no clipping of live video (an expensive mask on old GPUs,
          // redone every video frame). Square video, with the rounded corners
          // painted over it in the wall's background colour instead.
          child: (Device.isTv ? (Widget c) => c : (Widget c) => continuousClip(BorderRadius.circular(26), c))(
            Stack(
              fit: StackFit.expand,
              children: [
                feed == null
                    ? ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Text('FINDING CAMERA', style: Typo.label(color: Palette.dusk)),
                        ),
                      )
                    : FeedView(feed: feed!),
                // Soft scrim so the name always reads, never a hard bar.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.22, 0.55, 1],
                      colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 14,
                  child: feed == null
                      ? const SizedBox.shrink()
                      : ListenableBuilder(
                          listenable: feed!,
                          builder: (_, _) => _Status(state: feed!.state),
                        ),
                ),
                if (Device.isTv)
                  const IgnorePointer(child: CustomPaint(painter: _Corners(26, Color(0xFF0B0D14)))),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (camera.room.isNotEmpty) ...[
                        Text(
                          camera.room.toUpperCase(),
                          style: Typo.label(color: Palette.bone.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        camera.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.display(24),
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
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final FeedState state;

  @override
  Widget build(BuildContext context) {
    final live = state == FeedState.live;
    return AnimatedOpacity(
      opacity: live ? 1 : 0,
      duration: Motion.base,
      child: Glass(
        pill: true,
        blur: !Device.isTv, // a TV's GPU is better spent on the video
        tint: const Color(0x66000000),
        padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(active: live),
            const SizedBox(width: 4),
            Text('LIVE', style: Typo.label(color: Palette.bone, size: 10)),
          ],
        ),
      ),
    );
  }
}

/// Paints the four outside corners of a rounded rectangle in a solid
/// colour: rounded-looking video without clipping it.
class _Corners extends CustomPainter {
  const _Corners(this.r, this.color);
  final double r;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    void corner(double x, double y, double sx, double sy) {
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + sx * r, y)
        ..arcToPoint(Offset(x, y + sy * r), radius: Radius.circular(r), clockwise: sx * sy < 0)
        ..close();
      canvas.drawPath(path, p);
    }

    corner(0, 0, 1, 1);
    corner(size.width, 0, -1, 1);
    corner(0, size.height, 1, -1);
    corner(size.width, size.height, -1, -1);
  }

  @override
  bool shouldRepaint(_Corners old) => old.r != r || old.color != color;
}
