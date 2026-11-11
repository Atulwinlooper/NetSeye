import 'package:netseye/data/camera_store.dart';
import 'package:netseye/models/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sampleCameras = [
  Camera(
    id: 'cam33',
    name: 'Front door',
    room: 'Entrance',
    host: '192.168.1.33',
    mainUrl: 'rtsp://192.168.1.33:5543/live/channel0',
    subUrl: 'rtsp://192.168.1.33:5543/live/channel1',
    onvifPassword: 'secret',
  ),
  Camera(
    id: 'cam34',
    name: 'Hall',
    host: '192.168.1.34',
    mainUrl: 'rtsp://192.168.1.34:5543/x/live/channel0',
    subUrl: 'rtsp://192.168.1.34:5543/x/live/channel1',
    onvifPassword: 'secret',
  ),
  Camera(
    id: 'cam57',
    name: 'Rooftop',
    room: 'Terrace',
    host: '192.168.1.57',
    mainUrl: 'rtsp://192.168.1.57:5543/x/live/channel0',
    subUrl: 'rtsp://192.168.1.57:5543/x/live/channel1',
    onvifPassword: 'secret',
  ),
];

/// A store backed by memory, pre-filled with [cameras].
Future<CameraStore> testStore({List<Camera> cameras = sampleCameras, MemoryVault? vault}) async {
  SharedPreferences.setMockInitialValues({});
  final v = vault ?? MemoryVault();
  await v.write('cameras.v1', Camera.encodeList(cameras));
  return CameraStore.load(vault: v);
}
