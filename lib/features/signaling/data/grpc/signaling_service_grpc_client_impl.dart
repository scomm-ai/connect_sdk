import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:grpc/grpc.dart';

import '../../../../core/auth/signaling_access_token_provider.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/errors/errors.dart';
import '../../../../core/logging/log.dart';
import '../../domain/entities/signaling_entities.dart';
import 'generated/signaling/signaling.pb.dart' as signaling_pb;
import 'generated/signaling/signaling.pbgrpc.dart' as signaling_grpc;
import 'signaling_service_grpc_client.dart';

class SignalingServiceGrpcClientImpl implements SignalingServiceGrpcClient {
  final ClientChannel _channel;
  late final signaling_grpc.SignalingServiceClient _client;
  final ResolveSignalingAccessToken _accessTokenProvider;

  final StreamController<SignalingEnvelope> _messagesController =
      StreamController<SignalingEnvelope>.broadcast();

  final StreamController<SignalingConnectionStatus> _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();

  StreamSubscription<signaling_pb.SignalEnvelope>? _incomingSubscription;
  StreamController<signaling_pb.SignalEnvelope>? _outgoingController;

  String? _currentDeviceId;

  bool _isDisposed = false;
  bool _isStopping = false;
  bool _isConnected = false;
  bool _isReconnecting = false;

  Future<void>? _connectFuture;

  SignalingServiceGrpcClientImpl(this._channel, this._accessTokenProvider) {
    _client = signaling_grpc.SignalingServiceClient(_channel);
  }

  @override
  Stream<SignalingEnvelope> get messages => _messagesController.stream;

  @override
  Stream<SignalingConnectionStatus> get connectionStatus =>
      _statusController.stream;

  @override
  Future<void> connect({required String deviceId}) async {
    if (_isDisposed) {
      throw StateError('Signaling client already disposed.');
    }

    _currentDeviceId = deviceId;
    _isStopping = false;

    if (_isConnected) {
      debugLog('Signaling connect skipped: already connected.');
      return;
    }

    if (_connectFuture != null) {
      debugLog('Signaling connect skipped: connection already in progress.');
      return _connectFuture!;
    }

    infoLog('Opening signaling gRPC stream for deviceId=$deviceId.');
    _emitStatus(SignalingConnectionStatus.connecting);

    _connectFuture = _openConnection();
    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> _openConnection() async {
    final deviceId = _currentDeviceId;

    if (deviceId == null || _isDisposed || _isStopping) return;

    try {
      final options = await _authorizedOptions();

      await _incomingSubscription?.cancel();
      _incomingSubscription = null;

      final previousOutgoing = _outgoingController;
      _outgoingController = null;
      unawaited(previousOutgoing?.close());

      final outgoingController =
          StreamController<signaling_pb.SignalEnvelope>();
      _outgoingController = outgoingController;

      final responseStream = _client.connect(
        outgoingController.stream,
        options: options,
      );

      _incomingSubscription = responseStream.listen(
        (event) {
          infoLog('Received signaling message: ${event.messageId}');
          if (_isDisposed || _isStopping) return;

          if (!_isConnected) {
            _isConnected = true;
            _isReconnecting = false;
            _emitStatus(SignalingConnectionStatus.connected);
          }

          final envelope = _fromProtoEnvelope(event);

          _messagesController.add(envelope);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isDisposed || _isStopping) return;

          _isConnected = false;
          errorLog('Signaling gRPC stream error.', error, stackTrace);

          if (error is GrpcError &&
              (error.code == StatusCode.unauthenticated ||
                  error.code == StatusCode.permissionDenied)) {
            unawaited(_tryRefreshTokenAfterAuthFailure());
          }

          if (!_messagesController.isClosed) {
            _messagesController.addError(_toAppError(error), stackTrace);
          }

          _scheduleReconnect();
        },
        onDone: () {
          if (_isDisposed || _isStopping) return;

          _isConnected = false;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      outgoingController.add(
        signaling_pb.SignalEnvelope(
          messageId: _buildMessageId(),
          hello: signaling_pb.HelloPayload(deviceId: deviceId),
        ),
      );
    } catch (error, stackTrace) {
      if (_isDisposed || _isStopping) return;
      _isConnected = false;
      errorLog('Failed to open signaling gRPC stream.', error, stackTrace);
      if (!_messagesController.isClosed) {
        _messagesController.addError(_toAppError(error), stackTrace);
      }

      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || _isStopping || _isReconnecting) return;

    _isReconnecting = true;
    _emitStatus(SignalingConnectionStatus.reconnecting);

    () async {
      const delays = <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 15),
      ];

      for (final delay in delays) {
        infoLog(
          'Waiting ${delay.inSeconds} seconds before next signaling reconnect attempt.',
        );
        if (_isDisposed || _isStopping) {
          _isReconnecting = false;
          return;
        }

        await Future.delayed(delay);

        if (_isDisposed || _isStopping) {
          _isReconnecting = false;
          return;
        }

        try {
          infoLog('Attempting signaling reconnect...');
          await _openConnection();

          if (_isConnected) {
            _isReconnecting = false;
            infoLog('Signaling reconnect succeeded.');
            return;
          }
        } catch (_) {
          // _openConnection already logs and emits errors.
        }
      }

      _isReconnecting = false;

      if (!_isDisposed && !_isStopping) {
        _scheduleReconnect();
      }
    }();
  }

