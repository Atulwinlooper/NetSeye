import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/camera.dart';

/// Minimal ONVIF client: just enough to find out whether a camera can
/// pan/tilt and to move it. Everything stays on the local network.
class OnvifClient {
  OnvifClient(this.camera);

  final Camera camera;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  String? _ptzUrl;
  String? _mediaUrl;
  String? _profileToken;
  bool? _hasPtz;

  String get _base => 'http://${camera.host}:${camera.onvifPort}';

  static final Map<String, OnvifClient> _cache = {};

  /// One shared client per camera so capabilities are only looked up once.
  static OnvifClient of(Camera c) {
    final existing = _cache[c.id];
    if (existing != null &&
        existing.camera.host == c.host &&
        existing.camera.onvifPassword == c.onvifPassword) {
      return existing;
    }
    return _cache[c.id] = OnvifClient(c);
  }

  Future<bool> hasPtz() async {
    if (_hasPtz != null) return _hasPtz!;
    if (!camera.hasOnvif) return _hasPtz = false;
    try {
      final services = await _soap(
        '$_base/onvif/device_service',
        '<GetServices xmlns="http://www.onvif.org/ver10/device/wsdl">'
            '<IncludeCapability>false</IncludeCapability></GetServices>',
      );
      final re = RegExp(r'<[^>]*Namespace>([^<]+)</[^>]*Namespace>\s*<[^>]*XAddr>([^<]+)<');
      for (final m in re.allMatches(services)) {
        final ns = m.group(1)!;
        if (ns.contains('/ptz/')) _ptzUrl = _unxml(m.group(2)!.trim());
        if (ns.contains('ver10/media/')) _mediaUrl = _unxml(m.group(2)!.trim());
      }
      _mediaUrl ??= '$_base/onvif/media_service';
      if (_ptzUrl == null) return _hasPtz = false;
      final profiles = await _soap(
        _mediaUrl!,
        '<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>',
      );
      _profileToken = RegExp(r'Profiles[^>]*token="([^"]+)"').firstMatch(profiles)?.group(1);
      return _hasPtz = _profileToken != null;
    } catch (_) {
      return false; // not cached: try again next time
    }
  }

  /// Start moving. x and y are -1..1 (right / up are positive).
  Future<void> move(double x, double y) async {
    if (!await hasPtz()) return;
    await _soap(
      _ptzUrl!,
      '<ContinuousMove xmlns="http://www.onvif.org/ver20/ptz/wsdl">'
      '<ProfileToken>${_xml(_profileToken!)}</ProfileToken>'
      '<Velocity><PanTilt xmlns="http://www.onvif.org/ver10/schema" '
      'x="${x.toStringAsFixed(2)}" y="${y.toStringAsFixed(2)}"/></Velocity>'
      '</ContinuousMove>',
    ).catchError((_) => '');
  }

  Future<void> stop() async {
    if (_ptzUrl == null || _profileToken == null) return;
    await _soap(
      _ptzUrl!,
      '<Stop xmlns="http://www.onvif.org/ver20/ptz/wsdl">'
      '<ProfileToken>${_xml(_profileToken!)}</ProfileToken>'
      '<PanTilt>true</PanTilt><Zoom>true</Zoom></Stop>',
    ).catchError((_) => '');
  }

  /// Ask the camera for its own stream addresses. Returns (hd, light),
  /// either of which may be null if the camera only offers one.
  Future<(String?, String?)> discoverStreams() async {
    final media = '$_base/onvif/media_service';
    final profiles = await _soap(media, '<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>');
    final tokens = RegExp(r'Profiles[^>]*token="([^"]+)"')
        .allMatches(profiles)
        .map((m) => m.group(1)!)
        .toList();
    final uris = <String>[];
    for (final t in tokens.take(2)) {
      final r = await _soap(
        media,
        '<GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">'
        '<StreamSetup><Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>'
        '<Transport xmlns="http://www.onvif.org/ver10/schema"><Protocol>RTSP</Protocol></Transport>'
        '</StreamSetup><ProfileToken>${_xml(t)}</ProfileToken></GetStreamUri>',
      );
      final uri = RegExp(r'Uri>([^<]+)<').firstMatch(r)?.group(1);
      if (uri != null) uris.add(atHost(_unxml(uri.trim()), camera.host));
    }
    return (uris.isNotEmpty ? uris[0] : null, uris.length > 1 ? uris[1] : null);
  }

