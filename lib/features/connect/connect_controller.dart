import 'dart:async';

import 'package:scommconnector/core/logging/log.dart';
import 'package:scommconnector/core/logging/scomm_diag_log.dart';
import 'package:scommconnector/features/connect/connect_session.dart';
import 'package:scommconnector/features/connect/connect_session_store.dart';
import 'package:scommconnector/features/webrtc/domain/entities/webrtc_ice_server_config.dart';

import '../signaling/application/controllers/signaling_controller.dart';
import '../signaling/domain/entities/signaling_entities.dart';
import '../webrtc/application/controllers/webrtc_controller.dart';
import '../webrtc/application/state/webrtc_state.dart';
import '../webrtc/domain/entities/webrtc_ice_candidate.dart';
import '../webrtc/domain/entities/webrtc_session_description.dart';

class ConnectController {
  final SignalingController signalingController;
  final WebRtcController webRtcController;
  final ConnectSessionStore sessionStore;

  ConnectController({
    required this.signalingController,
    required this.webRtcController,
    required this.sessionStore,
  }) {
    webRtcController.onSessionEnded = (sessionId) {
      unawaited(_cleanupSessionAfterWebRtcEnded(sessionId));
    };
  }

  StreamSubscription<SignalEnvelope>? _signalingSubscription;
  StreamSubscription<MapEntry<String, WebRtcSessionDescription>>?
  _recoveryOfferSubscription;

  /// Sessions whose incoming offer is currently being processed (initialize →
  /// answer → send).  A duplicate offer that arrives before the first completes
  /// is dropped to prevent "PeerConnection is not initialized" race errors.
  final Set<String> _processingOfferSessions = {};
  final Set<String> _pendingOutgoingRemoteUris = <String>{};
  String? _localUri;
  String? _selectedSessionId;
  List<String> _configuredDataChannels = const [];
  List<WebRtcIceServerConfig> _configuredIceServers = const [];

  final _incomingConnectionRequests =
      StreamController<SignalEnvelope>.broadcast();
  final _cancelledIncomingConnectionRequests =
      StreamController<String>.broadcast();

  Stream<SignalEnvelope> get incomingConnectionRequests =>
      _incomingConnectionRequests.stream;

  /// Emits [requestId] when a pending incoming request is cancelled remotely
  /// (e.g. sender timed out or withdrew the request).
  Stream<String> get cancelledIncomingConnectionRequests =>
      _cancelledIncomingConnectionRequests.stream;

  bool _isSignalingStart = false;

  String? get selectedSessionId => _selectedSessionId;

  /// Remote URIs with an outgoing request awaiting acceptance.
  Set<String> get pendingOutgoingRemoteUris =>
      Set<String>.unmodifiable(_pendingOutgoingRemoteUris);

  /// Notifies listeners when pending outgoing connection activity changes.
  void Function()? onActivityChanged;

  /// Notifies listeners after a session is removed from the local store.
  void Function(String sessionId)? onSessionRemoved;

  void _notifyActivityChanged() => onActivityChanged?.call();

  void _notifySessionRemoved(String sessionId) =>
      onSessionRemoved?.call(sessionId);

  String _sessionIdFromRequestId(String requestId) => requestId;

  ConnectSession? get selectedSession {
    final id = _selectedSessionId;
    if (id == null) return null;
    return sessionStore.getBySessionId(id);
  }

  /// Selects an existing session for [remoteUri] (exact then soft match).
  ///
  /// Returns false when no matching session exists. Does not create WebRTC.
  bool selectSessionByRemoteUri(String remoteUri) {
    final session = sessionStore.getByRemoteUri(remoteUri);
    if (session == null) return false;
    if (webRtcController.stateOf(session.sessionId).status !=
        WebRtcStatus.connected) {
      return false;
    }
    _selectedSessionId = session.sessionId;
    _notifyActivityChanged();
    return true;
  }