  @override
  Future<void> sendEnvelope(SignalingEnvelope envelope) async {
    if (_isDisposed) {
      throw StateError('Cannot send envelope after dispose.');
    }

    if (_isStopping) {
      throw StateError('Cannot send envelope while signaling is stopped.');
    }

    final outgoing = _outgoingController;
    if (!_isConnected || outgoing == null || outgoing.isClosed) {
      throw const NoConnectionException();
    }

    outgoing.add(_toProtoEnvelope(envelope));
  }

  @override
  Stream<SignalingPresenceEvent> watchPresence({
    required List<String> targetUris,
  }) async* {
    if (targetUris.isEmpty) return;

    final options = await _authorizedOptions();

    final responseStream = _client.watchPresence(
      signaling_pb.WatchPresenceRequest(
        targets: targetUris
            .map((uri) => signaling_pb.DeviceRef(uri: uri))
            .toList(growable: false),
      ),
      options: options,
    );

    await for (final event in responseStream) {
      yield _fromProtoPresence(event);
    }
  }

  @override
  Future<void> disconnect() async {
    infoLog('Disconnecting signaling gRPC stream.');

    _isStopping = true;
    _isConnected = false;
    _isReconnecting = false;
    _connectFuture = null;

    await _incomingSubscription?.cancel();
    _incomingSubscription = null;

    final outgoing = _outgoingController;
    _outgoingController = null;
    await outgoing?.close();

    _emitStatus(SignalingConnectionStatus.stopped);
  }

  @override
  Future<void> dispose() async {
    infoLog('Disposing signaling gRPC client.');

    _isDisposed = true;
    _isStopping = true;
    _isConnected = false;
    _isReconnecting = false;
    _connectFuture = null;

    await _incomingSubscription?.cancel();
    _incomingSubscription = null;

    final outgoing = _outgoingController;
    _outgoingController = null;
    await outgoing?.close();

    await _messagesController.close();
    await _statusController.close();
  }

