import 'package:flutter_test/flutter_test.dart';
import 'package:netseye/models/camera.dart';
import 'package:netseye/services/onvif.dart';

import 'support.dart';

/// A pretend home network: which camera hardware answers at which address.
class _FakeOnvif extends OnvifClient {
  _FakeOnvif(super.camera, this.network);
  final Map<String, String> network; // ip -> MAC

  @override
  Future<String?> mac() async => network[camera.host];

  @override
  Future<(String?, String?)> discoverStreams() async {
    final m = network[camera.host];
    if (m == null) throw Exception('nobody there');
    return ('rtsp://${camera.host}:5543/$m/main', 'rtsp://${camera.host}:5543/$m/sub');
  }
}

void main() {
  // The three cameras as the app had them, identities already learned.
  final before = [
    sampleCameras[0].copyWith(host: '192.168.1.33', mac: 'AA:AA:AA:AA:AA:AA'), // Front door
    sampleCameras[1].copyWith(host: '192.168.1.34', mac: 'BB:BB:BB:BB:BB:BB'), // Hall
    sampleCameras[2].copyWith(host: '192.168.1.57', mac: 'CC:CC:CC:CC:CC:CC'), // Rooftop
  ];

  test('router reshuffle: every camera follows its own hardware', () async {
    // After a router restart: A moved to .37, B took A's old .33, C to .35.
    final network = {
      '192.168.1.37': 'AA:AA:AA:AA:AA:AA',
      '192.168.1.33': 'BB:BB:BB:BB:BB:BB',
      '192.168.1.35': 'CC:CC:CC:CC:CC:CC',
    };
    final store = await testStore(cameras: before);
    final moved = await store.verifyLocations(
      force: true,
      client: (c) => _FakeOnvif(c, network),
      findDevices: () async => network.keys.toSet(),
    );
    Camera cam(String id) => store.byId(id)!;
    expect(cam('cam33').host, '192.168.1.37');
    expect(cam('cam34').host, '192.168.1.33', reason: 'Hall now answers at the old Front door address');
    expect(cam('cam57').host, '192.168.1.35');
    // Stream links rediscovered at the new addresses, for the right camera.
    expect(cam('cam33').subUrl, 'rtsp://192.168.1.37:5543/AA:AA:AA:AA:AA:AA/sub');
    expect(cam('cam34').subUrl, contains('BB:BB'));
    expect(moved, hasLength(3));
  });

  test('a camera never plays another camera that took its address', () async {
    // Front door is off; Hall now sits on Front door's old address.
    final network = {'192.168.1.33': 'BB:BB:BB:BB:BB:BB', '192.168.1.57': 'CC:CC:CC:CC:CC:CC'};
    final store = await testStore(cameras: before);
    await store.verifyLocations(
      force: true,
      client: (c) => _FakeOnvif(c, network),
      findDevices: () async => network.keys.toSet(),
    );
    final frontDoor = store.byId('cam33')!;
    expect(frontDoor.hasStreams, isFalse, reason: "must not show Hall's video as Front door");
    expect(store.byId('cam34')!.host, '192.168.1.33');
  });

  test('nothing moves when every address is right', () async {
    final network = {
      '192.168.1.33': 'AA:AA:AA:AA:AA:AA',
      '192.168.1.34': 'BB:BB:BB:BB:BB:BB',
      '192.168.1.57': 'CC:CC:CC:CC:CC:CC',
    };
    var searched = false;
    final store = await testStore(cameras: before);
    final moved = await store.verifyLocations(
      force: true,
      client: (c) => _FakeOnvif(c, network),
      findDevices: () async {
        searched = true;
        return network.keys.toSet();
      },
    );
    expect(moved, isEmpty);
    expect(searched, isFalse, reason: 'no network search when nothing moved');
    expect(store.byId('cam33')!.mainUrl, before[0].mainUrl);
  });

  test('first run learns each camera\'s hardware address', () async {
    final network = {
      '192.168.1.33': 'AA:AA:AA:AA:AA:AA',
      '192.168.1.34': 'BB:BB:BB:BB:BB:BB',
      '192.168.1.57': 'CC:CC:CC:CC:CC:CC',
    };
    final store = await testStore(); // sample cameras, no MACs yet
    await store.verifyLocations(
      force: true,
      client: (c) => _FakeOnvif(c, network),
      findDevices: () async => {},
    );
    expect(store.cameras.map((c) => c.mac), ['AA:AA:AA:AA:AA:AA', 'BB:BB:BB:BB:BB:BB', 'CC:CC:CC:CC:CC:CC']);
  });

  test('stream links always use the address the camera answered on', () {
    // Real firmware bug: Rooftop moved to .37 but still reports .33 (Hall).
    expect(
      OnvifClient.atHost('rtsp://192.168.1.33:5543/live/channel1', '192.168.1.37'),
      'rtsp://192.168.1.37:5543/live/channel1',
    );
    expect(
      OnvifClient.atHost('rtsp://192.168.1.35:5543/abc/live/channel0', '192.168.1.35'),
      'rtsp://192.168.1.35:5543/abc/live/channel0',
    );
  });

  test('MAC addresses are compared in one format', () {
    expect(OnvifClient.normaliseMac('5c-35-48-d2-9b-34'), '5C:35:48:D2:9B:34');
    expect(OnvifClient.normaliseMac('5C:35:48:D2:9B:34'), '5C:35:48:D2:9B:34');
  });
}
