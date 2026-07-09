import 'dart:async';

import 'package:scommconnector/features/signaling/domain/usecases/send_signal_envelope_usecase.dart';
import 'package:scommconnector/features/signaling/domain/usecases/watch_signaling_messages_uscase.dart';

import '../../../../core/errors/errors.dart';
import '../../../../core/logging/log.dart';
import '../../../../core/resilience/online_aware_resilience.dart';
import '../../domain/entities/signaling_entities.dart';
import '../../domain/services/connection_health_monitor.dart';
import '../../domain/services/request_matcher.dart';
import '../../domain/services/signaling_error_classifier.dart';
import '../../domain/usecases/connect_signaling_usecase.dart';
import '../../domain/usecases/disconnect_signaling_usecase.dart';
import '../../domain/usecases/watch_connection_status_usecase.dart';
import '../../domain/usecases/watch_presence_usecase.dart';
import '../state/signaling_state.dart';

class SignalingController {
  final ConnectSignalingUseCase connectSignalingUseCase;
  final DisconnectSignalingUseCase disconnectSignalingUseCase;
  final WatchSignalingMessagesUseCase watchSignalingMessagesUseCase;
  final WatchConnectionStatusUseCase watchConnectionStatusUseCase;
  final SendSignalEnvelopeUseCase sendSignalEnvelopeUseCase;
  final WatchPresenceUseCase watchPresenceUseCase;
  final IConnectionHealthMonitor healthMonitor;
  final ISignalingErrorClassifier errorClassifier;
  final IOnlineAwareResilience onlineAwareness;
  final IRequestMatcher requestMatcher;

  SignalingController({
    required this.connectSignalingUseCase,
    required this.disconnectSignalingUseCase,
    required this.watchSignalingMessagesUseCase,
    required this.watchConnectionStatusUseCase,
    required this.sendSignalEnvelopeUseCase,
    required this.watchPresenceUseCase,
    required this.healthMonitor,
    required this.errorClassifier,
    required this.onlineAwareness,
    required this.requestMatcher,
  });

  SignalingState _state = const SignalingState();
  String? _deviceId;
  bool _manualStop = false;
  List<String> _watchedPresenceTargets = const [];

  // Stream subscriptions
  StreamSubscription<SignalingEnvelope>? _messagesSub;

  // Signaling server connection status stream
  StreamSubscription<SignalingConnectionStatus>? _statusSub;

  // Presence updates stream [NOTE: Proper used YET]
  StreamSubscription<SignalingPresenceEvent>? _presenceSub;

  // controllers Streams to emit state, incoming messages and presence events
  final StreamController<SignalingState> _stateController =
      StreamController<SignalingState>.broadcast();

  final StreamController<SignalingEnvelope> _incomingController =
      StreamController<SignalingEnvelope>.broadcast();

  final StreamController<SignalingPresenceEvent> _presenceController =
      StreamController<SignalingPresenceEvent>.broadcast();

  // Public streams to listen to state changes, incoming messages and presence events
  Stream<SignalingState> get signalingStates => _stateController.stream;
  Stream<SignalingEnvelope> get incomingMessages => _incomingController.stream;
  Stream<SignalingPresenceEvent> get presenceEvents =>
      _presenceController.stream;
  SignalingState get state => _state;

  // Starts the signaling controller by connecting to the signaling server and setting up necessary streams.
  Future<void> start({required String deviceId}) async {
    _deviceId = deviceId;
    _manualStop = false;

    await _bindStreams();

    await connectSignalingUseCase(deviceId: deviceId);

    await onlineAwareness.startMonitoring(
      shouldAutoRecover: () => !_manualStop,
      onRecoveryNeeded: () async {
        final id = _deviceId;
        if (id == null || id.isEmpty) return;
        try {
          await connectSignalingUseCase(deviceId: id);
        } catch (_) {}
      },
    );
  }

  // Stops the signaling controller by disconnecting from the signaling server, stopping all streams, and clearing any pending requests.
  Future<void> stop() async {
    infoLog('Stopping signaling controller...');
    _manualStop = true;
    _watchedPresenceTargets = const [];

    await onlineAwareness.stopMonitoring();
    await _presenceSub?.cancel();
    _presenceSub = null;

    await healthMonitor.stopHeartbeat();
    await disconnectSignalingUseCase();

    requestMatcher.clearAllRequests();

    _emitState(
      _state.copyWith(
        status: SignalingStatus.disconnected,
        message: 'Disconnected.',
        clearError: true,
      ),
    );
  }