  void _emitStatus(SignalingConnectionStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  signaling_pb.SignalEnvelope _toProtoEnvelope(SignalingEnvelope envelope) {
    final proto = signaling_pb.SignalEnvelope(
      messageId: envelope.messageId,
      sessionId: envelope.sessionId,
    );

    if (envelope.from != null) {
      proto.from = signaling_pb.DeviceRef(uri: envelope.from!.uri);
    }
    if (envelope.to != null) {
      proto.to = signaling_pb.DeviceRef(uri: envelope.to!.uri);
    }
    if (envelope.helloDeviceId != null && envelope.helloDeviceId!.isNotEmpty) {
      proto.hello = signaling_pb.HelloPayload(deviceId: envelope.helloDeviceId);
    }
    if (envelope.connectionRequest != null) {
      final request = envelope.connectionRequest!;
      proto.connectionRequest = signaling_pb.ConnectionRequest(
        requestId: request.requestId,
        serviceName: request.serviceName,
        note: request.note,
      );
    }
    if (envelope.connectionResponse != null) {
      final response = envelope.connectionResponse!;
      proto.connectionResponse = signaling_pb.ConnectionResponse(
        requestId: response.requestId,
        status: _toProtoResponseStatus(response.status),
        reason: response.reason,
      );
    }
    if (envelope.offer != null) {
      proto.offer = signaling_pb.OfferPayload(
        requestId: envelope.offer!.requestId,
        sdp: envelope.offer!.sdp,
      );
    }
    if (envelope.answer != null) {
      proto.answer = signaling_pb.AnswerPayload(
        requestId: envelope.answer!.requestId,
        sdp: envelope.answer!.sdp,
      );
    }
    if (envelope.iceCandidate != null) {
      final candidate = envelope.iceCandidate!;
      proto.iceCandidate = signaling_pb.IceCandidatePayload(
        requestId: candidate.requestId,
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMlineIndex: candidate.sdpMLineIndex,
      );
    }
    if (envelope.pingTimestampMs != null) {
      proto.ping = signaling_pb.PingPayload(
        timestampMs: fixnum.Int64(envelope.pingTimestampMs!),
      );
    }
    if (envelope.pongTimestampMs != null) {
      proto.pong = signaling_pb.PongPayload(
        timestampMs: fixnum.Int64(envelope.pongTimestampMs!),
      );
    }

    return proto;
  }

  SignalingEnvelope _fromProtoEnvelope(signaling_pb.SignalEnvelope proto) {
    return SignalingEnvelope(
      messageId: proto.messageId,
      sessionId: proto.sessionId,
      from: proto.hasFrom() ? SignalingDeviceRef(uri: proto.from.uri) : null,
      to: proto.hasTo() ? SignalingDeviceRef(uri: proto.to.uri) : null,
      helloDeviceId: proto.hasHello() ? proto.hello.deviceId : null,
      connectionRequest: proto.hasConnectionRequest()
          ? SignalingConnectionRequest(
              requestId: proto.connectionRequest.requestId,
              serviceName: proto.connectionRequest.serviceName,
              note: proto.connectionRequest.note,
            )
          : null,
      connectionResponse: proto.hasConnectionResponse()
          ? SignalingConnectionResponse(
              requestId: proto.connectionResponse.requestId,
              status: _fromProtoResponseStatus(proto.connectionResponse.status),
              reason: proto.connectionResponse.reason,
            )
          : null,
      offer: proto.hasOffer()
          ? SignalingOffer(
              requestId: proto.offer.requestId,
              sdp: proto.offer.sdp,
            )
          : null,
      answer: proto.hasAnswer()
          ? SignalingAnswer(
              requestId: proto.answer.requestId,
              sdp: proto.answer.sdp,
            )
          : null,
      iceCandidate: proto.hasIceCandidate()
          ? SignalingIceCandidate(
              requestId: proto.iceCandidate.requestId,
              candidate: proto.iceCandidate.candidate,
              sdpMid: proto.iceCandidate.sdpMid,
              sdpMLineIndex: proto.iceCandidate.sdpMlineIndex,
            )
          : null,
      pingTimestampMs: proto.hasPing() ? proto.ping.timestampMs.toInt() : null,
      pongTimestampMs: proto.hasPong() ? proto.pong.timestampMs.toInt() : null,
    );
  }

  SignalingPresenceEvent _fromProtoPresence(signaling_pb.PresenceEvent event) {
    return SignalingPresenceEvent(
      deviceUri: event.device.uri,
      status: event.status.name,
      lastSeenAtMs: event.lastSeenAtMs.toInt(),
    );
  }

  signaling_pb.ConnectionResponseStatus _toProtoResponseStatus(
    SignalingConnectionResponseStatus status,
  ) {
    switch (status) {
      case SignalingConnectionResponseStatus.accepted:
        return signaling_pb.ConnectionResponseStatus.ACCEPTED;
      case SignalingConnectionResponseStatus.rejected:
        return signaling_pb.ConnectionResponseStatus.REJECTED;
      case SignalingConnectionResponseStatus.busy:
        return signaling_pb.ConnectionResponseStatus.BUSY;
      case SignalingConnectionResponseStatus.blocked:
        return signaling_pb.ConnectionResponseStatus.BLOCKED;
      case SignalingConnectionResponseStatus.disconnected:
        return signaling_pb.ConnectionResponseStatus.DISCONNECTED;
      case SignalingConnectionResponseStatus.unspecified:
        return signaling_pb
            .ConnectionResponseStatus
            .CONNECTION_RESPONSE_STATUS_UNSPECIFIED;
    }
  }

  SignalingConnectionResponseStatus _fromProtoResponseStatus(
    signaling_pb.ConnectionResponseStatus status,
  ) {
    switch (status) {
      case signaling_pb.ConnectionResponseStatus.ACCEPTED:
        return SignalingConnectionResponseStatus.accepted;
      case signaling_pb.ConnectionResponseStatus.REJECTED:
        return SignalingConnectionResponseStatus.rejected;
      case signaling_pb.ConnectionResponseStatus.BUSY:
        return SignalingConnectionResponseStatus.busy;
      case signaling_pb.ConnectionResponseStatus.BLOCKED:
        return SignalingConnectionResponseStatus.blocked;
      case signaling_pb.ConnectionResponseStatus.DISCONNECTED:
        return SignalingConnectionResponseStatus.disconnected;
      case signaling_pb
          .ConnectionResponseStatus
          .CONNECTION_RESPONSE_STATUS_UNSPECIFIED:
      default:
        return SignalingConnectionResponseStatus.unspecified;
    }
  }

  Future<CallOptions> _authorizedOptions() async {
    var accessToken = await _accessTokenProvider();
    if (accessToken == null || accessToken.isEmpty) {
      await _tryRefreshTokenAfterAuthFailure();
      accessToken = await _accessTokenProvider();
    }

    if (accessToken == null || accessToken.isEmpty) {
      warningLog('Missing signaling access token while authorizing call.');
      throw const UnauthorizedException();
    }

    return CallOptions(
      metadata: <String, String>{'authorization': 'Bearer $accessToken'},
    );
  }

  Future<void> _tryRefreshTokenAfterAuthFailure() async {
    if (!scommDi.isRegistered<SignalingAccessTokenRefresher>()) {
      return;
    }

    try {
      await scommDi<SignalingAccessTokenRefresher>().refreshAccessToken();
    } catch (error) {
      warningLog('Signaling token refresh failed: $error');
    }
  }

  AppException _toAppError(Object error) {
    if (error is AppException) {
      return error;
    }
    if (error is GrpcError) {
      return _mapGrpcError(error);
    }
    return const UnknownAppException(
      message: 'Signaling failed due to an unexpected error.',
    );
  }

  AppException _mapGrpcError(GrpcError error) {
    switch (error.code) {
      case StatusCode.deadlineExceeded:
        return const RequestTimeoutException();
      case StatusCode.unavailable:
        return const NoConnectionException();
      case StatusCode.unauthenticated:
      case StatusCode.permissionDenied:
        return const UnauthorizedException();
      case StatusCode.invalidArgument:
      case StatusCode.notFound:
      case StatusCode.failedPrecondition:
      case StatusCode.internal:
      case StatusCode.unknown:
      case StatusCode.aborted:
      case StatusCode.resourceExhausted:
        return const ServerException();
      default:
        return const UnknownAppException();
    }
  }

  String _buildMessageId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}
