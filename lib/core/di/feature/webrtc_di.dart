import 'package:scommconnector/core/di/scomm_service_builder.dart';
import 'package:scommconnector/features/webrtc/application/webrtc_manager.dart';
import 'package:scommconnector/features/webrtc/data/services/webrtc_ice_route_monitor.dart';
import 'package:scommconnector/features/webrtc/data/services/webrtc_ice_route_stats_parser.dart';
import 'package:scommconnector/features/webrtc/domain/usecases/connection_state_usecase.dart';
import 'package:scommconnector/features/webrtc/webrtc.dart';

Future<void> webrtcDI(ScommServiceBuilder sl) async {
  /// Stateless shared service
  sl.registerLazySingleton<WebRtcIceRouteStatsParser>(
    WebRtcIceRouteStatsParser.new,
  );

  /// Per-session services
  sl.registerFactory<WebRtcPeerService>(
    WebRtcPeerService.new,
  );

  sl.registerFactory<WebRtcIceRouteMonitor>(
    () => WebRtcIceRouteMonitor(sl()),
  );

  sl.registerFactory<WebRtcRepository>(
    () => WebRtcRepositoryImpl(
      peerService: sl<WebRtcPeerService>(),
      iceRouteMonitor: sl<WebRtcIceRouteMonitor>(),
    ),
  );

  /// Session manager
  sl.registerLazySingleton<WebRtcSessionManager>(
    () => WebRtcSessionManager(
      createRepository: () => sl<WebRtcRepository>(),
    ),
  );

  /// Use cases
  sl.registerLazySingleton(
    () => InitializeWebRtcUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => CreateWebRtcOfferUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => CreateWebRtcAnswerUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => SetRemoteAnswerUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => AddRemoteIceCandidateUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => AddDataChannelUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => RemoveDataChannelUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => SendWebRtcDataUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => ConnectionStateUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => CloseWebRtcUseCase(sl()),
  );
  sl.registerLazySingleton(
    () => RestartIceAndCreateOfferUseCase(sl()),
  );

  /// Domain services
  sl.registerLazySingleton<IConnectionRecoveryStrategy>(
    () => ConnectionRecoveryStrategy(
      restartIceAndCreateOfferUseCase: sl(),
      closeWebRtcUseCase: sl(),
    ),
  );

  /// Controller
  sl.registerLazySingleton<WebRtcController>(
    () => WebRtcController(
      sessionManager: sl<WebRtcSessionManager>(),
      initializeWebRtcUseCase: sl(),
      createWebRtcOfferUseCase: sl(),
      createWebRtcAnswerUseCase: sl(),
      setRemoteAnswerUseCase: sl(),
      addRemoteIceCandidateUseCase: sl(),
      addDataChannelUseCase: sl(),
      removeDataChannelUseCase: sl(),
      sendWebRtcDataUseCase: sl(),
      closeWebRtcUseCase: sl(),
      connectionStateUseCase: sl(),
      recoveryStrategy: sl(),
      onlineAwareness: sl(),
    ),
  );
}
