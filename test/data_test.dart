import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/data/camera_store.dart';
import 'package:netseye/data/validate.dart';
import 'package:netseye/models/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  group('Validate', () {
    test('accepts LAN addresses and host names', () {
      expect(Validate.host('192.168.1.33'), isNull);
      expect(Validate.host('camera-hall.local'), isNull);
      expect(Validate.host('', optional: true), isNull);
    });

    test('rejects malformed addresses', () {
      expect(Validate.host(''), isNotNull);
      expect(Validate.host('192.168.1.300'), isNotNull);
      expect(Validate.host('http://192.168.1.33'), isNotNull);
      expect(Validate.host('a b'), isNotNull);
    });

    test('stream links must be rtsp', () {
      expect(Validate.stream('rtsp://192.168.1.33:5543/live/channel0'), isNull);
      expect(Validate.stream('http://192.168.1.33/live'), isNotNull);
      expect(Validate.stream(''), isNotNull);
      expect(Validate.stream('', optional: true), isNull);
    });
  });

  group('Camera', () {
    test('survives a JSON round trip', () {
      final back = Camera.decodeList(Camera.encodeList(sampleCameras));
      expect(back.map((c) => c.toJson()), sampleCameras.map((c) => c.toJson()));
    });

    test('knows whether its streams are known yet', () {
      expect(sampleCameras.first.hasStreams, isTrue);
      expect(sampleCameras.first.copyWith(mainUrl: '').hasStreams, isFalse);
    });
  });

  group('CameraStore', () {
    test('keeps cameras in the vault, not in plain preferences', () async {
      final vault = MemoryVault();
      final store = await testStore(vault: vault);
      await store.upsert(store.cameras.first.copyWith(name: 'Gate'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cameras.v1'), isNull);
      expect(await vault.read('cameras.v1'), contains('Gate'));
    });

    test('moves a list saved by the first version into the vault', () async {
      SharedPreferences.setMockInitialValues({'cameras.v1': Camera.encodeList(sampleCameras)});
      final vault = MemoryVault();
      final store = await CameraStore.load(vault: vault);
      expect(store.cameras, hasLength(3));
      expect(await vault.read('cameras.v1'), isNotNull);
      expect((await SharedPreferences.getInstance()).getString('cameras.v1'), isNull);
    });

    test('reorders to the final index', () async {
      final store = await testStore();
      await store.reorder(0, 2);
      expect(store.cameras.map((c) => c.id), ['cam34', 'cam57', 'cam33']);
      await store.reorder(2, 0);
      expect(store.cameras.map((c) => c.id), ['cam33', 'cam34', 'cam57']);
    });

    test('tries the hub first, then the camera itself', () async {
      final store = await testStore();
      final cam = store.cameras.first;
      expect(store.urlsFor(cam, hd: true), [cam.mainUrl]);
      await store.setHub('192.168.1.41');
      expect(store.urlsFor(cam, hd: false), ['rtsp://192.168.1.41:8554/cam33-sub', cam.subUrl]);
    });

    test('removes a camera', () async {
      final store = await testStore();
      await store.remove('cam34');
      expect(store.byId('cam34'), isNull);
      expect(store.cameras, hasLength(2));
    });
  });
}