  Future<void> start({
    required String deviceId,
    required String localUri,
    required List<String> dataChannels,
    List<WebRtcIceServerConfig> iceServers = const [],
  }) async {
    _localUri = localUri;
    _configuredDataChannels = List<String>.from(dataChannels);
    _configuredIceServers = List<WebRtcIceServerConfig>.from(iceServers);

    if (_isSignalingStart) {
      infoLog('Signaling stack is already started.');
      return;
    }

    try {
      _isSignalingStart = true;
      await signalingController.start(deviceId: deviceId);

      await _signalingSubscription?.cancel();
      _signalingSubscription = signalingController.incomingMessages.listen(
        _handleSignalingEnvelope,
        onError: (error, stackTrace) {
          infoLog('Error handling signaling envelope: $error');
        },
      );

      // Listen for ICE-restart offers produced by recovery so we can forward
      // them to the remote peer via signaling.  Without this the remote side
      // never knows about the restart and the connection can never recover.
      await _recoveryOfferSubscription?.cancel();
      _recoveryOfferSubscription = webRtcController.recoveryOfferStream.listen(
        (entry) => _sendRecoveryOffer(sessionId: entry.key, offer: entry.value),
        onError: (error) {
          infoLog('Error handling recovery offer: $error');
        },
      );
    } catch (error) {
      _isSignalingStart = false;
      await signalingController.stop();
      rethrow;
    }
  }

  Future<void> stopSignaling() async {
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;

    await _recoveryOfferSubscription?.cancel();
    _recoveryOfferSubscription = null;

    await signalingController.stop();

    _isSignalingStart = false;
  }

  Future<void> stopWebRtcSession(String sessionId) async {
    final session = sessionStore.getBySessionId(sessionId);

    if (_selectedSessionId == sessionId) {
      _selectedSessionId = null;
    }

    if (session != null) {
      await _sendDisconnectNotice(
        sessionId,
        session: session,
      );
      sessionStore.remove(sessionId);
      await session.dispose();
      _notifySessionRemoved(sessionId);
    }

    await webRtcController.close(sessionId);
    _notifyActivityChanged();
  }

  Future<void> _cleanupSessionAfterWebRtcEnded(String sessionId) async {
    final session = sessionStore.remove(sessionId);
    if (session == null) {
      return;
    }

    if (_selectedSessionId == sessionId) {
      _selectedSessionId = null;
    }

    await session.dispose();
    _notifySessionRemoved(sessionId);
    _notifyActivityChanged();
  }

  Future<void> initiateConnection({
    required String toUri,
    required String serviceName,
    String note = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_shouldDropOutgoingRequest(toUri: toUri)) {
      infoLog('Dropping outgoing connection request to $toUri.');
      ScommDiagLog.connect('outgoing_dropped', {
        'toUri': toUri,
        'serviceName': serviceName,
      });
      return;
    }

    final fromUri = _requireLocalUri();
    final requestId = _buildRequestId();
    final sessionId = _sessionIdFromRequestId(requestId);

    ScommDiagLog.connect('outgoing_start', {
      'requestId': requestId,
      'sessionId': sessionId,
      'fromUri': fromUri,
      'toUri': toUri,
      'serviceName': serviceName,
      'timeoutMs': timeout.inMilliseconds,
    });

    _pendingOutgoingRemoteUris.add(toUri);
    _notifyActivityChanged();
    try {
      ScommDiagLog.connect('outgoing_await_accept', {
        'requestId': requestId,
        'toUri': toUri,
      });
      await signalingController.sendConnectionRequest(
        requestId: requestId,
        fromUri: fromUri,
        toUri: toUri,
        serviceName: serviceName,
        note: note,
        timeout: timeout,
      );
      ScommDiagLog.connect('outgoing_accepted', {
        'requestId': requestId,
        'sessionId': sessionId,
        'toUri': toUri,
      });

      sessionStore.save(
        ConnectSession(
          sessionId: sessionId,
          requestId: requestId,
          remoteUri: toUri,
        ),
      );
      _selectedSessionId = sessionId;

      try {
        ScommDiagLog.connect('outgoing_webrtc_init', {
          'sessionId': sessionId,
          'channels': _configuredDataChannels.length,
        });
        await webRtcController.initialize(
          sessionId: sessionId,
          dataChannels: _configuredDataChannels,
          iceServers: _configuredIceServers,
        );

        await _bindLocalIce(sessionId);

        ScommDiagLog.connect('outgoing_create_offer', {'sessionId': sessionId});
        final offer = await webRtcController.createOffer(sessionId: sessionId);

        ScommDiagLog.connect('outgoing_send_offer', {
          'sessionId': sessionId,
          'requestId': requestId,
          'sdpLen': offer.sdp.length,
        });
        await _sendOffer(offer: offer, toUri: toUri, requestId: requestId);
        ScommDiagLog.connect('outgoing_offer_sent', {
          'sessionId': sessionId,
          'requestId': requestId,
        });
      } catch (error) {
        ScommDiagLog.connect('outgoing_webrtc_failed', {
          'sessionId': sessionId,
          'error': error,
        });
        await stopWebRtcSession(sessionId);
        rethrow;
      }
    } catch (error) {
      ScommDiagLog.connect('outgoing_failed', {
        'requestId': requestId,
        'toUri': toUri,
        'error': error,
      });
      rethrow;
    } finally {
      _pendingOutgoingRemoteUris.remove(toUri);
      _notifyActivityChanged();
    }
  }

