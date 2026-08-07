import 'package:scommconnector/core/di/scomm_service_builder.dart';
import 'package:scommconnector/features/auth/application/controllers/auth_controller.dart';

Future<void> authDI(ScommServiceBuilder sl) async {
  sl.registerLazySingleton<ScommAuthController>(
    () => ScommAuthController(),
  );
}
