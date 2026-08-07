import 'package:scommconnector/core/di/scomm_service_builder.dart';
import 'package:scommconnector/features/connect/connect_controller.dart';
import 'package:scommconnector/features/connect/connect_session_store.dart';

Future<void> connectDI(ScommServiceBuilder sl) async {
  sl.registerLazySingleton<ConnectSessionStore>(() => ConnectSessionStore());

  sl.registerLazySingleton<ConnectController>(
    () => ConnectController(
      sessionStore: sl(),
      signalingController: sl(),
      webRtcController: sl(),
    ),
  );
}