  Future<void> acceptIncomingRequest({
    required SignalEnvelope requestEnvelope,
    required bool accept,
    String reason = '',
  }) async {
    final fromUri = _requireLocalUri();
    final toUri = requestEnvelope.from?.uri;
    final request = requestEnvelope.connectionRequest;

    ScommDiagLog.connect('incoming_respond_start', {
      'accept': accept,
      'reason': reason,
      'fromUri': fromUri,
      'remoteUri': toUri,
      'hasRequest': request != null,
    });

    if (toUri == null || request == null) {
      ScommDiagLog.connect('incoming_respond_invalid', {
        'toUri': toUri,
        'hasRequest': request != null,
      });
      throw StateError(
        'Incoming request is missing from uri or request payload.',
      );
    }

    final requestId = request.requestId;
    final sessionId = _sessionIdFromRequestId(requestId);

    ScommDiagLog.connect('incoming_send_response', {
      'requestId': requestId,
      'sessionId': sessionId,
      'accept': accept,
      'toUri': toUri,
    });
    await signalingController.sendEnvelope(
      SignalEnvelope(
        messageId: _buildRequestId(),
        from: SignalingDeviceRef(uri: fromUri),
        to: SignalingDeviceRef(uri: toUri),
        connectionResponse: SignalingConnectionResponse(
          requestId: requestId,
          status: accept
              ? SignalingConnectionResponseStatus.accepted
              : SignalingConnectionResponseStatus.rejected,
          reason: reason,
        ),
      ),
    );
    ScommDiagLog.connect('incoming_response_sent', {
      'requestId': requestId,
      'accept': accept,
    });

    if (!accept) return;

    sessionStore.save(
      ConnectSession(
        sessionId: sessionId,
        requestId: requestId,
        remoteUri: toUri,
      ),
    );
    _selectedSessionId = sessionId;

    ScommDiagLog.connect('incoming_webrtc_init', {
      'sessionId': sessionId,
      'channels': 0,
    });
    // Answerer must NOT create data channels — only the offerer creates them.
    // Pre-creating here races libdatachannel negotiation and breaks `main`.
    await webRtcController.initialize(
      sessionId: sessionId,
      dataChannels: const [],
      iceServers: _configuredIceServers,
    );

    await _bindLocalIce(sessionId);
    ScommDiagLog.connect('incoming_ready_for_offer', {
      'sessionId': sessionId,
      'requestId': requestId,
      'webrtcStatus': webRtcController.stateOf(sessionId).status.name,
    });
  }

