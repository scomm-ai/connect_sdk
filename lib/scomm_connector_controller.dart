import 'dart:async';
import 'dart:convert';
import 'package:scommconnector/core/logging/log.dart';
import 'package:scommconnector/core/logging/scomm_diag_log.dart';
import 'package:scommconnector/features/auth/auth.dart';
import 'package:scommconnector/features/identity/identity.dart';
import 'package:scommconnector/features/scomm_session_state.dart';
import 'package:scommconnector/features/signaling/signaling.dart';
import 'package:scommconnector/features/webrtc/webrtc.dart';
import 'package:scommconnector/core/di/service_locator.dart';
import 'package:scommconnector/features/connect/connect_controller.dart';
import 'package:scommconnector/features/connect/datachannel/scomm_datachannel_controller.dart';
import 'package:scommconnector/features/connect/datachannel/scomm_datachannel_protocol.dart';
import 'package:scommconnector/features/connect/datachannel/scomm_datachannel_transport.dart';
import 'package:scommconnector/features/connect/datachannel/scomm_transfer_speed.dart';
import 'package:scommconnector/scomm_start_config.dart';

/////// Main public API surface of the ScommConnector package. This class is a singleton
/////// that provides high-level methods for authentication, identity management, connection handling, and data channel communication.
/////// It internally uses the various controllers and services defined in the package, and exposes a simplified interface for consumers.
/////// Consumers can listen to various streams for updates on connection state, incoming messages, presence events, etc., and can send messages or connection requests using the provided methods.

class ScommConnectorController {
  static final ScommConnectorController _instance =
      ScommConnectorController._internal();
  factory ScommConnectorController() => _instance;

  // Private constructor for singleton pattern
  ScommConnectorController._internal() {
    // Initialize the data channel controller with transport callbacks
    _datachannelController = ScommDatachannelController(
      transport: ScommDataChannelTransport(
        sendRawMessage: _sendTrackedRawMessage,
        isConnected: _canSendDataChannel,
      ),
    );
    _authStateSubscription = _authController.authStates.listen((_) {
      if (!_stateChangesController.isClosed) {
        _stateChangesController.add(null);
      }
    });
    _startTransferSpeedTicker();
  }

  // Stream exposed for consumers to listen
  StreamSubscription? _authSub;
  StreamSubscription? _identitySub;
  StreamSubscription? _signalingSub;
  StreamSubscription? _webrtcSub;
  StreamSubscription<WebRtcIceRoute>? _iceRouteSubscription;

  final _webrtccontroller = scommDi<WebRtcController>();
  final _connectController = scommDi<ConnectController>();
  final _identityController = scommDi<IdentityController>();
  final _authController = scommDi<ScommAuthController>();
  final _stateChangesController = StreamController<void>.broadcast();
  late ScommDatachannelController _datachannelController;
  final _dataMessageSubscriptions =
      <String, StreamSubscription<WebRtcDataMessage>>{};
  final _requestSessionByRequestId = <String, String>{};
  StreamSubscription<AuthState>? _authStateSubscription;
  final _incomingRequestCache = <String, SignalEnvelope>{};
  Timer? _transferSpeedTimer;
  int _sentBytesSinceLastTick = 0;
  int _receivedBytesSinceLastTick = 0;
  ScommTransferSpeed _transferSpeed = const ScommTransferSpeed();
  WebRtcIceRoute _iceRoute = const WebRtcIceRoute();
  final _transferSpeedController =
      StreamController<ScommTransferSpeed>.broadcast();
  final _iceRouteController = StreamController<WebRtcIceRoute>.broadcast();

  ///// Exposed state and streams for consumers.
  ScommSessionState _sessionState = ScommSessionState.initial();
  final _sessionStateController =
      StreamController<ScommSessionState>.broadcast();

  /// Returns the latest combined auth, identity, signaling, and WebRTC state.
  ScommSessionState get sessionState => _sessionState;

  /// Emits a new session snapshot whenever any core connector state changes.
  Stream<ScommSessionState> get stream => _sessionStateController.stream;

