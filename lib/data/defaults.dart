import '../models/camera.dart';

// The home's cameras, pre-filled so family phones work on first open.
//
// Addresses come from `secrets.json` (git-ignored) at build time:
//   flutter build apk --dart-define-from-file=secrets.json
// The ONVIF password is never part of the app: each device asks for it once
// and keeps it encrypted on the device (see CameraStore.setPassword).
// Stream links are not stored either: on first launch the app asks each
// camera for them over ONVIF (see CameraStore.discoverMissingStreams).
// Without secrets.json the app starts empty and cameras are added in-app.
const _user = String.fromEnvironment('PEHRA_ONVIF_USER', defaultValue: 'admin');
const _hosts = String.fromEnvironment('PEHRA_CAMERA_HOSTS');

const _names = ['Camera one', 'Camera two', 'Camera three', 'Camera four', 'Camera five'];

List<Camera> defaultCameras() {
  final hosts = _hosts.split(',').map((h) => h.trim()).where((h) => h.isNotEmpty).toList();
  return [
    for (var i = 0; i < hosts.length; i++)
      Camera(
        id: 'cam${hosts[i].split('.').last}',
        name: i < _names.length ? _names[i] : 'Camera ${i + 1}',
        host: hosts[i],
        mainUrl: '',
        subUrl: '',
        onvifUser: _user,
        onvifPassword: '',
      ),
  ];
}
