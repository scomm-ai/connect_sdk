import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/entities/webrtc_connection_state.dart';
import '../../domain/entities/webrtc_data_message.dart';
import '../../domain/entities/webrtc_ice_candidate.dart';
import '../../domain/entities/webrtc_ice_server_config.dart';
import '../../domain/entities/webrtc_session_description.dart';
import 'libdatachannel_bindings.dart';
import 'libdatachannel_library.dart';

/// High-level Dart wrapper around a libdatachannel PeerConnection.
class LibDataChannelPeerConnection {
  LibDataChannelPeerConnection._({
    required this.pcId,
    required LibDataChannelBindings bindings,
  }) : _bindings = bindings;

  final int pcId;
  final LibDataChannelBindings _bindings;

  final Map<String, int> _dataChannels = {};
  final List<_NativeCallbackHandle> _callbackHandles = [];

  final _connectionStateController =
      StreamController<WebRtcConnectionState>.broadcast();
  final _localIceController = StreamController<WebRtcIceCandidate>.broadcast();
  final _dataMessageController =
      StreamController<WebRtcDataMessage>.broadcast();

  Completer<WebRtcSessionDescription>? _localDescriptionCompleter;
  bool _hasRemoteDescription = false;
  bool _closed = false;

  Stream<WebRtcConnectionState> get connectionStates =>
      _connectionStateController.stream;
  Stream<WebRtcIceCandidate> get localIceCandidates =>
      _localIceController.stream;
  Stream<WebRtcDataMessage> get dataMessages => _dataMessageController.stream;

  bool get hasRemoteDescription => _hasRemoteDescription;
  Map<String, int> get dataChannelIds => Map.unmodifiable(_dataChannels);

  static Future<LibDataChannelPeerConnection> create({
    List<WebRtcIceServerConfig>? iceServers,
  }) async {
    final library = LibDataChannelLibrary.instance();
    final bindings = library.bindings;

    final iceUris = _buildIceServerUris(iceServers);
    final icePointers = <Pointer<Utf8>>[];

    final config = calloc<RtcConfigurationNative>();
    Pointer<Pointer<Utf8>>? iceArray;
    try {
      if (iceUris.isNotEmpty) {
        iceArray = calloc<Pointer<Utf8>>(iceUris.length);
        for (var i = 0; i < iceUris.length; i++) {
          final ptr = iceUris[i].toNativeUtf8();
          icePointers.add(ptr);
          iceArray[i] = ptr;
        }
        config.ref.iceServers = iceArray;
        config.ref.iceServersCount = iceUris.length;
      } else {
        config.ref.iceServers = nullptr;
        config.ref.iceServersCount = 0;
      }

      config.ref.proxyServer = nullptr;
      config.ref.bindAddress = nullptr;
      config.ref.certificateType = 0;
      config.ref.certificatePemFile = nullptr;
      config.ref.keyPemFile = nullptr;
      config.ref.keyPemPass = nullptr;
      config.ref.iceTransportPolicy = 0;
      config.ref.enableIceTcp = false;
      config.ref.enableIceUdpMux = false;
      // Manual offer/answer to match the existing scommconnector flow.
      config.ref.disableAutoNegotiation = true;
      config.ref.forceMediaTransport = false;
      config.ref.portRangeBegin = 0;
      config.ref.portRangeEnd = 0;
      config.ref.mtu = 0;
      config.ref.maxMessageSize = 0;

      final pcId = bindings.rtcCreatePeerConnection(config);
      if (pcId < 0) {
        throw StateError('rtcCreatePeerConnection failed: $pcId');
      }

      final peer = LibDataChannelPeerConnection._(
        pcId: pcId,
        bindings: bindings,
      );
      peer._installCallbacks();
      return peer;
    } finally {
      for (final ptr in icePointers) {
        malloc.free(ptr);
      }
      if (iceArray != null) {
        calloc.free(iceArray);
      }
      calloc.free(config);
    }
  }