  Future<void> _handleSignalingEnvelope(SignalEnvelope envelope) async {
    try {
      ScommDiagLog.connect('envelope_received', {
        'payloadType': envelope.payloadType.name,
        'from': envelope.from?.uri,
        'to': envelope.to?.uri,
        'messageId': envelope.messageId,
      });
      switch (envelope.payloadType) {
        case SignalingPayloadType.connectionRequest:
          final request = envelope.connectionRequest;
          final remoteUri = envelope.from?.uri;

          if (request != null &&
              remoteUri != null &&
              _shouldDropIncomingRequest(
                remoteUri: remoteUri,
                requestId: request.requestId,
              )) {
            infoLog(
              'Dropping incoming connection request from $remoteUri requestId=${request.requestId}.',
            );
            ScommDiagLog.connect('incoming_request_dropped', {
              'requestId': request.requestId,
              'remoteUri': remoteUri,
            });
            break;
          }

          ScommDiagLog.connect('incoming_request_queued', {
            'requestId': request?.requestId,
            'remoteUri': remoteUri,
            'serviceName': request?.serviceName,
          });
          _incomingConnectionRequests.add(envelope);
          break;

        case SignalingPayloadType.offer:
          final remoteOffer = envelope.offer;
          final remoteUri = envelope.from?.uri;

          if (remoteOffer == null || remoteUri == null) {
            ScommDiagLog.connect('offer_ignored_incomplete', {
              'hasOffer': remoteOffer != null,
              'remoteUri': remoteUri,
            });
            break;
          }

          final requestId = remoteOffer.requestId;
          final sessionId = _sessionIdFromRequestId(requestId);
          final existingStatus = webRtcController.stateOf(sessionId).status;

          ScommDiagLog.connect('offer_received', {
            'requestId': requestId,
            'sessionId': sessionId,
            'remoteUri': remoteUri,
            'existingStatus': existingStatus.name,
            'sdpLen': remoteOffer.sdp.length,
          });

          if (_shouldDropIncomingRequest(
            remoteUri: remoteUri,
            requestId: requestId,
          )) {
            infoLog(
              'Dropping incoming offer from $remoteUri requestId=$requestId.',
            );
            ScommDiagLog.connect('offer_dropped_policy', {
              'requestId': requestId,
              'sessionId': sessionId,
            });
            break;
          }

          // Guard against concurrent offer processing for the same session.
          // A duplicate offer that races the ongoing initialize → answer flow
          // would hit "PeerConnection is not initialized" and must be dropped.
          if (_processingOfferSessions.contains(sessionId)) {
            infoLog(
              'Dropping duplicate offer: offer already in progress. sessionId=$sessionId',
            );
            ScommDiagLog.connect('offer_dropped_in_progress', {
              'sessionId': sessionId,
            });
            break;
          }
          _processingOfferSessions.add(sessionId);
          try {
            sessionStore.save(
              ConnectSession(
                sessionId: sessionId,
                requestId: requestId,
                remoteUri: remoteUri,
              ),
            );
            _selectedSessionId = sessionId;

            if (webRtcController.stateOf(sessionId).status ==
                WebRtcStatus.initial) {
              ScommDiagLog.connect('offer_init_missing_session', {
                'sessionId': sessionId,
              });
              await webRtcController.initialize(
                sessionId: sessionId,
                dataChannels: _configuredDataChannels,
                iceServers: _configuredIceServers,
              );
              await _bindLocalIce(sessionId);
            } else {
              ScommDiagLog.connect('offer_reuse_session', {
                'sessionId': sessionId,
                'status': webRtcController.stateOf(sessionId).status.name,
              });
            }

            final offer = WebRtcSessionDescription(
              type: 'offer',
              sdp: remoteOffer.sdp,
            );

            ScommDiagLog.connect('offer_create_answer', {
              'sessionId': sessionId,
            });
            final answer = await _createAnswerForIncomingOffer(
              sessionId: sessionId,
              offer: offer,
            );

            ScommDiagLog.connect('offer_send_answer', {
              'sessionId': sessionId,
              'requestId': requestId,
              'sdpLen': answer.sdp.length,
            });
            await _sendAnswer(
              answer: answer,
              toUri: remoteUri,
              requestId: requestId,
            );
            ScommDiagLog.connect('offer_answer_sent', {
              'sessionId': sessionId,
              'requestId': requestId,
            });
          } catch (error) {
            ScommDiagLog.connect('offer_handle_failed', {
              'sessionId': sessionId,
              'requestId': requestId,
              'error': error,
            });
            rethrow;
          } finally {
            _processingOfferSessions.remove(sessionId);
          }
          break;

        case SignalingPayloadType.answer:
          final remoteAnswer = envelope.answer;
          if (remoteAnswer == null) break;

          final sessionId = _sessionIdFromRequestId(remoteAnswer.requestId);
          ScommDiagLog.connect('answer_received', {
            'requestId': remoteAnswer.requestId,
            'sessionId': sessionId,
            'sdpLen': remoteAnswer.sdp.length,
            'webrtcStatus': webRtcController.stateOf(sessionId).status.name,
          });

          await webRtcController.setRemoteAnswer(
            sessionId: sessionId,
            answer: WebRtcSessionDescription(
              type: 'answer',
              sdp: remoteAnswer.sdp,
            ),
          );
          ScommDiagLog.connect('answer_applied', {'sessionId': sessionId});
          break;

        case SignalingPayloadType.iceCandidate:
          final remoteIce = envelope.iceCandidate;
          if (remoteIce == null) break;

          final sessionId = _sessionIdFromRequestId(remoteIce.requestId);
          ScommDiagLog.connect('ice_remote', {
            'requestId': remoteIce.requestId,
            'sessionId': sessionId,
            'sdpMid': remoteIce.sdpMid,
            'sdpMLineIndex': remoteIce.sdpMLineIndex,
          });

          await webRtcController.addRemoteIceCandidate(
            sessionId: sessionId,
            candidate: WebRtcIceCandidate(
              candidate: remoteIce.candidate,
              sdpMid: remoteIce.sdpMid,
              sdpMLineIndex: remoteIce.sdpMLineIndex,
            ),
          );
          break;

        case SignalingPayloadType.connectionResponse:
          final response = envelope.connectionResponse;
          if (response == null) break;

          ScommDiagLog.connect('connection_response', {
            'requestId': response.requestId,
            'status': response.status.name,
            'reason': response.reason,
          });

          if (response.status ==
              SignalingConnectionResponseStatus.disconnected) {
            final sessionId = _sessionIdFromRequestId(response.requestId);
            // Mark the session before closing so WebRtcController skips recovery.
            webRtcController.markRemoteClosed(sessionId);
            await stopWebRtcSession(sessionId);
            break;
          }

          if (response.status == SignalingConnectionResponseStatus.rejected ||
              response.status == SignalingConnectionResponseStatus.busy ||
              response.status == SignalingConnectionResponseStatus.blocked) {
            _notifyIncomingRequestCancelled(response.requestId);
          }
          break;
        case SignalingPayloadType.ping:
        case SignalingPayloadType.pong:
          break;

        default:
          infoLog('Received unsupported signaling envelope: $envelope');
          break;
      }
    } catch (e) {
      infoLog('Error handling signaling envelope: $e');
      ScommDiagLog.connect('envelope_handler_error', {
        'payloadType': envelope.payloadType.name,
        'error': e,
      });
    }
  }

