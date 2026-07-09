import 'package:scommconnector/features/auth/auth.dart';
import 'package:scommconnector/features/identity/identity.dart';
import 'package:scommconnector/features/signaling/signaling.dart';
import 'package:scommconnector/features/webrtc/webrtc.dart';
import 'package:equatable/equatable.dart';

class ScommSessionState extends Equatable {
  final bool isAuthenticated;
  final bool isDeviceRegistered;
  final AuthState authState;
  final IdentityState identityState;
  final SignalingState signalingState;
  final WebRtcState webRtcState;
  final String? activeRemoteUri;
  final List<String> connectedRemoteUris;
  final List<String> connectingRemoteUris;

  const ScommSessionState({
    required this.isAuthenticated,
    required this.isDeviceRegistered,
    required this.authState,
    required this.identityState,
    required this.signalingState,
    required this.webRtcState,
    this.activeRemoteUri,
    this.connectedRemoteUris = const <String>[],
    this.connectingRemoteUris = const <String>[],
  });

  bool get canStartRealtime => isAuthenticated && isDeviceRegistered;
  int get connectedDeviceCount => connectedRemoteUris.length;

  ScommSessionState copyWith({
    bool? isAuthenticated,
    bool? isDeviceRegistered,
    AuthState? authState,
    IdentityState? identityState,
    SignalingState? signalingState,
    WebRtcState? webRtcState,
    String? activeRemoteUri,
    List<String>? connectedRemoteUris,
    List<String>? connectingRemoteUris,
    bool clearActiveRemoteUri = false,
  }) {
    return ScommSessionState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isDeviceRegistered: isDeviceRegistered ?? this.isDeviceRegistered,
      authState: authState ?? this.authState,
      identityState: identityState ?? this.identityState,
      signalingState: signalingState ?? this.signalingState,
      webRtcState: webRtcState ?? this.webRtcState,
      activeRemoteUri: clearActiveRemoteUri
          ? null
          : (activeRemoteUri ?? this.activeRemoteUri),
      connectedRemoteUris:
          connectedRemoteUris ?? List<String>.from(this.connectedRemoteUris),
      connectingRemoteUris:
          connectingRemoteUris ?? List<String>.from(this.connectingRemoteUris),
    );
  }

  factory ScommSessionState.initial() {
    return ScommSessionState(
      isAuthenticated: false,
      isDeviceRegistered: false,
      authState: AuthState.initial(),
      identityState: IdentityState.initial(),
      signalingState: SignalingState.initial(),
      webRtcState: WebRtcState.initial(),
      activeRemoteUri: null,
      connectedRemoteUris: const <String>[],
      connectingRemoteUris: const <String>[],
    );
  }


  Map<String, dynamic> toJson() {
    return {
      'isAuthenticated': isAuthenticated,
      'isDeviceRegistered': isDeviceRegistered,
      'authState': authState.toJson(),
      'identityState': identityState.toJson(),
      'signalingState': signalingState.toJson(),
      'webRtcState': webRtcState.toJson(),
      'activeRemoteUri': activeRemoteUri,
      'connectedRemoteUris': connectedRemoteUris,
      'connectingRemoteUris': connectingRemoteUris,
    };
  }

  factory ScommSessionState.fromJson(Map<String, dynamic> json) {
    return ScommSessionState(
      isAuthenticated: json['isAuthenticated'] as bool,
      isDeviceRegistered: json['isDeviceRegistered'] as bool,
      authState: AuthState.fromJson(json['authState'] as Map<String, dynamic>),
      identityState:
          IdentityState.fromJson(json['identityState'] as Map<String, dynamic>),
      signalingState:
          SignalingState.fromJson(json['signalingState'] as Map<String, dynamic>),
      webRtcState:
          WebRtcState.fromJson(json['webRtcState'] as Map<String, dynamic>),
        activeRemoteUri: json['activeRemoteUri'] as String?,
      connectedRemoteUris: (json['connectedRemoteUris'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      connectingRemoteUris: (json['connectingRemoteUris'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
    );
  }

  @override
  List<Object?> get props => [
        isAuthenticated,
        isDeviceRegistered,
        authState,
        identityState,
        signalingState,
        webRtcState,
        activeRemoteUri,
        connectedRemoteUris,
        connectingRemoteUris,
      ];
}