  void _installCallbacks() {
    final stateCb =
        NativeCallable<RtcStateChangeCallbackNative>.listener((
          int pc,
          int state,
          Pointer<Void> ptr,
        ) {
          if (_closed) return;
          _connectionStateController.add(_mapState(state));
        });
    _callbackHandles.add(_NativeCallbackHandle(stateCb));
    _check(
      _bindings.rtcSetStateChangeCallback(pcId, stateCb.nativeFunction),
      'rtcSetStateChangeCallback',
    );

    final iceCb =
        NativeCallable<RtcIceStateChangeCallbackNative>.listener((
          int pc,
          int state,
          Pointer<Void> ptr,
        ) {
          if (_closed) return;
          if (state == RtcIceState.failed) {
            _connectionStateController.add(WebRtcConnectionState.failed);
          } else if (state == RtcIceState.disconnected) {
            _connectionStateController.add(WebRtcConnectionState.disconnected);
          } else if (state == RtcIceState.closed) {
            _connectionStateController.add(WebRtcConnectionState.closed);
          }
        });
    _callbackHandles.add(_NativeCallbackHandle(iceCb));
    _check(
      _bindings.rtcSetIceStateChangeCallback(pcId, iceCb.nativeFunction),
      'rtcSetIceStateChangeCallback',
    );

    final descCb =
        NativeCallable<RtcDescriptionCallbackNative>.listener((
          int pc,
          Pointer<Utf8> sdp,
          Pointer<Utf8> type,
          Pointer<Void> ptr,
        ) {
          if (_closed) return;
          final completer = _localDescriptionCompleter;
          if (completer == null || completer.isCompleted) return;
          completer.complete(
            WebRtcSessionDescription(
              type: type == nullptr ? 'offer' : type.toDartString(),
              sdp: sdp == nullptr ? '' : sdp.toDartString(),
            ),
          );
        });
    _callbackHandles.add(_NativeCallbackHandle(descCb));
    _check(
      _bindings.rtcSetLocalDescriptionCallback(pcId, descCb.nativeFunction),
      'rtcSetLocalDescriptionCallback',
    );

    final candCb =
        NativeCallable<RtcCandidateCallbackNative>.listener((
          int pc,
          Pointer<Utf8> cand,
          Pointer<Utf8> mid,
          Pointer<Void> ptr,
        ) {
          if (_closed || cand == nullptr) return;
          final raw = cand.toDartString();
          if (raw.isEmpty) return;
          _localIceController.add(
            WebRtcIceCandidate(
              candidate: _candidateToSignal(raw),
              sdpMid: mid == nullptr ? null : mid.toDartString(),
              sdpMLineIndex: 0,
            ),
          );
        });
    _callbackHandles.add(_NativeCallbackHandle(candCb));
    _check(
      _bindings.rtcSetLocalCandidateCallback(pcId, candCb.nativeFunction),
      'rtcSetLocalCandidateCallback',
    );

    final dcCb =
        NativeCallable<RtcDataChannelCallbackNative>.listener((
          int pc,
          int dc,
          Pointer<Void> ptr,
        ) {
          if (_closed) return;
          _bindDataChannel(dc);
        });
    _callbackHandles.add(_NativeCallbackHandle(dcCb));
    _check(
      _bindings.rtcSetDataChannelCallback(pcId, dcCb.nativeFunction),
      'rtcSetDataChannelCallback',
    );
  }

  Future<WebRtcSessionDescription> createOffer({bool iceRestart = false}) async {
    // libdatachannel C API has no restartIce; a fresh local description is the
    // closest equivalent for trickle-ICE renegotiation.
    return _setLocalDescription(type: 'offer');
  }

  Future<WebRtcSessionDescription> createAnswerForOffer(
    WebRtcSessionDescription offer,
  ) async {
    await setRemoteDescription(offer);
    return _setLocalDescription(type: 'answer');
  }

  Future<void> setRemoteAnswer(WebRtcSessionDescription answer) {
    return setRemoteDescription(answer);
  }

  Future<void> setRemoteDescription(WebRtcSessionDescription description) async {
    final sdpPtr = description.sdp.toNativeUtf8();
    final typePtr = description.type.toNativeUtf8();
    try {
      _check(
        _bindings.rtcSetRemoteDescription(pcId, sdpPtr, typePtr),
        'rtcSetRemoteDescription',
      );
      _hasRemoteDescription = true;
    } finally {
      malloc.free(sdpPtr);
      malloc.free(typePtr);
    }
  }