  /// Returns the latest measured data channel upload and download speed.
  ScommTransferSpeed get transferSpeed => _transferSpeed;

  /// Emits transfer speed updates once per second.
  Stream<ScommTransferSpeed> get transferSpeeds =>
      _transferSpeedController.stream;

  /// Returns the latest ICE route selected for the active WebRTC session.
  WebRtcIceRoute get iceRoute => _iceRoute;

  /// Emits ICE route changes for the active WebRTC session.
  Stream<WebRtcIceRoute> get iceRoutes => _iceRouteController.stream;

  // Snapshot states for consumers that need synchronous reads.

  /// Returns the current identity snapshot for the authenticated user/device.
  IdentityState get identityState => _identityController.state;

  /// Returns the WebRTC state for the selected session, or an empty state.
  WebRtcState get webrtcState {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) return const WebRtcState();
    return _webrtccontroller.stateOf(sessionId);
  }

  /// Returns the current signaling connection state.
  SignalingState get signalingState =>
      _connectController.signalingController.state;

  /// Emits a simple notification when any exposed state snapshot may be stale.
  Stream<void> get stateChanges => _stateChangesController.stream;

  /// Returns whether the selected WebRTC session can currently send data.
  bool _canSendDataChannel() {
    final status = webrtcState.status;
    return status == WebRtcStatus.connected ||
        status == WebRtcStatus.negotiating ||
        status == WebRtcStatus.retrying;
  }

  /// Emits a session state only when it differs from the current snapshot.
  void _emitSession(ScommSessionState next) {
    if (_sessionState == next) return;
    _sessionState = next;
    _sessionStateController.add(next);
  }

  /// Rebuilds the public session state from auth, identity, signaling, and WebRTC.
  void _syncSessionState() {
    final auth = _authController.state;
    final identity = _identityController.state;
    final signaling = _connectController.signalingController.state;
    final webrtc = webrtcState;

    final connectedRemoteUris = _connectController.sessionStore.all
        .where((session) {
          final status = _webrtccontroller.stateOf(session.sessionId).status;
          return status == WebRtcStatus.connected;
        })
        .map((session) => session.remoteUri)
        .where((uri) => uri.trim().isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final connectingRemoteUris = {
      ..._connectController.pendingOutgoingRemoteUris,
      ..._connectController.sessionStore.all
          .where((session) {
            final status = _webrtccontroller.stateOf(session.sessionId).status;
            return status == WebRtcStatus.initializing ||
                status == WebRtcStatus.negotiating ||
                status == WebRtcStatus.retrying;
          })
          .map((session) => session.remoteUri)
          .where((uri) => uri.trim().isNotEmpty),
    }.toList(growable: false)
      ..sort();

    final selectedRemoteUri = _connectController.selectedSession?.remoteUri;
    final activeRemoteUri = selectedRemoteUri != null &&
            connectedRemoteUris.contains(selectedRemoteUri)
        ? selectedRemoteUri
        : (connectedRemoteUris.isNotEmpty ? connectedRemoteUris.first : null);

    _emitSession(
      ScommSessionState(
        isAuthenticated: auth.isLoggedIn,
        isDeviceRegistered: identity.isRegistered,
        authState: auth,
        identityState: identity,
        signalingState: signaling,
        webRtcState: webrtc,
        activeRemoteUri: activeRemoteUri,
        connectedRemoteUris: connectedRemoteUris,
        connectingRemoteUris: connectingRemoteUris,
      ),
    );
  }

  ///////// Authentication methods ///////////

  /// Initializes cached auth state and subscribes to internal state streams.
  Future<void> initialize() async {
    await _authController.init();

    _connectController.onActivityChanged = _syncSessionState;
    _connectController.onSessionRemoved = (sessionId) {
      unawaited(_dataMessageSubscriptions.remove(sessionId)?.cancel());
      _requestSessionByRequestId.removeWhere((_, mapped) => mapped == sessionId);
      if (_connectController.selectedSessionId == null) {
        unawaited(_iceRouteSubscription?.cancel());
        _iceRouteSubscription = null;
        _resetTransferSpeed();
        _setIceRoute(const WebRtcIceRoute());
      }
    };

    await _authSub?.cancel();
    await _identitySub?.cancel();
    await _signalingSub?.cancel();
    await _webrtcSub?.cancel();
    await _iceRouteSubscription?.cancel();

    _authSub = _authController.authStates.listen((_) => _syncSessionState());
    _identitySub = _identityController.identityStates.listen(
      (_) => _syncSessionState(),
    );
    _signalingSub = _connectController.signalingController.signalingStates
        .listen((_) => _syncSessionState());
    _webrtcSub = _webrtccontroller.webRtcStates.listen(
      (_) => _syncSessionState(),
    );

    _syncSessionState();
  }

  /// Injects an AppAuth (or other host) access token for signaling/identity calls.
  Future<void> setAccessToken(String token, {String? userId}) async {
    try {
      await _authController.setAccessToken(token, userId: userId);
    } catch (e) {
      errorLog('Error during setAccessToken: ${e.toString()}');
      rethrow;
    } finally {
      _syncSessionState();
    }
  }

  /// Logs out the current user and clears the active auth session.
  Future<void> logout() => _authController.logout();

  ////////// Identity methods //////////
  /// Registers the current machine as an SComm device for the logged-in user.
  Future<void> registerDevice(
    String deviceName,
    String deviceType,
    DeviceMode mode,
  ) async {
    infoLog(
      'Registering device with name="$deviceName", type="$deviceType", mode="$mode"',
    );
    await _identityController.registerDevice(
      deviceName: deviceName,
      deviceType: deviceType,
      mode: mode,
    );
  }

  /// Registers a service name under an existing SComm device.
  Future<void> registerService(String deviceId, String serviceName) async {
    await _identityController.registerService(
      deviceId: deviceId,
      serviceName: serviceName,
    );
  }

  /// Lists devices allowlisted for the given local device id.
  Future<List<IdentityDevice>> listAllowlistedDevices(String myDeviceId) =>
      _identityController.listAllowUserDevices(deviceId: myDeviceId);

  /// Loads the locally saved device identity for the given user id or email.
  Future<SavedDeviceIdentity?> loadMyCurrentDeviceIdentity(String userId) {
    ScommDiagLog.identity('pkg_load_my_current', {'lookupKey': userId});
    return _identityController.loadSavedDeviceIdentity(userId);
  }

  /// Lists all devices registered for the current user.
  Future<List<IdentityDevice>> listMyDevices() =>
      _identityController.listMyDevices();

  /// Deletes a registered device by id.
  Future<void> deleteDevice(String deviceId) =>
      _identityController.deleteDevice(deviceId: deviceId);

  /// Deletes a registered service by id.
  Future<void> deleteService(String serviceId) =>
      _identityController.deleteService(serviceId: serviceId);

  /// Lists all services registered for a device.
  Future<List<DeviceService>> listDeviceServices(String deviceId) =>
      _identityController.listDeviceServices(deviceId: deviceId);

  /// Updates the display name of a registered service.
  Future<void> updateService({
    required String serviceId,
    required String serviceName,
  }) {
    return _identityController.updateService(
      serviceId: serviceId,
      serviceName: serviceName,
    );
  }

  /// Adds a user/device pair to the allowlist with the provided state.
  Future<void> addAllowUserDevice({
    required String userId,
    required String deviceId,
    required String state,
  }) {
    return _identityController.addAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
      state: state,
    );
  }

  /// Removes a user/device pair from the allowlist.
  Future<void> removeAllowUserDevice({
    required String userId,
    required String deviceId,
  }) {
    return _identityController.removeAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
    );
  }

  /// Updates the allowlist state for a user/device pair.
  Future<void> updateAllowUserDevice({
    required String userId,
    required String deviceId,
    required String state,
  }) {
    return _identityController.updateAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
      state: state,
    );
  }

  /// Updates the name, type, and mode for a registered device.
  Future<void> updateDevice({
    required String deviceId,
    required String deviceName,
    required String deviceType,
    required DeviceMode mode,
  }) =>
      _identityController.updateDevice(
        deviceId: deviceId,
        mode: mode,
        deviceName: deviceName,
        deviceType: deviceType,
      );

  // Backward-compatible aliases used by runner code.
  /// Backward-compatible alias for registering the current device.
  Future<void> registerDevices(
    String deviceName,
    String deviceType,
    DeviceMode mode,
  ) =>
      registerDevice(deviceName, deviceType, mode);

  /// Backward-compatible alias for loading the saved current device identity.
  Future<SavedDeviceIdentity?> loadMyDevices(String userId) =>
      loadMyCurrentDeviceIdentity(userId);

  ///// Connection and DataChannel methods //////////
  /// Starts signaling/WebRTC for the registered device using the given config.
  Future<void> start(ScommStartConfig config) async {
    final localUri = 'scomm:${config.email}/${config.deviceId}';

    await _connectController.start(
      deviceId: config.deviceId,
      localUri: localUri,
      dataChannels: const [ScommDataChannelTransport.mainChannel],
      iceServers: config.iceServers,
    );

    for (final sub in _dataMessageSubscriptions.values) {
      await sub.cancel();
    }
    _dataMessageSubscriptions.clear();
    _requestSessionByRequestId.clear();
  }

  /// Binds data message and ICE route listeners for all active sessions.
  Future<void> bindSelectedSessionStreams() async {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      for (final sub in _dataMessageSubscriptions.values) {
        await sub.cancel();
      }
      _dataMessageSubscriptions.clear();
      _requestSessionByRequestId.clear();
      // _boundDataSessionId = null;
      await _iceRouteSubscription?.cancel();
      _iceRouteSubscription = null;
      return;
    }

    final activeSessionIds = _connectController.sessionStore.sessionIds.toSet();

    final staleSubscriptions = _dataMessageSubscriptions.keys
        .where((id) => !activeSessionIds.contains(id))
        .toList(growable: false);
    for (final staleSessionId in staleSubscriptions) {
      await _dataMessageSubscriptions.remove(staleSessionId)?.cancel();
    }

    final staleRequestMappings = _requestSessionByRequestId.entries
        .where((entry) => !activeSessionIds.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in staleRequestMappings) {
      _requestSessionByRequestId.remove(requestId);
    }

    for (final activeSessionId in activeSessionIds) {
      if (_dataMessageSubscriptions.containsKey(activeSessionId)) {
        infoLog(
          '[SCOMM-BIND] Session $activeSessionId already subscribed, skipping',
        );
        continue;
      }

      infoLog(
        '[SCOMM-BIND] Subscribing to data messages for session $activeSessionId',
      );
      _dataMessageSubscriptions[activeSessionId] = _webrtccontroller
          .receivedDataMessages(activeSessionId)
          .listen((message) async {
        if (message.channelLabel != ScommDataChannelTransport.mainChannel) {
          return;
        }
        _recordReceivedPayload(message.message);

        // Record request routing before broadcasting to listeners to avoid
        // races where handlers send responses immediately.
        final earlyParsed = _datachannelController.transport.parse(
          message.message,
        );
        final earlyRequestId = earlyParsed?.requestId?.trim();
        if (earlyRequestId != null && earlyRequestId.isNotEmpty) {
          _requestSessionByRequestId[earlyRequestId] = activeSessionId;
        }

        final parsed = await _datachannelController.receiveRawMessage(
          message.message,
        );
        final requestId = parsed?.requestId?.trim();
        if (requestId != null && requestId.isNotEmpty) {
          _requestSessionByRequestId[requestId] = activeSessionId;
        }
      });
    }
    // _boundDataSessionId = sessionId;

    await _iceRouteSubscription?.cancel();
    _iceRouteSubscription =
        _webrtccontroller.iceRoutes(sessionId).listen(_setIceRoute);
  }

  /// Stops the active WebRTC session and disconnects signaling.
  Future<void> stop() async {
    await stopWebRtc();
    await stopSignaling();
  }

  /// Disconnects signaling and clears cached incoming connection requests.
  Future<void> stopSignaling() async {
    _incomingRequestCache.clear();
    await _connectController.stopSignaling();
  }

  /// Stops the currently selected WebRTC session if one exists.
  Future<void> stopWebRtc() async {
    final sessionId = _connectController.selectedSession?.sessionId;
    if (sessionId != null) {
      await _stopWebRtcSession(sessionId);
    }
  }

  /// Stops the WebRTC session associated with the given remote URI.
  Future<void> stopWebRtcForUri(String remoteUri) async {
    final session = _connectController.sessionStore.getByRemoteUri(remoteUri);
    if (session != null) {
      await _stopWebRtcSession(session.sessionId);
    }
  }

  /// Stops one WebRTC session and removes all routing state attached to it.
  Future<void> _stopWebRtcSession(String sessionId) async {
    await _connectController.stopWebRtcSession(sessionId);
    await _dataMessageSubscriptions.remove(sessionId)?.cancel();
    _requestSessionByRequestId.removeWhere((_, mapped) => mapped == sessionId);
    if (_connectController.selectedSessionId == null) {
      await _iceRouteSubscription?.cancel();
      _iceRouteSubscription = null;
      _resetTransferSpeed();
      _setIceRoute(const WebRtcIceRoute());
    }
  }

  /// Cancels subscriptions, closes streams, stops sessions, and releases resources.
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _identitySub?.cancel();
    await _signalingSub?.cancel();
    await _webrtcSub?.cancel();
    await _iceRouteSubscription?.cancel();
    await _authStateSubscription?.cancel();
    for (final sub in _dataMessageSubscriptions.values) {
      await sub.cancel();
    }
    _dataMessageSubscriptions.clear();
    _requestSessionByRequestId.clear();
    _transferSpeedTimer?.cancel();
    await _transferSpeedController.close();
    await _iceRouteController.close();
    await _stateChangesController.close();
    await _datachannelController.dispose();
    await _sessionStateController.close();
    await stop();
  }

  /// Restarts signaling/WebRTC by stopping current sessions and starting again.
  Future<void> restart(ScommStartConfig config) async {
    await stop();
    await start(config);
  }

  /// Emits WebRTC connection state changes for the selected session.
  Stream<WebRtcConnectionState> get scommConnectionState {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      return const Stream.empty();
    }
    return _webrtccontroller.connectionStates(sessionId);
  }

  /// Emits raw WebRTC data messages for the selected session.
  Stream<WebRtcDataMessage> get webrtcDataMessages {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      return const Stream.empty();
    }
    return _webrtccontroller.receivedDataMessages(sessionId);
  }

  /// Refreshes and returns the current ICE route for the selected session.
  Future<WebRtcIceRoute> refreshIceRoute() {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      return Future.value(const WebRtcIceRoute());
    }
    return _webrtccontroller.refreshIceRoute(sessionId);
  }

  /// Emits incoming connection requests and caches them for accept/reject calls.
  Stream<SignalEnvelope> get scommConnectionIncomingRequests =>
      _connectController.incomingConnectionRequests.map((request) {
        final requestId = request.connectionRequest?.requestId;
        if (requestId != null && requestId.isNotEmpty) {
          _incomingRequestCache[requestId] = request;
        }
        return request;
      });

  /// Emits when a pending incoming request was cancelled by the remote sender.
  Stream<String> get cancelledIncomingConnectionRequests =>
      _connectController.cancelledIncomingConnectionRequests.map((requestId) {
        _incomingRequestCache.remove(requestId);
        return requestId;
      });

  /// Emits all incoming signaling envelopes from the signaling controller.
  Stream<SignalEnvelope> get incomingSignalingMessages =>
      _connectController.signalingController.incomingMessages;

  /// Emits parsed SComm data channel messages from active sessions.
  Stream<ScommRemoteMessage> get scommDataChannelMessages =>
      _datachannelController.messages;

  /// Sends a raw string payload over the main data channel.
  Future<void> sendMessageOverDataChannel(String message) async {
    await _sendTrackedRawMessage(
      channelLabel: ScommDataChannelTransport.mainChannel,
      message: message,
    );
  }

  /// Selects an already-open session matching [remoteUri] for datachannel send.
  ///
  /// Returns false when that peer is not in the local session store.
  /// Does not initiate a new connection.
  Future<bool> selectSessionByRemoteUri(String remoteUri) async {
    final selected = _connectController.selectSessionByRemoteUri(remoteUri);
    if (!selected) return false;
    await bindSelectedSessionStreams();
    return true;
  }

  /// Sends a structured request message and returns the request id used.
  Future<String> sendDatachannelRequest({
    required String service,
    required String action,
    required Map<String, dynamic> data,
    String? requestId,
  }) async {
    final id = await _datachannelController.sendRequest(
      service: service,
      action: action,
      data: data,
      requestId: requestId,
    );
    final sessionId = _connectController.selectedSessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      _requestSessionByRequestId[id] = sessionId;
    }
    return id;
  }

  /// Sends a structured response routed to the session that sent the request.
  Future<void> sendDatachannelResponse({
    required String requestId,
    required String service,
    required String action,
    required Map<String, dynamic> data,
  }) {
    return _sendRoutedDataChannelMessage(
      requestId: requestId,
      message: ScommRemoteMessage(
        type: ScommMessageType.response,
        requestId: requestId,
        service: service,
        action: action,
        data: data,
      ),
    );
  }

  /// Sends a structured stream chunk routed by request id.
  Future<void> sendDatachannelStream({
    required String requestId,
    required String service,
    required String action,
    required Map<String, dynamic> data,
  }) {
    return _sendRoutedDataChannelMessage(
      requestId: requestId,
      message: ScommRemoteMessage(
        type: ScommMessageType.stream,
        requestId: requestId,
        service: service,
        action: action,
        data: data,
      ),
    );
  }

  /// Sends a structured event message over the main data channel.
  Future<void> sendDatachannelEvent({
    required String service,
    required String action,
    required Map<String, dynamic> data,
  }) {
    return _datachannelController.sendEvent(
      service: service,
      action: action,
      data: data,
    );
  }

  // Future<ScommRemoteMessage?> receiveRawDatachannelMessage(String rawMessage) {
  //   final words = rawMessage.split(' ');

  //   const int previewCount = 3; // number of words to show

  //   final startWords = words.take(previewCount).join(' ');
  //   final endWords = words.length > previewCount
  //       ? words.skip(words.length - previewCount).join(' ')
  //       : '';

  //   infoLog('Received message preview: $startWords ... $endWords');
  //   return _datachannelController.receiveRawMessage(rawMessage);
  // }

  /// Emits true when the selected session data channel is connected.
  Stream<bool> get isDataChannelOpen {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      return Stream<bool>.value(false);
    }

    return _webrtccontroller
        .connectionStates(sessionId)
        .map((state) => state == WebRtcConnectionState.connected)
        .distinct();
  }

  /// Accepts a cached incoming connection request and binds its session streams.
  Future<void> acceptConnectionRequest(String requestId) async {
    ScommDiagLog.connect('pkg_accept_start', {
      'requestId': requestId,
      'cacheHit': _incomingRequestCache.containsKey(requestId),
      'cacheSize': _incomingRequestCache.length,
    });
    final request = _incomingRequestCache.remove(requestId);
    if (request == null) {
      ScommDiagLog.connect('pkg_accept_unknown_request', {
        'requestId': requestId,
      });
      throw StateError('Unknown requestId: $requestId');
    }

    await _connectController.acceptIncomingRequest(
      requestEnvelope: request,
      accept: true,
    );

    await bindSelectedSessionStreams();
    ScommDiagLog.connect('pkg_accept_done', {
      'requestId': requestId,
      'selectedSessionId': _connectController.selectedSessionId,
    });
  }

  /// Rejects a cached incoming connection request with an optional reason.
  Future<void> rejectConnectionRequest(
    String requestId, {
    String reason = '',
  }) async {
    ScommDiagLog.connect('pkg_reject_start', {
      'requestId': requestId,
      'reason': reason,
      'cacheHit': _incomingRequestCache.containsKey(requestId),
    });
    final request = _incomingRequestCache.remove(requestId);
    if (request == null) {
      ScommDiagLog.connect('pkg_reject_unknown_request', {
        'requestId': requestId,
      });
      throw StateError('Unknown requestId: $requestId');
    }

    await _connectController.acceptIncomingRequest(
      requestEnvelope: request,
      accept: false,
      reason: reason,
    );
  }

  /// Backward-compatible presence stream getter with the original misspelled name.
  Stream<SignalingPresenceEvent> get presebceEvents =>
      _connectController.signalingController.presenceEvents;

  /// Emits presence updates for watched device URIs.
  Stream<SignalingPresenceEvent> get presenceEvents => presebceEvents;

  /// Requests presence updates for the given target device URIs.
  Future<void> watchPresence(List<String> targetUris) {
    return _connectController.signalingController.watchPresence(
      targetUris: targetUris,
    );
  }

  /// Emits the list of watched device URIs currently reported as online.
  Stream<List<String>> get onlineDevicesStream async* {
    final statusByUri = <String, String>{};
    await for (final event in presenceEvents) {
      statusByUri[event.deviceUri] = event.status;
      yield statusByUri.entries
          .where((entry) => _isOnlineStatus(entry.value))
          .map((entry) => entry.key)
          .toList(growable: false);
    }
  }

  /// Sends a connection request to a remote SComm URI using the main channel.
  Future<void> sendConnectionRequest(String deviceId) async {
    await _connectController.initiateConnection(
      toUri: deviceId,
      serviceName: ScommDataChannelTransport.mainChannel,
    );

    await bindSelectedSessionStreams();
  }

  /// Sends a connection request with a custom service name, note, and timeout.
  Future<void> sendConnectionRequestDetailed({
    required String toUri,
    required String serviceName,
    String note = '',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await _connectController.initiateConnection(
      toUri: toUri,
      serviceName: serviceName,
      note: note,
      timeout: timeout,
    );

    await bindSelectedSessionStreams();
  }

  /// Applies a remote WebRTC answer to the selected session.
  Future<void> setRemoteAnswer(WebRtcSessionDescription answer) {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      throw StateError('No active selected WebRTC session.');
    }
    return _webrtccontroller.setRemoteAnswer(
      sessionId: sessionId,
      answer: answer,
    );
  }

  /// Adds a remote ICE candidate to the selected WebRTC session.
  Future<void> addRemoteIceCandidate(WebRtcIceCandidate candidate) {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      throw StateError('No active selected WebRTC session.');
    }
    return _webrtccontroller.addRemoteIceCandidate(
      sessionId: sessionId,
      candidate: candidate,
    );
  }

  /// Adds a data channel with the given label to the selected session.
  Future<void> addDataChannel(String label) {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      throw StateError('No active selected WebRTC session.');
    }
    return _webrtccontroller.addDataChannel(sessionId: sessionId, label: label);
  }

  /// Removes a data channel with the given label from the selected session.
  Future<void> removeDataChannel(String label) {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      throw StateError('No active selected WebRTC session.');
    }
    return _webrtccontroller.removeDataChannel(
      sessionId: sessionId,
      label: label,
    );
  }

  /// Normalizes presence status text and checks whether it means online.
  bool _isOnlineStatus(String status) {
    final normalized = status.trim().toUpperCase();
    return normalized == 'ONLINE' || normalized == 'AVAILABLE';
  }

  /// Sends raw data through WebRTC while updating transfer speed counters.
  Future<void> _sendTrackedRawMessage({
    required String channelLabel,
    required String message,
  }) async {
    final sessionId = _connectController.selectedSessionId;
    if (sessionId == null) {
      throw StateError('No active selected WebRTC session.');
    }

    await bindSelectedSessionStreams();

    _recordSentPayload(message);
    await _webrtccontroller.sendData(
      sessionId: sessionId,
      channelLabel: channelLabel,
      message: message,
    );
  }

  /// Routes response and stream messages back to the session that made the request.
  Future<void> _sendRoutedDataChannelMessage({
    required String requestId,
    required ScommRemoteMessage message,
  }) async {
    final normalizedRequestId = requestId.trim();
    final mappedSessionId = _requestSessionByRequestId[normalizedRequestId];
    infoLog(
      '[SCOMM-ROUTE] Sending type=${message.type.name} action=${message.action} requestId=$normalizedRequestId → mappedSession=$mappedSessionId | allMappings=${_requestSessionByRequestId.length}',
    );
    if (mappedSessionId != null && mappedSessionId.isNotEmpty) {
      infoLog('[SCOMM-ROUTE] ✓ Using mapped session $mappedSessionId');
      _recordSentPayload(message.encode());
      await _webrtccontroller.sendData(
        sessionId: mappedSessionId,
        channelLabel: ScommDataChannelTransport.mainChannel,
        message: message.encode(),
      );
      return;
    }

    final selectedSessionId = _connectController.selectedSessionId;
    final sessionIds = _connectController.sessionStore.sessionIds;
    final singleActiveSessionId =
        sessionIds.length == 1 ? sessionIds.first : null;
    final fallbackSessionId = selectedSessionId ?? singleActiveSessionId;

    infoLog(
      '[SCOMM-ROUTE] No mapping found → selectedSession=$selectedSessionId singleActive=$singleActiveSessionId fallback=$fallbackSessionId allSessions=${sessionIds.toList()}',
    );

    if (fallbackSessionId == null || fallbackSessionId.isEmpty) {
      infoLog(
        '[SCOMM-ROUTE] ⚠ No session available, falling back to transport.send',
      );
      return _datachannelController.transport.send(message);
    }

    infoLog('[SCOMM-ROUTE] ✓ Using fallback session $fallbackSessionId');
    _recordSentPayload(message.encode());
    await _webrtccontroller.sendData(
      sessionId: fallbackSessionId,
      channelLabel: ScommDataChannelTransport.mainChannel,
      message: message.encode(),
    );
  }

  /// Adds a sent payload byte count to the current one-second speed window.
  void _recordSentPayload(String message) {
    _sentBytesSinceLastTick += utf8.encode(message).length;
  }

  /// Adds a received payload byte count to the current one-second speed window.
  void _recordReceivedPayload(String message) {
    _receivedBytesSinceLastTick += utf8.encode(message).length;
  }

  /// Starts the timer that publishes per-second transfer speed snapshots.
  void _startTransferSpeedTicker() {
    _transferSpeedTimer?.cancel();
    _transferSpeedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _transferSpeed = ScommTransferSpeed(
        sentBytesPerSecond: _sentBytesSinceLastTick,
        receivedBytesPerSecond: _receivedBytesSinceLastTick,
      );
      _sentBytesSinceLastTick = 0;
      _receivedBytesSinceLastTick = 0;

      if (!_transferSpeedController.isClosed) {
        _transferSpeedController.add(_transferSpeed);
      }
    });
  }

  /// Clears transfer speed counters and emits a zero-speed snapshot.
  void _resetTransferSpeed() {
    _sentBytesSinceLastTick = 0;
    _receivedBytesSinceLastTick = 0;
    _transferSpeed = const ScommTransferSpeed();
    if (!_transferSpeedController.isClosed) {
      _transferSpeedController.add(_transferSpeed);
    }
  }

  /// Stores and broadcasts a changed ICE route for the active session.
  void _setIceRoute(WebRtcIceRoute next) {
    if (_iceRoute == next) {
      return;
    }
    _iceRoute = next;
    if (!_iceRouteController.isClosed) {
      _iceRouteController.add(next);
    }
    if (!_stateChangesController.isClosed) {
      _stateChangesController.add(null);
    }
  }
}
