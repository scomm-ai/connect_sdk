import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scommconnector/core/auth/signaling_access_token_provider.dart';
import 'package:scommconnector/core/di/feature/auth_di.dart';
import 'package:scommconnector/core/di/feature/connect_di.dart';
import 'package:scommconnector/core/di/feature/identity_id.dart';
import 'package:scommconnector/core/di/feature/signaling_di.dart';
import 'package:scommconnector/core/di/feature/webrtc_di.dart';
import 'package:scommconnector/core/di/scomm_service_builder.dart';
import 'package:scommconnector/core/logging/log.dart';
import 'package:scommconnector/features/auth/application/controllers/auth_controller.dart';
import 'package:scommconnector/features/connect/connect_controller.dart';
import 'package:scommconnector/features/identity/identity.dart';
import 'package:scommconnector/features/signaling/signaling.dart';
import 'package:scommconnector/features/webrtc/webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

final scommDi = ScommServiceBuilder();

Future<void> setupDependencies({
  required String host,
  required int port,
  bool useTls = false,
}) async {
  if (!scommDi.isRegistered<SharedPreferences>()) {
    final prefs = await SharedPreferences.getInstance();
    scommDi.registerLazySingleton<SharedPreferences>(() => prefs);
  }
  if (!scommDi.isRegistered<FlutterSecureStorage>()) {
    final secureStorage = FlutterSecureStorage();
    scommDi.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);
  }

  infoLog('Setting up Scomm Connector dependencies...');

  if (!scommDi.isRegistered<AuthSessionState>()) {
    scommDi.registerLazySingleton<AuthSessionState>(AuthSessionState.new);
  }

  if (!scommDi.isRegistered<ScommAuthController>()) {
    await authDI(scommDi);
  }

  infoLog('Auth DI setup complete');

  if (!scommDi.isRegistered<IdentityController>()) {
    await identityDI(scommDi, host, port, useTls);
  }

  infoLog('Identity DI setup complete');

  if (!scommDi.isRegistered<SignalingController>()) {
    await signalingDI(scommDi, host, port, useTls);
  }

  infoLog('Signaling DI setup complete');

  if (!scommDi.isRegistered<WebRtcController>()) {
    await webrtcDI(scommDi);
  }

  infoLog('WebRTC DI setup complete');

  if (!scommDi.isRegistered<ConnectController>()) {
    await connectDI(scommDi);
  }

  infoLog('Connect DI setup complete');
}

/// Registers a host-provided token source (typically AppAuth).
void registerSignalingAccessTokenProvider(SignalingAccessTokenProvider provider) {
  if (scommDi.isRegistered<SignalingAccessTokenProvider>()) {
    scommDi.unregister<SignalingAccessTokenProvider>();
  }
  scommDi.registerLazySingleton<SignalingAccessTokenProvider>(() => provider);
}

/// Registers optional refresh hook used on gRPC auth failures.
void registerSignalingAccessTokenRefresher(SignalingAccessTokenRefresher refresher) {
  if (scommDi.isRegistered<SignalingAccessTokenRefresher>()) {
    scommDi.unregister<SignalingAccessTokenRefresher>();
  }
  scommDi.registerLazySingleton<SignalingAccessTokenRefresher>(() => refresher);
}

Future<String?> resolveSignalingAccessToken() async {
  if (scommDi.isRegistered<SignalingAccessTokenProvider>()) {
    try {
      final token = await scommDi<SignalingAccessTokenProvider>().getAccessToken();
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }
    } catch (_) {}
  }

  return scommDi<AuthSessionState>().tokenOrNull;
}

class AuthSessionState {
  String _accessToken = '';
  String _userId = '';

  String get accessToken => _accessToken;
  String? get tokenOrNull =>
      _accessToken.trim().isEmpty ? null : _accessToken.trim();
  String? get userIdOrNull => _userId.trim().isEmpty ? null : _userId.trim();

  void setAccessToken(String token) {
    _accessToken = token;
  }

  void setSession({required String accessToken, required String userId}) {
    _accessToken = accessToken;
    _userId = userId;
  }

  void clear() {
    _accessToken = '';
    _userId = '';
  }
}
