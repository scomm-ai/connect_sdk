/// Host-provided access token for signaling and identity gRPC calls.
///
/// Typically backed by AppAuth (`UidsAuthSdk.getValidSession()`).
abstract class SignalingAccessTokenProvider {
  Future<String?> getAccessToken();
}

/// Optional hook invoked when signaling receives an auth failure so the host
/// can refresh AppAuth and push a new token via [ScommConnectorController.setAccessToken].
abstract class SignalingAccessTokenRefresher {
  Future<String?> refreshAccessToken();
}
