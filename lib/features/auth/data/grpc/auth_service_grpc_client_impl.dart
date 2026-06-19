import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:grpc/grpc.dart';
import 'package:scommconnector/core/logging/log.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/entities/imap_credentials.dart';
import 'generated/auth/auth.pb.dart' as auth_pb;
import 'generated/auth/auth.pbgrpc.dart' as auth_grpc;
import '../models/auth_tokens_model.dart';
import '../models/exchange_external_token_request_model.dart';
import '../models/exchange_imap_credentials_request_model.dart';
import '../models/refresh_access_token_request_model.dart';
import 'auth_service_grpc_client.dart';

class AuthServiceGrpcClientImpl implements AuthServiceGrpcClient {
  final auth_grpc.AuthServiceClient _client;

  AuthServiceGrpcClientImpl({
    required String host,
    required int port,
    bool useTls = false,
  }) : _client = auth_grpc.AuthServiceClient(
          ClientChannel(
            host,
            port: port,
            options: ChannelOptions(
              credentials: useTls
                  ? const ChannelCredentials.secure()
                  : const ChannelCredentials.insecure(),
            ),
          ),
        );

  @override
  Future<AuthTokensModel> exchangeExternalToken(
    ExchangeExternalTokenRequestModel request,
  ) async {
    final response = await _executeWithNetworkGuard(() {
      final grpcRequest = auth_pb.ExchangeExternalTokenRequest(
        provider: request.provider,
        externalAccessToken: request.externalAccessToken,
      );

      return _client.exchangeExternalToken(grpcRequest);
    });
    _ensureSuccess(response, fallback: 'Token exchange failed.');
    return _toAuthTokensModel(response);
  }

  @override
  Future<AuthTokensModel> exchangeImapCredentials(
    ExchangeImapCredentialsRequestModel request,
  ) async {
    final response = await _executeWithNetworkGuard(() {
      final grpcRequest = auth_pb.ExchangeImapCredentialsRequest(
        provider: request.provider,
        imapCredentials: _toGrpcImap(request.imapCredentials),
      );

      return _client.exchangeImapCredentials(grpcRequest);
    });

    _ensureSuccess(response, fallback: 'IMAP credential exchange failed.');
    return _toAuthTokensModel(response);
  }

  @override
  Future<AuthTokensModel> refreshTokens(
    RefreshAccessTokenRequestModel request,
  ) async {
    final response = await _executeWithNetworkGuard(() {
      final grpcRequest = auth_pb.RefreshTokensRequest(
        refreshToken: request.refreshToken,
      );

      return _client.refreshTokens(grpcRequest);
    });

    _ensureSuccess(response, fallback: 'Token refresh failed.');
    return _toAuthTokensModel(response);
  }

  auth_pb.ImapCredentials _toGrpcImap(ImapCredentials credentials) {
    return auth_pb.ImapCredentials(
      username: credentials.username,
      password: credentials.password,
      host: credentials.host,
      port: credentials.port,
      useTls: credentials.useTls,
    );
  }

  void _ensureSuccess(
    auth_pb.AuthTokensResponse response, {
    required String fallback,
  }) {
    if (response.success) {
      return;
    }

    throw ServerException(
      message: response.message.isNotEmpty ? response.message : fallback,
    );
  }

  AuthTokensModel _toAuthTokensModel(auth_pb.AuthTokensResponse response) {
    DateTime? expiresAt;
    if (response.hasExpiresAtEpochSeconds()) {
      final seconds = response.expiresAtEpochSeconds;
      if (seconds != fixnum.Int64.ZERO) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000,
          isUtc: true,
        );
      }
    }

    return AuthTokensModel(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: expiresAt,
    );
  }

  Future<T> _executeWithNetworkGuard<T>(Future<T> Function() action) async {
    try {
      infoLog('Executing gRPC action with network guard...');
      return await action();
    } on GrpcError catch (error) {
      throw _mapGrpcError(error);
    } catch (error) {
      if (error is AppException) {
        rethrow;
      }
      throw const UnknownAppException();
    }
  }

  AppException _mapGrpcError(GrpcError error) {
    switch (error.code) {
      case StatusCode.deadlineExceeded:
        return const RequestTimeoutException();
      case StatusCode.unavailable:
        return const NoConnectionException();
      case StatusCode.unauthenticated:
      case StatusCode.permissionDenied:
        return UnauthorizedException(
          message: error.message ?? 'You are not authorized.',
        );
      case StatusCode.internal:
      case StatusCode.unknown:
      case StatusCode.aborted:
      case StatusCode.resourceExhausted:
        return ServerException(
          message: error.message ?? 'Server error. Please try again later.',
        );
      default:
        return UnknownAppException(
          message: error.message ?? 'Something went wrong. Please try again.',
        );
    }
  }
}
