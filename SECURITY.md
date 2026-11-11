# Security

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them
privately through GitHub's
[private vulnerability reporting](https://github.com/Atulwinlooper/NetSeye/security/advisories/new)
for this repository. Include the steps to reproduce, the affected version
and the impact you expect.

You can expect an acknowledgement within a week. Fixes are released as a new
version, and the advisory is published once users have had a chance to
update.

## Supported versions

Only the latest release receives security fixes.

## How NetSeye handles your data

- **No internet, no cloud.** The app connects only to the camera (and
  optional home hub) addresses you enter. It contains no analytics, ads or
  telemetry and never contacts an outside server.
- **Camera password is never in the app or this repository.** Each device
  asks for it on first open, checks it against the cameras, and stores it
  with the camera list in Android's encrypted storage (Android Keystore,
  via `flutter_secure_storage`).
- **No backups of credentials.** App data is excluded from Android cloud
  backup and device-to-device transfer.
- **Build secrets stay local.** Camera addresses for a build come from
  `secrets.json`, and release signing from `android/key.properties` and a
  keystore. All of these are git-ignored and must never be committed.
- **Release builds** are obfuscated and log nothing about camera connections.
- **Location permission** is requested only because Android requires it
  before an app may read the Wi-Fi network name, which NetSeye displays.
  Location itself is never read or stored. Declining it is fine; the app
  then shows the device's local IP address instead.

## Known limitations (outside the app's control)

- **Cameras speak plain HTTP (ONVIF) and RTSP without TLS**, so cleartext
  traffic is allowed app-wide (Android can't scope it to private IPs). Stream
  links and ONVIF requests travel unencrypted on your local network; ONVIF
  passwords are sent as WS-Security digests, not plain text. Keep cameras on
  a trusted network.
- **Some camera firmware serves video without any password.** Anyone on the
  same Wi-Fi may be able to watch such a camera with any RTSP player. Put
  guests on a separate guest network.
- **Local RTSP relay.** For compatibility, the app runs a small relay bound
  to `127.0.0.1` (never reachable from the network) while a camera is open.
  It forwards to that one camera only, rejects oversized messages, and stops
  when the stream closes.
- **Sideloaded APKs.** Install NetSeye only from this repository's releases or
  from your own build, and keep your signing key private: updates must be
  signed with the same key.