  void _notifyIncomingRequestCancelled(String requestId) {
    final normalized = requestId.trim();
    if (normalized.isEmpty || _cancelledIncomingConnectionRequests.isClosed) {
      return;
    }

    infoLog('Incoming connection request cancelled remotely: $normalized');
    _cancelledIncomingConnectionRequests.add(normalized);
    _notifyActivityChanged();
  }

  Future<void> _bindLocalIce(String sessionId) async {
    final session = sessionStore.getBySessionId(sessionId);
    if (session == null) return;

    await session.localIceSubscription?.cancel();
    session.localIceSubscription = webRtcController
        .localIceCandidates(sessionId)
        .listen(
          (candidate) => _forwardLocalIceCandidate(
            sessionId: sessionId,
            candidate: candidate,
          ),
          onError: (error, stackTrace) {
            infoLog('Error forwarding ICE candidate: $error');
          },
        );
  }

  Future<void> _forwardLocalIceCandidate({
    required String sessionId,
    required WebRtcIceCandidate candidate,
  }) async {
    final localUri = _localUri;
    final session = sessionStore.getBySessionId(sessionId);

    if (localUri == null || session == null) return;

    // Do not forward candidates when the session is permanently failed or
    // closed — the remote peer would ignore them and it wastes signaling
    // bandwidth.
    final status = webRtcController.stateOf(sessionId).status;
    if (status == WebRtcStatus.failed || status == WebRtcStatus.closed) {
      return;
    }

    await signalingController.sendEnvelope(
      SignalEnvelope(
        messageId: _buildRequestId(),
        from: SignalingDeviceRef(uri: localUri),
        to: SignalingDeviceRef(uri: session.remoteUri),
        iceCandidate: SignalingIceCandidate(
          requestId: session.requestId,
          candidate: candidate.candidate,
          sdpMid: candidate.sdpMid ?? '',
          sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
        ),
      ),
    );
  }

