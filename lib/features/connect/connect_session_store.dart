import 'connect_session.dart';

class ConnectSessionStore {
  final Map<String, ConnectSession> _sessions = {};

  ConnectSession save(ConnectSession session) {
    _sessions[session.sessionId] = session;
    return session;
  }

  ConnectSession? getBySessionId(String sessionId) {
    return _sessions[sessionId];
  }

  ConnectSession? getByRequestId(String requestId) {
    return _sessions[requestId];
  }

  ConnectSession? getByRemoteUri(String remoteUri) {
    final exact = _findByRemoteUri(remoteUri, soft: false);
    if (exact != null) return exact;
    return _findByRemoteUri(remoteUri, soft: true);
  }

  ConnectSession? _findByRemoteUri(String remoteUri, {required bool soft}) {
    final needle = soft ? _normalizeRemoteUri(remoteUri) : remoteUri.trim();
    if (needle.isEmpty) return null;

    for (final session in _sessions.values) {
      final candidate = soft
          ? _normalizeRemoteUri(session.remoteUri)
          : session.remoteUri.trim();
      if (candidate == needle) return session;
    }
    return null;
  }

  static String _normalizeRemoteUri(String uri) {
    var normalized = uri.trim().toLowerCase();
    if (normalized.startsWith('scomm://')) {
      normalized = 'scomm:${normalized.substring('scomm://'.length)}';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  List<String> get sessionIds => _sessions.keys.toList(growable: false);

  ConnectSession? remove(String sessionId) {
    return _sessions.remove(sessionId);
  }

  Iterable<ConnectSession> get all => _sessions.values;

  Future<void> clear() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.dispose();
    }
  }
}