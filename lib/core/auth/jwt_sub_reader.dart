import 'dart:convert';

/// Reads JWT `sub` from an access token without verifying the signature.
/// Verification is performed by the signaling server.
String? readJwtSub(String token) {
  final parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }

  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(decoded);
    if (payload is Map) {
      final sub = payload['sub'];
      if (sub is String && sub.trim().isNotEmpty) {
        return sub.trim();
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

String normalizeSignalingUserId(String userId) {
  final trimmed = userId.trim();
  if (trimmed.contains('@')) {
    return trimmed.toLowerCase();
  }
  return trimmed;
}

/// Returns true when [value] looks like an email address (contains `@`).
///
/// Device identity persistence must use emails, not opaque JWT `sub` ids.
bool looksLikeEmail(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final at = trimmed.indexOf('@');
  return at > 0 && at < trimmed.length - 1;
}
