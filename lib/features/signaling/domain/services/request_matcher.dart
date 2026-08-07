import 'dart:async';

import '../../../../core/logging/log.dart';
import '../entities/signaling_entities.dart';

/// Manages request/response correlation by request ID.
///
/// Single Responsibility: Track pending requests and match responses.
abstract class IRequestMatcher {
  /// Register a pending request and get completer for response.
  Completer<SignalingConnectionResponse> registerRequest(String requestId);

  /// Complete a pending request with response.
  /// Returns true if request was found and completed.
  bool completeRequest(String requestId, SignalingConnectionResponse response);

  /// Fail a pending request with error.
  /// Returns true if request was found and completed.
  bool failRequest(String requestId, Object error);

  /// Get all pending request IDs.
  Set<String> getPendingRequestIds();

  /// Clear all pending requests.
  void clearAllRequests();
}

/// Default implementation using Map<String, Completer>.
class RequestMatcher implements IRequestMatcher {
  static const _pendingWarningThreshold = 50;
  static const _pendingCriticalThreshold = 100;

  final Map<String, Completer<SignalingConnectionResponse>> _pendingRequests =
      {};

  @override
  Completer<SignalingConnectionResponse> registerRequest(String requestId) {
    final existing = _pendingRequests[requestId];
    if (existing != null && !existing.isCompleted) {
      warningLog(
        'Registering duplicate requestId=$requestId; replacing existing pending request.',
      );
      existing.completeError(
        Exception('Replaced by newer request with same id.'),
      );
    }

    final completer = Completer<SignalingConnectionResponse>();
    _pendingRequests[requestId] = completer;

    final pendingCount = _pendingRequests.length;
    if (pendingCount >= _pendingCriticalThreshold) {
      errorLog(
        'Pending signaling requests overflow risk: count=$pendingCount.',
      );
    } else if (pendingCount >= _pendingWarningThreshold) {
      warningLog('Pending signaling requests growing: count=$pendingCount.');
    }

    return completer;
  }

  @override
  bool completeRequest(String requestId, SignalingConnectionResponse response) {
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
      debugLog(
        'Completed pending signaling request requestId=$requestId status=${response.status}.',
      );
      return true;
    }
    // Late/duplicate responses are common after timeout or when the callee also
    // sees the ConnectionResponse envelope — not a datachannel failure.
    debugLog(
      'No pending request found to complete for requestId=$requestId.',
    );
    return false;
  }

  @override
  bool failRequest(String requestId, Object error) {
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
      warningLog(
        'Failed pending signaling request requestId=$requestId.',
        error,
      );
      return true;
    }
    debugLog('No pending request found to fail for requestId=$requestId.');
    return false;
  }

  @override
  Set<String> getPendingRequestIds() => Set.from(_pendingRequests.keys);

  @override
  void clearAllRequests() {
    if (_pendingRequests.isNotEmpty) {
      warningLog(
        'Clearing ${_pendingRequests.length} pending signaling requests due to shutdown/reset.',
      );
    }
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Request cancelled due to shutdown.'),
        );
      }
    }
    _pendingRequests.clear();
  }
}
