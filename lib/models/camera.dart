import 'dart:convert';

/// One camera on the home network.
class Camera {
  const Camera({
    required this.id,
    required this.name,
    this.room = '',
    required this.host,
    required this.mainUrl,
    required this.subUrl,
    this.onvifPort = 8000,
    this.onvifUser = 'admin',
    this.onvifPassword = '',
  });

  final String id;
  final String name;
  final String room;
  final String host;

  /// Full-quality stream (HEVC on CP Plus cameras).
  final String mainUrl;

  /// Light stream for grids and slow Wi-Fi (H.264, 640x360).
  final String subUrl;

  final int onvifPort;
  final String onvifUser;
  final String onvifPassword;

  bool get hasOnvif => onvifPassword.isNotEmpty;
  bool get hasStreams => mainUrl.isNotEmpty;

  Camera copyWith({
    String? name,
    String? room,
    String? host,
    String? mainUrl,
    String? subUrl,
    int? onvifPort,
    String? onvifUser,
    String? onvifPassword,
  }) => Camera(
    id: id,
    name: name ?? this.name,
    room: room ?? this.room,
    host: host ?? this.host,
    mainUrl: mainUrl ?? this.mainUrl,
    subUrl: subUrl ?? this.subUrl,
    onvifPort: onvifPort ?? this.onvifPort,
    onvifUser: onvifUser ?? this.onvifUser,
    onvifPassword: onvifPassword ?? this.onvifPassword,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'room': room,
    'host': host,
    'mainUrl': mainUrl,
    'subUrl': subUrl,
    'onvifPort': onvifPort,
    'onvifUser': onvifUser,
    'onvifPassword': onvifPassword,
  };

  factory Camera.fromJson(Map<String, dynamic> j) => Camera(
    id: j['id'] as String,
    name: j['name'] as String,
    room: (j['room'] as String?) ?? '',
    host: j['host'] as String,
    mainUrl: j['mainUrl'] as String,
    subUrl: j['subUrl'] as String,
    onvifPort: (j['onvifPort'] as int?) ?? 8000,
    onvifUser: (j['onvifUser'] as String?) ?? 'admin',
    onvifPassword: (j['onvifPassword'] as String?) ?? '',
  );

  static String encodeList(List<Camera> cams) => jsonEncode(cams.map((c) => c.toJson()).toList());

  static List<Camera> decodeList(String s) =>
      (jsonDecode(s) as List).map((e) => Camera.fromJson(e as Map<String, dynamic>)).toList();
}