  /// Forward a recovery (ICE-restart) offer to the remote peer via signaling.
  /// This is essential: without it the remote side never processes the restart
  /// and the WebRTC connection can never recover.
  Future<void> _sendRecoveryOffer({
    required String sessionId,
    required WebRtcSessionDescription offer,
  }) async {
    final session = sessionStore.getBySessionId(sessionId);
    final localUri = _localUri;
    if (session == null || localUri == null) return;

    infoLog(
      'Forwarding recovery offer via signaling. sessionId=$sessionId requestId=${session.requestId}',
    );

    try {
      await signalingController.sendEnvelope(
        SignalEnvelope(
          messageId: _buildRequestId(),
          from: SignalingDeviceRef(uri: localUri),
          to: SignalingDeviceRef(uri: session.remoteUri),
          offer: SignalingOffer(requestId: session.requestId, sdp: offer.sdp),
        ),
      );
    } catch (e) {
      infoLog('Failed to forward recovery offer: $e');
    }
  }

  /// Notifies the remote peer that this side is intentionally closing the
  /// session.  The remote side will receive a [connectionResponse] with
  /// [SignalingConnectionResponseStatus.disconnected] and suppress recovery.
  ///
  /// Skipped when the remote already closed the session (they initiated the
  /// disconnect) to avoid an unnecessary echo that could interfere with them
  /// re-establishing a new connection.
  Future<void> _sendDisconnectNotice(
    String sessionId, {
    ConnectSession? session,
  }) async {
    // Remote already knows — don't echo back.
    if (webRtcController.isRemoteClosed(sessionId)) return;

    final activeSession = session ?? sessionStore.getBySessionId(sessionId);
    final localUri = _localUri;
    if (activeSession == null || localUri == null) return;

    try {
      await signalingController.sendEnvelope(
        SignalEnvelope(
          messageId: _buildRequestId(),
          from: SignalingDeviceRef(uri: localUri),
          to: SignalingDeviceRef(uri: activeSession.remoteUri),
          connectionResponse: SignalingConnectionResponse(
            requestId: activeSession.requestId,
            status: SignalingConnectionResponseStatus.disconnected,
          ),
        ),
      );
    } catch (e) {
      // Best-effort: if signaling is already down the remote will time out.
      infoLog('Failed to send disconnect notice: $e');
    }
  }

  Future<void> _sendOffer({
    required WebRtcSessionDescription offer,
    required String toUri,
    required String requestId,
  }) {
    return signalingController.sendEnvelope(
      SignalEnvelope(
        messageId: _buildRequestId(),
        from: SignalingDeviceRef(uri: _requireLocalUri()),
        to: SignalingDeviceRef(uri: toUri),
        offer: SignalingOffer(requestId: requestId, sdp: offer.sdp),
      ),
    );
  }

  Future<void> _sendAnswer({
    required WebRtcSessionDescription answer,
    required String toUri,
    required String requestId,
  }) {
    return signalingController.sendEnvelope(
      SignalEnvelope(
        messageId: _buildRequestId(),
        from: SignalingDeviceRef(uri: _requireLocalUri()),
        to: SignalingDeviceRef(uri: toUri),
        answer: SignalingAnswer(requestId: requestId, sdp: answer.sdp),
      ),
    );
  }

  String _requireLocalUri() {
    final localUri = _localUri;
    if (localUri == null || localUri.isEmpty) {
      throw StateError('Local URI is not initialized.');
    }
    return localUri;
  }