  Future<WebRtcSessionDescription> _setLocalDescription({
    required String type,
  }) async {
    final completer = Completer<WebRtcSessionDescription>();
    _localDescriptionCompleter = completer;

    final typePtr = type.toNativeUtf8();
    try {
      _check(
        _bindings.rtcSetLocalDescription(pcId, typePtr),
        'rtcSetLocalDescription',
      );
    } finally {
      malloc.free(typePtr);
    }

    // Callback is often synchronous; also fall back to reading the SDP.
    if (!completer.isCompleted) {
      final local = _readLocalDescription();
      if (local != null) {
        completer.complete(local);
      }
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        final local = _readLocalDescription();
        if (local != null) return local;
        throw TimeoutException('Timed out waiting for local $type description');
      },
    );
  }

  WebRtcSessionDescription? _readLocalDescription() {
    final sdp = _readStringBuffer(
      (buffer, size) => _bindings.rtcGetLocalDescription(pcId, buffer, size),
    );
    if (sdp == null || sdp.isEmpty) return null;

    final type =
        _readStringBuffer(
          (buffer, size) =>
              _bindings.rtcGetLocalDescriptionType(pcId, buffer, size),
        ) ??
        'offer';

    return WebRtcSessionDescription(type: type, sdp: sdp);
  }

  Future<void> addRemoteIceCandidate(WebRtcIceCandidate candidate) async {
    final candPtr = _candidateToSignal(candidate.candidate).toNativeUtf8();
    final midPtr = (candidate.sdpMid ?? '').toNativeUtf8();
    try {
      _check(
        _bindings.rtcAddRemoteCandidate(
          pcId,
          candPtr,
          candidate.sdpMid == null ? nullptr : midPtr,
        ),
        'rtcAddRemoteCandidate',
      );
    } finally {
      malloc.free(candPtr);
      malloc.free(midPtr);
    }
  }

  Future<void> addDataChannel(String label) async {
    if (_dataChannels.containsKey(label)) return;

    final labelPtr = label.toNativeUtf8();
    try {
      final dc = _bindings.rtcCreateDataChannel(pcId, labelPtr);
      if (dc < 0) {
        throw StateError('rtcCreateDataChannel("$label") failed: $dc');
      }
      _bindDataChannel(dc, preferredLabel: label);
    } finally {
      malloc.free(labelPtr);
    }
  }

  Future<void> removeDataChannel(String label) async {
    final dc = _dataChannels.remove(label);
    if (dc == null) return;
    _bindings.rtcClose(dc);
    _bindings.rtcDeleteDataChannel(dc);
  }

  Future<void> sendData({
    required String channelLabel,
    required String message,
  }) async {
    final dc = _dataChannels[channelLabel];
    if (dc == null) {
      final available = _dataChannels.keys.join(', ');
      throw StateError(
        'Data channel "$channelLabel" does not exist. '
        'Available channels: [${available.isEmpty ? 'none' : available}]',
      );
    }

    final dataPtr = message.toNativeUtf8();
    try {
      // Negative size => null-terminated UTF-8 string.
      _check(
        _bindings.rtcSendMessage(dc, dataPtr, -1),
        'rtcSendMessage',
      );
    } finally {
      malloc.free(dataPtr);
    }
  }

  /// Returns the selected ICE candidate pair strings, if available.
  ({String local, String remote})? selectedCandidatePair() {
    final needed = _bindings.rtcGetSelectedCandidatePair(
      pcId,
      nullptr,
      0,
      nullptr,
      0,
    );
    if (needed <= 0) return null;

    final localPtr = calloc<Uint8>(needed).cast<Utf8>();
    final remotePtr = calloc<Uint8>(needed).cast<Utf8>();
    try {
      final result = _bindings.rtcGetSelectedCandidatePair(
        pcId,
        localPtr,
        needed,
        remotePtr,
        needed,
      );
      if (result < 0) return null;
      return (local: localPtr.toDartString(), remote: remotePtr.toDartString());
    } finally {
      calloc.free(localPtr);
      calloc.free(remotePtr);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    for (final dc in _dataChannels.values) {
      _bindings.rtcClose(dc);
      _bindings.rtcDeleteDataChannel(dc);
    }
    _dataChannels.clear();

    _bindings.rtcClosePeerConnection(pcId);
    _bindings.rtcDeletePeerConnection(pcId);

    for (final handle in _callbackHandles) {
      handle.close();
    }
    _callbackHandles.clear();

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

  void _bindDataChannel(int dc, {String? preferredLabel}) {
    final label =
        preferredLabel ??
        _readStringBuffer(
          (buffer, size) => _bindings.rtcGetDataChannelLabel(dc, buffer, size),
        );
    if (label == null || label.isEmpty) return;

    _dataChannels[label] = dc;

    final messageCb =
        NativeCallable<RtcMessageCallbackNative>.listener((
          int id,
          Pointer<Utf8> message,
          int size,
          Pointer<Void> ptr,
        ) {
          if (_closed || message == nullptr) return;

          late final String value;
          if (size >= 0) {
            final bytes = message.cast<Uint8>().asTypedList(size);
            value = utf8.decode(Uint8List.fromList(bytes), allowMalformed: true);
          } else {
            // Negative size includes the terminating NUL.
            value = message.toDartString();
          }

          _dataMessageController.add(
            WebRtcDataMessage(channelLabel: label, message: value),
          );
        });
    _callbackHandles.add(_NativeCallbackHandle(messageCb));
    _bindings.rtcSetMessageCallback(dc, messageCb.nativeFunction);
  }

  static List<String> _buildIceServerUris(
    List<WebRtcIceServerConfig>? input,
  ) {
    if (input == null || input.isEmpty) {
      return const ['stun:stun.l.google.com:19302'];
    }

    final uris = <String>[];
    for (final server in input) {
      for (final url in server.urls) {
        final username = server.username;
        final credential = server.credential;
        if (username != null &&
            username.isNotEmpty &&
            credential != null &&
            credential.isNotEmpty &&
            (url.startsWith('turn:') || url.startsWith('turns:'))) {
          // libdatachannel expects: user:pass@turn:host:port
          final withoutScheme = url.replaceFirst(RegExp(r'^turns?:'), '');
          final scheme = url.startsWith('turns:') ? 'turns' : 'turn';
          uris.add(
            '${Uri.encodeComponent(username)}:'
            '${Uri.encodeComponent(credential)}'
            '@$scheme:$withoutScheme',
          );
        } else {
          uris.add(url);
        }
      }
    }
    return uris;
  }

  String? _readStringBuffer(
    int Function(Pointer<Utf8> buffer, int size) reader,
  ) {
    final needed = reader(nullptr, 0);
    if (needed <= 0) return null;
    final buffer = calloc<Uint8>(needed).cast<Utf8>();
    try {
      final result = reader(buffer, needed);
      if (result < 0) return null;
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  void _check(int code, String op) {
    if (code < 0) {
      throw StateError('$op failed with code $code');
    }
  }

  String _candidateToSignal(String rawCandidate) {
    return rawCandidate.startsWith('candidate:')
        ? rawCandidate
        : 'candidate:$rawCandidate';
  }

  WebRtcConnectionState _mapState(int state) {
    switch (state) {
      case RtcState.newState:
        return WebRtcConnectionState.newState;
      case RtcState.connecting:
        return WebRtcConnectionState.connecting;
      case RtcState.connected:
        return WebRtcConnectionState.connected;
      case RtcState.disconnected:
        return WebRtcConnectionState.disconnected;
      case RtcState.failed:
        return WebRtcConnectionState.failed;
      case RtcState.closed:
        return WebRtcConnectionState.closed;
      default:
        return WebRtcConnectionState.newState;
    }
  }
}

class _NativeCallbackHandle {
  _NativeCallbackHandle(NativeCallable<dynamic> callable)
    : _close = callable.close;

  final void Function() _close;

  void close() => _close();
}
