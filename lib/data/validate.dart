/// Input checks for addresses typed into the app. Each returns a short,
/// plain-language problem, or null when the value is fine.
abstract final class Validate {
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');
  static final _hostname = RegExp(
    r'^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
  );

  /// All-digit names must be a real IPv4 address (so 192.168.1.300 fails).
  static bool isHost(String v) =>
      _ipv4.hasMatch(v) || (_hostname.hasMatch(v) && !RegExp(r'^[\d.]+$').hasMatch(v));

  /// A camera or hub address: an IPv4 address or a local host name.
  static String? host(String v, {bool optional = false}) {
    final s = v.trim();
    if (s.isEmpty) return optional ? null : 'Enter the address, like 192.168.1.33';
    if (!isHost(s)) return "That doesn't look like an address. Try something like 192.168.1.33";
    return null;
  }

  /// An RTSP stream link.
  static String? stream(String v, {bool optional = false}) {
    final s = v.trim();
    if (s.isEmpty) return optional ? null : 'Add the stream link, or tap Find streams';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme != 'rtsp' || uri.host.isEmpty) {
      return 'Stream links start with rtsp://';
    }
    return null;
  }
}
