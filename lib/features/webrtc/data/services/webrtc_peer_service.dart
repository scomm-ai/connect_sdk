import 'dart:async';

import '../../domain/entities/webrtc_connection_state.dart';
import '../../domain/entities/webrtc_data_message.dart';
import '../../domain/entities/webrtc_ice_candidate.dart';
import '../../domain/entities/webrtc_ice_server_config.dart';
import '../../domain/entities/webrtc_session_description.dart';
import '../native/libdatachannel_peer_connection.dart';

class WebRtcPeerService {
  WebRtcPeerService();

  static const _maxPendingRemoteIceCandidates = 200;

  LibDataChannelPeerConnection? _peerConnection;

  LibDataChannelPeerConnection? get peerConnection => _peerConnection;

  final List<WebRtcIceCandidate> _pendingRemoteIceCandidates = [];

  StreamSubscription<WebRtcConnectionState>? _connectionSub;
  StreamSubscription<WebRtcIceCandidate>? _iceSub;
  StreamSubscription<WebRtcDataMessage>? _dataSub;

  final _connectionStateController =
      StreamController<WebRtcConnectionState>.broadcast();
  final _localIceController = StreamController<WebRtcIceCandidate>.broadcast();
  final _dataMessageController =
      StreamController<WebRtcDataMessage>.broadcast();

  Stream<WebRtcConnectionState> get connectionStates =>
      _connectionStateController.stream;
  Stream<WebRtcIceCandidate> get localIceCandidates =>
      _localIceController.stream;
  Stream<WebRtcDataMessage> get dataMessages => _dataMessageController.stream;

  Future<void> initialize({
    required List<String> dataChannelLabels,
    List<WebRtcIceServerConfig>? iceServers,
  }) async {
    await close();

    final pc = await LibDataChannelPeerConnection.create(
      iceServers: iceServers,
    );
    _peerConnection = pc;

    _connectionSub = pc.connectionStates.listen(_connectionStateController.add);
    _iceSub = pc.localIceCandidates.listen(_localIceController.add);
    _dataSub = pc.dataMessages.listen(_dataMessageController.add);

    for (final label in dataChannelLabels) {
      await addDataChannel(label);
    }
  }

  Future<WebRtcSessionDescription> createOffer({
    bool iceRestart = false,
  }) async {
    final pc = _requirePeerConnection();
    return pc.createOffer(iceRestart: iceRestart);
  }

  Future<WebRtcSessionDescription> createAnswerForOffer(
    WebRtcSessionDescription offer,
  ) async {
    final pc = _requirePeerConnection();
    final answer = await pc.createAnswerForOffer(offer);
    await _flushPendingRemoteIceCandidates(pc);
    return answer;
  }

  Future<void> setRemoteAnswer(WebRtcSessionDescription answer) async {
    final pc = _requirePeerConnection();
    await pc.setRemoteAnswer(answer);
    await _flushPendingRemoteIceCandidates(pc);
  }

  Future<void> addRemoteIceCandidate(WebRtcIceCandidate candidate) async {
    final pc = _requirePeerConnection();

    if (!pc.hasRemoteDescription) {
      if (_pendingRemoteIceCandidates.length >=
          _maxPendingRemoteIceCandidates) {
        _pendingRemoteIceCandidates.removeAt(0);
      }
      _pendingRemoteIceCandidates.add(candidate);
      return;
    }

    await pc.addRemoteIceCandidate(candidate);
  }

  Future<void> addDataChannel(String label) async {
    await _requirePeerConnection().addDataChannel(label);
  }

  Future<void> removeDataChannel(String label) async {
    await _requirePeerConnection().removeDataChannel(label);
  }

  Future<void> sendData({
    required String channelLabel,
    required String message,
  }) async {
    await _requirePeerConnection().sendData(
      channelLabel: channelLabel,
      message: message,
    );
  }

  Future<void> close() async {
    await _connectionSub?.cancel();
    await _iceSub?.cancel();
    await _dataSub?.cancel();
    _connectionSub = null;
    _iceSub = null;
    _dataSub = null;

    _pendingRemoteIceCandidates.clear();

    final pc = _peerConnection;
    _peerConnection = null;

    if (pc != null) {
      await pc.close();
    }

    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(WebRtcConnectionState.closed);
    }
  }

  Future<void> dispose() async {
    await close();
    await _connectionStateController.close();
    await _localIceController.close();
    await _dataMessageController.close();
  }

  LibDataChannelPeerConnection _requirePeerConnection() {
    final pc = _peerConnection;
    if (pc == null) {
      throw StateError('PeerConnection is not initialized.');
    }
    return pc;
  }

  Future<void> _flushPendingRemoteIceCandidates(
    LibDataChannelPeerConnection pc,
  ) async {
    if (_pendingRemoteIceCandidates.isEmpty) return;

    final pending = List<WebRtcIceCandidate>.from(_pendingRemoteIceCandidates);
    _pendingRemoteIceCandidates.clear();

    for (final candidate in pending) {
      await pc.addRemoteIceCandidate(candidate);
    }
  }
}
