import 'dart:async';

import 'package:scommconnector/core/auth/jwt_sub_reader.dart';
import 'package:scommconnector/core/auth/signaling_access_token_provider.dart';
import 'package:scommconnector/core/di/service_locator.dart';
import 'package:scommconnector/core/logging/log.dart';

import '../state/auth_state.dart';

class ScommAuthController {
  static final ScommAuthController _instance = ScommAuthController._internal();

  AuthState _state = AuthState.initial();

  factory ScommAuthController() => _instance;

  ScommAuthController._internal();

  final _authStateStream = StreamController<AuthState>.broadcast();
  Stream<AuthState> get authStates => _authStateStream.stream;

  void _notify(AuthState newState) {
    _state = newState;
    _authStateStream.add(_state);
  }

  AuthState get state => _state;

  Future<void> setAccessToken(String token, {String? userId}) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError('Access token must not be empty');
    }

    final resolvedUserId = normalizeSignalingUserId(
      userId ?? readJwtSub(trimmedToken) ?? '',
    );
    if (resolvedUserId.isEmpty) {
      throw ArgumentError('Unable to resolve user id from access token');
    }

    scommDi<AuthSessionState>().setSession(
      accessToken: trimmedToken,
      userId: resolvedUserId,
    );

    _notify(
      _state.copyWith(
        isLoading: false,
        isLoggedIn: true,
        error: null,
        email: resolvedUserId,
        clearError: true,
      ),
    );
  }

  Future<void> logout() async {
    _notify(const AuthState.unauthenticated());
    scommDi<AuthSessionState>().clear();
  }

  Future<void> init() async {
    infoLog('Initializing Scomm auth session from token provider...');

    if (scommDi.isRegistered<SignalingAccessTokenProvider>()) {
      try {
        final token =
            await scommDi<SignalingAccessTokenProvider>().getAccessToken();
        if (token != null && token.trim().isNotEmpty) {
          await setAccessToken(token);
          return;
        }
      } catch (error) {
        infoLog('Token provider init failed: $error');
      }
    }

    final session = scommDi<AuthSessionState>();
    final existingToken = session.tokenOrNull;
    final existingUserId = session.userIdOrNull;
    if (existingToken != null &&
        existingToken.isNotEmpty &&
        existingUserId != null &&
        existingUserId.isNotEmpty) {
      _notify(
        _state.copyWith(
          isLoading: false,
          isLoggedIn: true,
          error: null,
          email: existingUserId,
          clearError: true,
        ),
      );
      return;
    }

    _notify(
      _state.copyWith(
        isLoading: false,
        isLoggedIn: false,
        error: null,
        clearError: true,
      ),
    );
  }

  /// Attempts to refresh the access token via [SignalingAccessTokenRefresher]
  /// when registered, then updates local session state.
  Future<bool> refreshSessionToken() async {
    if (!scommDi.isRegistered<SignalingAccessTokenRefresher>()) {
      return false;
    }

    try {
      final token =
          await scommDi<SignalingAccessTokenRefresher>().refreshAccessToken();
      if (token == null || token.trim().isEmpty) {
        return false;
      }
      await setAccessToken(token);
      return true;
    } catch (error) {
      infoLog('Session token refresh failed: $error');
      return false;
    }
  }
}
