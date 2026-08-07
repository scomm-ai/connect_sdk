import 'package:scommconnector/core/config/grpc_client.dart';
import 'package:scommconnector/core/di/service_locator.dart';
import 'package:scommconnector/core/di/scomm_service_builder.dart';
import 'package:scommconnector/core/resilience/online_aware_resilience.dart';
import 'package:scommconnector/features/signaling/domain/usecases/watch_connection_status_usecase.dart';
import 'package:scommconnector/features/signaling/domain/usecases/watch_signaling_messages_uscase.dart';
import 'package:scommconnector/features/signaling/signaling.dart';

Future<void> signalingDI(
  ScommServiceBuilder sl,
  String host,
  int port,
  bool useTls,
) async {
  final client = createGrpcClient(host, port, useTls: useTls);

  sl.registerLazySingleton<SignalingServiceGrpcClient>(
    () => SignalingServiceGrpcClientImpl(
      client,
      resolveSignalingAccessToken,
    ),
  );

  sl.registerLazySingleton<SignalingRepository>(
    () => SignalingRepositoryImpl(
      grpcClient: sl(),
    ),
  );

  sl.registerLazySingleton(() => ConnectSignalingUseCase(sl()));
  sl.registerLazySingleton(() => WatchConnectionStatusUseCase(sl()));
  sl.registerLazySingleton(() => WatchSignalingMessagesUseCase(sl()));
  sl.registerLazySingleton(() => DisconnectSignalingUseCase(sl()));
  sl.registerLazySingleton(() => SendSignalEnvelopeUseCase(sl()));
  sl.registerLazySingleton(() => WatchPresenceUseCase(sl()));

  sl.registerLazySingleton<IOnlineAwareResilience>(
    OnlineAwareResilience.new,
  );

  sl.registerLazySingleton<ISignalingErrorClassifier>(
    SignalingErrorClassifier.new,
  );

  sl.registerLazySingleton<IRequestMatcher>(RequestMatcher.new);

  sl.registerLazySingleton<IConnectionHealthMonitor>(
    ConnectionHealthMonitor.new,
  );

  sl.registerLazySingleton<SignalingController>(
    () => SignalingController(
      connectSignalingUseCase: sl(),
      disconnectSignalingUseCase: sl(),
      watchSignalingMessagesUseCase: sl(),
      watchConnectionStatusUseCase: sl(),
      sendSignalEnvelopeUseCase: sl(),
      watchPresenceUseCase: sl(),
      healthMonitor: sl(),
      errorClassifier: sl(),
      onlineAwareness: sl(),
      requestMatcher: sl(),
    ),
  );
}
