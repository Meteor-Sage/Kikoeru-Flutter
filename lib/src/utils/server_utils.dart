class ServerUtils {
  static const String officialHostKeyword = 'api.asmr';
  static const String defaultRemoteHost = 'https://api.asmr-200.com';
  static const String defaultLocalHost = 'localhost:8888';

  static const List<String> preferredHosts = [
    'api.asmr-200.com',
    'api.asmr.one',
    'api.asmr-100.com',
    'api.asmr-300.com',
  ];

  /// Checks if the provided host string corresponds to the official server.
  static bool isOfficialServer(String? host) {
    if (host == null || host.isEmpty) return false;
    return host.contains(officialHostKeyword);
  }
}
