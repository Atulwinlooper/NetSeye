# NetSeye

Watch your CP Plus (and other ONVIF / RTSP) home cameras on Android phones
and Android TV **over your home Wi-Fi only**: no internet, no cloud
account, no server. The app talks to the cameras directly, so the cameras
stay viewable during an internet outage.

Built with Flutter. Android package: `com.winlooper.netseye`.

## Features

- Live grid of all cameras; tap (or press OK on a TV remote) for full screen
- Pan / tilt for cameras that support it (drag the picture, or hold the arrows)
- Digital zoom up to 4× (pinch, double-tap, or the + / − buttons)
- Listen to the camera's microphone
- HD / Light quality switch
- Android TV: full remote control, a 2 × 2 camera wall and an on-screen
  keyboard built for the remote
- Shows the Wi-Fi network you're on, and how many cameras are online
- Stream links are discovered automatically over ONVIF: you enter only the
  camera address and its ONVIF login
- Small: about 16 MB, using Android's own hardware video decoding

## Install

Download the APK for your device from the releases page, or build it
yourself (below), then open it on the device and allow
"Install unknown apps" if asked.

- `NetSeye.apk`: phones and tablets (64-bit ARM)
- `NetSeye-TV.apk`: Android TV and older 32-bit devices

On first open, NetSeye asks for your cameras' ONVIF password once. It is
checked against the cameras and stored encrypted on that device only.

## Using it

- **Grid:** tap a camera to open it; long-press to rename it or set its room.
  Pull down to reconnect everything.
- **Full screen:** swipe (phone) or left / right (TV) to switch cameras.
  **Listen**, **HD / Light**, **Move** and zoom controls are along the
  bottom and right edges.
- **Move mode on TV:** hold an arrow to turn the camera; **OK** or **Back**
  ends it.
- **Settings:** add, remove, reorder and edit cameras. **Find streams** asks
  a camera for its video links over ONVIF.

## Building

Requirements: Flutter 3.x (stable), Android SDK.

1. Copy `secrets.example.json` to `secrets.json` and list your cameras'
   addresses and ONVIF username (no password: each device asks for it).
   This file is git-ignored. Without it the app starts empty and cameras are
   added in Settings.
2. For signed release builds, create `android/key.properties` pointing at
   your own keystore (see the
   [Flutter docs](https://docs.flutter.dev/deployment/android#signing-the-app)).
   Without it, release builds fall back to the debug key.
3. Build:

```sh
./tool/build_apk.sh        # phones: NetSeye.apk (arm64)
./tool/build_apk.sh tv     # Android TV: NetSeye-TV.apk (32-bit, Skia renderer)
flutter test               # unit and widget tests
flutter test --tags visual --run-skipped --update-goldens   # design previews
```

Release builds are obfuscated (`--obfuscate --split-debug-info`).

Diagnostics: build with `--dart-define=PEHRA_LOG=true` and run
`adb logcat | grep NetSeye:` to see each camera's connection state;
`--dart-define=PEHRA_PERF=true` logs frame timings.

## How it works

- **Playback:** Android's Media3 / ExoPlayer plays each camera's RTSP
  stream with hardware decoding, straight into a Flutter texture
  (`android/.../ExoStreams.kt`).
- **Camera quirks:** `RtspRelay.kt` is a small relay on `127.0.0.1` that
  sits between the player and a camera over TCP. It sends the RTCP receiver
  reports some CP Plus firmware ("minirtsp") needs to keep streaming, and
  repairs the malformed stream description sent by older firmware
  ("gvminirtsp"). Video data passes through untouched.
- **Connections:** each camera tries TCP via the relay, then plain TCP, then
  UDP, and remembers what works. The full-screen view reuses the grid's
  connection, so moving between screens doesn't reconnect. If a stream
  drops, the last picture stays up while it reconnects.
- **TV:** cameras open in Light quality because many cameras' HD (above
  1080p) is beyond typical TV video decoders. HD is still available and
  falls back to Light if the TV can't play it.

Code layout: `lib/app` (theme, motion, routes) · `lib/data` (camera list,
validation) · `lib/services` (playback, ONVIF, network) · `lib/features`
(home, viewer, settings) · `lib/widgets` (shared UI) ·
`android/app/src/main/kotlin` (native playback).

## Limitations

- **Talk-back** (speaking through the camera) isn't possible on the local
  network: CP Plus cameras offer no ONVIF audio backchannel, and CP Plus
  does it only through its cloud with a private protocol.
- **One viewer per stream:** some CP Plus firmware serves each stream to only
  one viewer at a time. If two devices open the same camera, one is dropped
  and reconnects.
- **Wi-Fi quality matters:** a camera with a weak signal will drop streams
  however good the player. Check with `ping` (packet loss, high latency).
- **Power:** the router and cameras need power during an outage; a small UPS
  for the router keeps everything working.

## Security

See [SECURITY.md](SECURITY.md) for how credentials are handled and how to
report a vulnerability.

## License

NetSeye is released under the [MIT License](LICENSE).

Bundled fonts are licensed under the SIL Open Font License 1.1:
[Inter](assets/fonts/Inter-LICENSE.txt) and
[IBM Plex Mono](assets/fonts/IBMPlexMono-LICENSE.txt).
Third-party Flutter and Android libraries keep their own licenses.