  // Disposes the signaling controller by stopping it and closing all stream controllers.
  Future<void> dispose() async {
    _manualStop = true;

    await onlineAwareness.stopMonitoring();
    await _presenceSub?.cancel();
    await _messagesSub?.cancel();
    await _statusSub?.cancel();
    await healthMonitor.stopHeartbeat();
    await disconnectSignalingUseCase();

    requestMatcher.clearAllRequests();

    await _stateController.close();
    await _incomingController.close();
    await _presenceController.close();
  }

  // Sends a signaling envelope to the signaling server. If an error occurs, it updates the state with the error message and rethrows the error.
  Future<void> sendEnvelope(SignalingEnvelope envelope) async {
    try {
      await sendSignalEnvelopeUseCase(envelope);
    } catch (error) {
      final appError = errorClassifier.toAppError(error);
      _emitState(
        _state.copyWith(
          status: SignalingStatus.failure,
          error: appError.message,
          clearMessage: true,
        ),
      );
      rethrow;
    }
  }

  // Send a connection request to another devices and waits for while;
  Future<void> sendConnectionRequest({
    required String requestId,
    required String fromUri,
    required String toUri,
    required String serviceName,
    String note = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final completer = requestMatcher.registerRequest(requestId);

    await sendEnvelope(
      SignalingEnvelope(
        messageId: _buildMessageId(),
        from: SignalingDeviceRef(uri: fromUri),
        to: SignalingDeviceRef(uri: toUri),
        connectionRequest: SignalingConnectionRequest(
          requestId: requestId,
          serviceName: serviceName,
          note: note,
        ),
      ),
    );

    try {
      final response = await completer.future.timeout(timeout);
      _ensureConnectionAccepted(response);
    } on TimeoutException {
      try {
        await sendEnvelope(
          SignalingEnvelope(
            messageId: _buildMessageId(),
            from: SignalingDeviceRef(uri: fromUri),
            to: SignalingDeviceRef(uri: toUri),
            connectionResponse: SignalingConnectionResponse(
              requestId: requestId,
              status: SignalingConnectionResponseStatus.rejected,
              reason: 'Request timed out.',
            ),
          ),
        );
      } catch (error) {
        warningLog(
          'Failed to notify target about connection request timeout: $error',
        );
      }
      throw const ServerException(
        message: 'Connection timed out. Target may be offline or unreachable.',
      );
    } finally {
      requestMatcher.failRequest(requestId, 'Request finished.');
    }
  }

  // Watches the presence of devices eg online/offline status
  Future<void> watchPresence({required List<String> targetUris}) async {
    final targets = targetUris
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    _watchedPresenceTargets = targets;

    await _presenceSub?.cancel();
    _presenceSub = null;

    if (targets.isEmpty || _state.status != SignalingStatus.connected) {
      return;
    }

    _presenceSub = watchPresenceUseCase(targetUris: targets).listen(
      (event) {
        if (!_presenceController.isClosed) {
          _presenceController.add(event);
        }
      },
      onError: (error, stackTrace) {
        if (!_presenceController.isClosed) {
          _presenceController.addError(
            errorClassifier.toAppError(error),
            stackTrace,
          );
        }
      },
      onDone: () {
        warningLog('Presence stream ended.');
      },
      cancelOnError: false,
    );
  }

  // Binds the necessary streams to listen for incoming signaling messages and connection status changes, and handles them accordingly.
  Future<void> _bindStreams() async {
    _messagesSub ??= watchSignalingMessagesUseCase().listen(
      (envelope) {
        if (!_incomingController.isClosed) {
          _incomingController.add(envelope);
        }
        _handleEnvelope(envelope);
      },
      onError: (error, stackTrace) {
        final appError = errorClassifier.toAppError(error);
        if (!_incomingController.isClosed) {
          _incomingController.addError(appError, stackTrace);
        }

        if (!_manualStop) {
          _emitState(
            _state.copyWith(
              status: SignalingStatus.failure,
              error: appError.message,
              clearMessage: true,
            ),
          );
        }
      },
      cancelOnError: false,
    );

    _statusSub ??= watchConnectionStatusUseCase().listen(
      (status) async {
        infoLog('Connection status changed: $status');
        switch (status) {
          case SignalingConnectionStatus.disconnected:
            await healthMonitor.stopHeartbeat();
            _emitState(
              _state.copyWith(
                status: SignalingStatus.disconnected,
                message: 'Disconnected.',
                clearError: true,
              ),
            );
            break;

          case SignalingConnectionStatus.connecting:
            _emitState(
              _state.copyWith(
                status: SignalingStatus.connecting,
                message: 'Connecting...',
                clearError: true,
              ),
            );
            break;

          case SignalingConnectionStatus.connected:
            // Start heartbeat to monitor connection health[Ping-Pong mechanism]
            // 15 minutes interval for ping to server
            healthMonitor.startHeartbeat(
              interval: const Duration(minutes: 15),
              onSendHeartbeat: sendEnvelope,
            );

            await _restorePresenceWatch();

            _emitState(
              _state.copyWith(
                status: SignalingStatus.connected,
                message: 'Connected.',
                clearError: true,
              ),
            );
            break;

          case SignalingConnectionStatus.reconnecting:
            await healthMonitor.stopHeartbeat();
            _emitState(
              _state.copyWith(
                status: SignalingStatus.reconnecting,
                message: 'Reconnecting...',
                clearError: true,
              ),
            );
            break;

          case SignalingConnectionStatus.stopped:
            await healthMonitor.stopHeartbeat();
            _emitState(
              _state.copyWith(
                status: SignalingStatus.disconnected,
                message: 'Disconnected.',
                clearError: true,
              ),
            );
            break;

          case SignalingConnectionStatus.authRequired:
            await healthMonitor.stopHeartbeat();
            _emitState(
              _state.copyWith(
                status: SignalingStatus.failure,
                error: 'Authentication required.',
                clearMessage: true,
              ),
            );
            break;

          case SignalingConnectionStatus.failed:
            await healthMonitor.stopHeartbeat();
            _emitState(
              _state.copyWith(
                status: SignalingStatus.failure,
                error: 'Signaling connection failed.',
                clearMessage: true,
              ),
            );
            break;
        }
      },
      onError: (error, stackTrace) {
        final appError = errorClassifier.toAppError(error);
        _emitState(
          _state.copyWith(
            status: SignalingStatus.failure,
            error: appError.message,
            clearMessage: true,
          ),
        );
      },
      cancelOnError: false,
    );
  }

  // Internal method to restore presence watch after reconnection.
  Future<void> _restorePresenceWatch() async {
    if (_watchedPresenceTargets.isEmpty || _manualStop) return;
    await watchPresence(targetUris: _watchedPresenceTargets);
  }

  void _handleEnvelope(SignalingEnvelope envelope) {
    if (envelope.connectionResponse != null) {
      final response = envelope.connectionResponse!;
      requestMatcher.completeRequest(response.requestId, response);
      return;
    }

    if (envelope.pingTimestampMs != null) {
      unawaited(_respondToPing(envelope));
    }
  }

  Future<void> _respondToPing(SignalingEnvelope pingEnvelope) async {
    try {
      await sendEnvelope(
        SignalingEnvelope(
          messageId: _buildMessageId(),
          from: pingEnvelope.to,
          to: pingEnvelope.from,
          pongTimestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {}
  }

  void _ensureConnectionAccepted(SignalingConnectionResponse response) {
    if (response.status == SignalingConnectionResponseStatus.accepted) return;

    final reason = response.reason.isNotEmpty ? response.reason : null;

    switch (response.status) {
      case SignalingConnectionResponseStatus.rejected:
        throw ServerException(
          message: reason ?? 'Connection request was rejected.',
        );
      case SignalingConnectionResponseStatus.busy:
        throw ServerException(message: reason ?? 'Target device is busy.');
      case SignalingConnectionResponseStatus.blocked:
        throw UnauthorizedException(
          message: reason ?? 'Connection blocked by target device.',
        );
      case SignalingConnectionResponseStatus.disconnected:
        throw ServerException(
          message: reason ?? 'Remote peer closed the connection.',
        );
      case SignalingConnectionResponseStatus.unspecified:
        throw ServerException(message: reason ?? 'Connection request failed.');
      case SignalingConnectionResponseStatus.accepted:
        return;
    }
  }

  String _buildMessageId() => 'sig-${DateTime.now().microsecondsSinceEpoch}';

  void _emitState(SignalingState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}
