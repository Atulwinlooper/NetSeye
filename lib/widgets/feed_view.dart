import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/live_feed.dart';
import 'pressable.dart';

/// The video surface plus its quiet states: connecting, reconnecting,
/// and a calm "can't reach" card with a retry.
class FeedView extends StatelessWidget {
  const FeedView({super.key, required this.feed, this.fit = BoxFit.cover, this.compact = true});

  final LiveFeed feed;
  final BoxFit fit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final live = feed.state == FeedState.live;
        // Reconnecting behind the last picture: keep it up, with a small
        // note instead of a blank "reconnecting" screen.
        final holding = !live && feed.hasPicture;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF0B0A09)),
            AnimatedOpacity(
              opacity: live || holding ? 1 : 0,
              duration: Motion.slow,
              curve: Motion.ease,
              child: _Picture(feed: feed, fit: fit),
            ),
            AnimatedSwitcher(
              duration: Motion.base,
              switchInCurve: Motion.ease,
              switchOutCurve: Motion.ease,
              child: switch (feed.state) {
                FeedState.live => const SizedBox.shrink(key: ValueKey('live')),
                FeedState.connecting => _Waiting(
                  key: const ValueKey('c'),
                  text: 'Connecting',
                  compact: compact,
                ),
                FeedState.retrying when holding => Align(
                  key: const ValueKey('h'),
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x8C000000),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('RECONNECTING', style: Typo.label(size: 9, color: Palette.bone)),
                    ),
                  ),
                ),
                FeedState.retrying => _Waiting(
                  key: const ValueKey('r'),
                  text: 'Reconnecting',
                  compact: compact,
                ),
                FeedState.failed => _Failed(
                  key: const ValueKey('f'),
                  onRetry: feed.reconnect,
                  compact: compact,
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.text, required this.compact});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _ScanLine(),
          const SizedBox(height: 12),
          Text(text.toUpperCase(), style: Typo.label(color: Palette.dusk)),
        ],
      ),
    );
  }
}

/// A slow amber sweep, like a light passing over a lens.
class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: ColoredBox(
          color: Palette.line,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = Curves.easeInOutCubic.transform(_c.value);
              return FractionallySizedBox(
                alignment: Alignment(-1.6 + 3.2 * t, 0),
                widthFactor: 0.35,
                child: const ColoredBox(color: Palette.accent),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({super.key, required this.onRetry, required this.compact});
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Can't reach this camera", style: Typo.bodyStrong, textAlign: TextAlign.center),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                'Check that it has power and is on the home Wi-Fi.',
                style: Typo.small,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 14),
            Pressable(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: Palette.accent.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('Try again', style: Typo.button.copyWith(color: Palette.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pulsing ember dot shown next to "Live".
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.active = true});
  final bool active;
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Palette.ember : Palette.dusk;
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: 6 + 8 * _c.value,
                height: 6 + 8 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.35 * (1 - _c.value)),
                ),
              ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live picture from whichever engine the feed is using.
class _Picture extends StatelessWidget {
  const _Picture({required this.feed, required this.fit});
  final LiveFeed feed;
  final BoxFit fit;

  @override
  // The native video view is only a picture: keep it out of focus (or a TV
  // remote's arrows would land inside it, invisibly) and out of touch.
  Widget build(BuildContext context) => ExcludeFocus(child: IgnorePointer(child: feed.view(fit)));
}