  /// Point a stream link at [host], the address the camera actually
  /// answered on. Some firmware keeps reporting the address it had when it
  /// booted, so after the router hands out new addresses its links point at
  /// a different camera (or nothing). Port and path are kept.
  static String atHost(String url, String host) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty || u.host == host) return url;
    return u.replace(host: host).toString();
  }

  /// Free the HTTP client (for short-lived clients; the shared ones from
  /// [of] live as long as the app).
  void close() => _http.close(force: true);

  /// The camera's hardware (MAC) address, normalised to upper-case
  /// "AA:BB:CC:DD:EE:FF". Null if it can't be reached or won't say.
  Future<String?> mac() async {
    try {
      final r = await _soap(
        '$_base/onvif/device_service',
        '<GetNetworkInterfaces xmlns="http://www.onvif.org/ver10/device/wsdl"/>',
      );
      final m = RegExp(r'HwAddress>([^<]+)<').firstMatch(r)?.group(1);
      return m == null ? null : normaliseMac(m);
    } on Exception {
      return null;
    }
  }

  static String normaliseMac(String v) {
    final hex = v.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12) return v.trim().toUpperCase();
    return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  }

  /// Find ONVIF devices on the local network: a WS-Discovery multicast
  /// probe (the standard way cameras announce themselves), plus a quick
  /// scan of this network for the ONVIF port in case multicast is blocked.
  /// Returns IPv4 addresses.
  static Future<Set<String>> findDevices({int port = 8000, bool scan = true}) async {
    final found = <String>{...await _wsDiscovery()};
    if (scan) found.addAll(await _scan(port));
    return found;
  }

  static Future<Set<String>> _wsDiscovery() async {
    final found = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final id = List.generate(16, (_) => Random().nextInt(16).toRadixString(16)).join();
      final probe = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
        'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
        'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
        'xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
        '<e:Header><w:MessageID>uuid:$id</w:MessageID>'
        '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
        '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
        '</e:Header><e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>'
        '</e:Envelope>',
      );
      final group = InternetAddress('239.255.255.250');
      socket.send(probe, group, 3702);
      final done = Completer<void>();
      final sub = socket.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = socket!.receive();
        if (d == null) return;
        final text = utf8.decode(d.data, allowMalformed: true);
        for (final m in RegExp(r'https?://([0-9.]+)[:/]').allMatches(text)) {
          found.add(m.group(1)!);
        }
        found.add(d.address.address);
      });
      // Send twice: UDP on Wi-Fi drops packets.
      Timer(const Duration(milliseconds: 400), () => socket?.send(probe, group, 3702));
      Timer(const Duration(milliseconds: 2500), () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      await sub.cancel();
    } on Exception {
      // Multicast not allowed here; the scan still runs.
    } finally {
      socket?.close();
    }
    return found;
  }

  static Future<Set<String>> _scan(int port) async {
    final found = <String>{};
    final prefixes = <String>{};
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          final ip = a.address;
          final private =
              ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
          if (!a.isLoopback && private) prefixes.add(ip.substring(0, ip.lastIndexOf('.') + 1));
        }
      }
    } on Exception {
      return found;
    }
    for (final p in prefixes) {
      // A few batches, so slow devices (TVs) don't open 254 sockets at once.
      for (var start = 1; start < 255; start += 64) {
        await Future.wait([
          for (var i = start; i < start + 64 && i < 255; i++)
            Socket.connect('$p$i', port, timeout: const Duration(milliseconds: 700))
                .then((s) {
                  found.add('$p$i');
                  s.destroy();
                })
                .catchError((Object _) {}),
        ]);
      }
    }
    return found;
  }

  Future<String> _soap(String url, String body) async {
    final req = await _http.postUrl(Uri.parse(url));
    req.persistentConnection = false; // camera servers drop keep-alive
    final bytes = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
      '${_security()}<s:Body>$body</s:Body></s:Envelope>',
    );
    // Small camera web servers can't read chunked bodies: send it whole.
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/soap+xml');
    req.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close().timeout(const Duration(seconds: 5));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException('ONVIF ${res.statusCode}');
    }
    return text;
  }

  /// Escape text placed inside XML so values like a password or token
  /// containing & < > " ' can't break or alter the request.
  static String _xml(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Undo XML escaping in values the camera sends back (e.g. & in URLs).
  static String _unxml(String v) => v
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// WS-Security UsernameToken with password digest.
  String _security() {
    final rnd = Random.secure();
    final nonce = List<int>.generate(16, (_) => rnd.nextInt(256));
    final created = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final digest = base64.encode(
      sha1.convert([...nonce, ...utf8.encode(created), ...utf8.encode(camera.onvifPassword)]).bytes,
    );
    return '<s:Header><Security '
        'xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">'
        '<UsernameToken><Username>${_xml(camera.onvifUser)}</Username>'
        '<Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</Password>'
        '<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-soap-message-security-1.0#Base64Binary">${base64.encode(nonce)}</Nonce>'
        '<Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">$created</Created>'
        '</UsernameToken></Security></s:Header>';
  }
}
