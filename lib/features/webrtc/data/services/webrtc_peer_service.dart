import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../domain/entities/webrtc_connection_state.dart';
import '../../domain/entities/webrtc_data_message.dart';
import '../../domain/entities/webrtc_ice_candidate.dart';
import '../../domain/entities/webrtc_ice_server_config.dart';
import '../../domain/entities/webrtc_session_description.dart';

typedef WebRtcPeerConnectionFactory =
    Future<RTCPeerConnection> Function(Map<String, dynamic> configuration);

class WebRtcPeerService {
  WebRtcPeerService({WebRtcPeerConnectionFactory? peerConnectionFactory})
    : _peerConnectionFactory =
          peerConnectionFactory ??
          ((configuration) => createPeerConnection(configuration));

  static const _maxPendingRemoteIceCandidates = 200;

  final WebRtcPeerConnectionFactory _peerConnectionFactory;

  RTCPeerConnection? _peerConnection;

  RTCPeerConnection? get peerConnection => _peerConnection;
  final Map<String, RTCDataChannel> _dataChannels = {};
  final List<WebRtcIceCandidate> _pendingRemoteIceCandidates = [];

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

    final config = <String, dynamic>{
      'iceServers': _buildIceServers(iceServers),
    };

    final pc = await _peerConnectionFactory(config);
    _peerConnection = pc;

    pc.onConnectionState = (state) {
      _connectionStateController.add(_mapConnectionState(state));
    };

    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _connectionStateController.add(WebRtcConnectionState.failed);
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _connectionStateController.add(WebRtcConnectionState.disconnected);
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _connectionStateController.add(WebRtcConnectionState.closed);
      }
    };

    pc.onIceCandidate = (candidate) {
      final raw = candidate.candidate;
      if (raw == null || raw.isEmpty) return;

      _localIceController.add(
        WebRtcIceCandidate(
          candidate: _candidateToSignal(raw),
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };

    pc.onDataChannel = (channel) {
      _bindDataChannel(channel);
    };

    for (final label in dataChannelLabels) {
      await addDataChannel(label);
    }
  }

  Future<WebRtcSessionDescription> createOffer({
    bool iceRestart = false,
  }) async {
    final pc = _requirePeerConnection();

    if (iceRestart) {
      await pc.restartIce();
    }

    final offer = iceRestart
        ? await pc.createOffer(const {'iceRestart': true})
        : await pc.createOffer();

    await pc.setLocalDescription(offer);

    return WebRtcSessionDescription(
      type: offer.type ?? 'offer',
      sdp: offer.sdp ?? '',
    );
  }

  Future<WebRtcSessionDescription> createAnswerForOffer(
    WebRtcSessionDescription offer,
  ) async {
    final pc = _requirePeerConnection();

    await pc.setRemoteDescription(RTCSessionDescription(offer.sdp, offer.type));
    await _flushPendingRemoteIceCandidates(pc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    return WebRtcSessionDescription(
      type: answer.type ?? 'answer',
      sdp: answer.sdp ?? '',
    );
  }

  Future<void> setRemoteAnswer(WebRtcSessionDescription answer) async {
    final pc = _requirePeerConnection();

    await pc.setRemoteDescription(
      RTCSessionDescription(answer.sdp, answer.type),
    );
    await _flushPendingRemoteIceCandidates(pc);
  }

  Future<void> addRemoteIceCandidate(WebRtcIceCandidate candidate) async {
    final pc = _requirePeerConnection();

    bool hasRemoteDescription;
    try {
      hasRemoteDescription = (await pc.getRemoteDescription()) != null;
    } catch (_) {
      return;
    }

    if (!hasRemoteDescription) {
      if (_pendingRemoteIceCandidates.length >=
          _maxPendingRemoteIceCandidates) {
        _pendingRemoteIceCandidates.removeAt(0);
      }
      _pendingRemoteIceCandidates.add(candidate);
      return;
    }

    await _applyRemoteIceCandidate(pc, candidate);
  }

  Future<void> addDataChannel(String label) async {
    final pc = _requirePeerConnection();

    if (_dataChannels.containsKey(label)) return;

    final channel = await pc.createDataChannel(label, RTCDataChannelInit());
    _bindDataChannel(channel);
  }

  Future<void> removeDataChannel(String label) async {
    final channel = _dataChannels.remove(label);
    if (channel == null) return;
    await channel.close();
  }

  Future<void> sendData({
    required String channelLabel,
    required String message,
  }) async {
    final channel = _dataChannels[channelLabel];
    if (channel == null) {
      final available = _dataChannels.keys.join(', ');
      throw StateError(
        'Data channel "$channelLabel" does not exist. '
        'Available channels: [${available.isEmpty ? 'none' : available}]',
      );
    }

    await channel.send(RTCDataChannelMessage(message));
  }

  Future<void> close() async {
    for (final channel in _dataChannels.values) {
      await channel.close();
    }
    _dataChannels.clear();
    _pendingRemoteIceCandidates.clear();

    final pc = _peerConnection;
    _peerConnection = null;

    if (pc != null) {
      await pc.close();
      await pc.dispose();
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

  RTCPeerConnection _requirePeerConnection() {
    final pc = _peerConnection;
    if (pc == null) {
      throw StateError('PeerConnection is not initialized.');
    }
    return pc;
  }

  List<Map<String, dynamic>> _buildIceServers(
    List<WebRtcIceServerConfig>? input,
  ) {
    if (input != null && input.isNotEmpty) {
      return input
          .map(
            (entry) => <String, dynamic>{
              'urls': entry.urls,
              if (entry.username != null) 'username': entry.username,
              if (entry.credential != null) 'credential': entry.credential,
            },
          )
          .toList(growable: false);
    }

    return const <Map<String, dynamic>>[
      <String, dynamic>{
        'urls': ['stun:stun.l.google.com:19302'],
      },
    ];
  }

  WebRtcConnectionState _mapConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return WebRtcConnectionState.newState;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return WebRtcConnectionState.connecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return WebRtcConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return WebRtcConnectionState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return WebRtcConnectionState.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return WebRtcConnectionState.closed;
    }
  }

  String _candidateToSignal(String rawCandidate) {
    return rawCandidate.startsWith('candidate:')
        ? rawCandidate
        : 'candidate:$rawCandidate';
  }

  RTCIceCandidate _toFlutterCandidate(
    String rawCandidate, {
    String? sdpMid,
    int? sdpMLineIndex,
  }) {
    return RTCIceCandidate(
      _candidateToSignal(rawCandidate),
      sdpMid,
      sdpMLineIndex,
    );
  }

  Future<void> _applyRemoteIceCandidate(
    RTCPeerConnection pc,
    WebRtcIceCandidate candidate,
  ) async {
    await pc.addCandidate(
      _toFlutterCandidate(
        candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      ),
    );
  }

  Future<void> _flushPendingRemoteIceCandidates(RTCPeerConnection pc) async {
    if (_pendingRemoteIceCandidates.isEmpty) return;

    final pending = List<WebRtcIceCandidate>.from(_pendingRemoteIceCandidates);
    _pendingRemoteIceCandidates.clear();

    for (final candidate in pending) {
      await _applyRemoteIceCandidate(pc, candidate);
    }
  }

  void _bindDataChannel(RTCDataChannel channel) {
    final label = channel.label;
    if (label == null) return;

    _dataChannels[label] = channel;

    channel.messageStream.listen((data) {
      final value = data.isBinary
          ? String.fromCharCodes(data.binary)
          : data.text;

      _dataMessageController.add(
        WebRtcDataMessage(channelLabel: label, message: value),
      );
    });
  }
}