  String _buildRequestId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  // Future<void> _prepareForIncomingOffer({
  //   required String remoteUri,
  //   required String requestId,
  // }) async {
  //   final isFreshRemoteSession =
  //       _activeRequestId != null &&
  //       (_activeRequestId != requestId || _remoteUri != remoteUri);

  //   infoLog(
  //     'Preparing incoming offer: activeRequestId=$_activeRequestId activeRemoteUri=$_remoteUri incomingRequestId=$requestId incomingRemoteUri=$remoteUri isFreshRemoteSession=$isFreshRemoteSession webrtcSessionGeneration=$_webrtcSessionGeneration',
  //   );

  //   if (isFreshRemoteSession) {
  //     infoLog(
  //       'Resetting WebRTC session for fresh incoming offer requestId $requestId.',
  //     );
  //     await _resetWebRtcSession();
  //   }

  //   _remoteUri = remoteUri;
  //   _activeRequestId = requestId;
  // }

  Future<WebRtcSessionDescription> _createAnswerForIncomingOffer({
    required String sessionId,
    required WebRtcSessionDescription offer,
  }) async {
    try {
      return await webRtcController.createAnswerForOffer(
        sessionId: sessionId,
        offer: offer,
      );
    } catch (error) {
      if (!_isHaveLocalOfferError(error)) rethrow;

      await webRtcController.close(sessionId);

      await webRtcController.initialize(
        sessionId: sessionId,
        dataChannels: _configuredDataChannels,
        iceServers: _configuredIceServers,
      );

      await _bindLocalIce(sessionId);

      return webRtcController.createAnswerForOffer(
        sessionId: sessionId,
        offer: offer,
      );
    }
  }

  // Future<void> _resetWebRtcSession() async {
  //   final nextGeneration = _webrtcSessionGeneration + 1;
  //   infoLog(
  //     'Resetting WebRTC session: previousGeneration=$_webrtcSessionGeneration nextGeneration=$nextGeneration activeRequestId=$_activeRequestId remoteUri=$_remoteUri dataChannels=${_configuredDataChannels.length} iceServers=${_configuredIceServers.length}',
  //   );
  //   await webRtcController.close(_activeRequestId!);
  //   await _initializeWebRtcSession(reason: 'reset');
  //   infoLog(
  //     'WebRTC session reset complete: currentGeneration=$_webrtcSessionGeneration activeRequestId=$_activeRequestId remoteUri=$_remoteUri',
  //   );
  // }

  // Future<void> _initializeWebRtcSession({required String reason}) async {
  //   final nextGeneration = _webrtcSessionGeneration + 1;
  //   infoLog(
  //     'Initializing WebRTC session generation=$nextGeneration reason=$reason dataChannels=${_configuredDataChannels.length} iceServers=${_configuredIceServers.length}',
  //   );
  //   await webRtcController.initialize(
  //     sessionId: _activeRequestId!,
  //     dataChannels: _configuredDataChannels,
  //     iceServers: _configuredIceServers,
  //   );
  //   _webrtcSessionGeneration = nextGeneration;
  //   infoLog(
  //     'Initialized WebRTC session generation=$_webrtcSessionGeneration reason=$reason',
  //   );
  // }

  bool _isHaveLocalOfferError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('have-local-offer') ||
        (message.contains('wrong state') && message.contains('local-offer'));
  }

  bool _shouldDropIncomingRequest({
    required String remoteUri,
    required String requestId,
  }) {
    final existing = sessionStore.getByRemoteUri(remoteUri);
    if (existing == null) return false;

    return webRtcController.stateOf(existing.sessionId).status ==
            WebRtcStatus.connected &&
        existing.requestId != requestId;
  }

  bool _shouldDropOutgoingRequest({required String toUri}) {
    final existing = sessionStore.getByRemoteUri(toUri);
    if (existing == null) return false;

    final status = webRtcController.stateOf(existing.sessionId).status;
    return status == WebRtcStatus.connected ||
        status == WebRtcStatus.negotiating ||
        status == WebRtcStatus.retrying ||
        status == WebRtcStatus.initializing;
  }
}
