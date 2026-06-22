import 'package:get_it/get_it.dart';
import 'package:scommconnector/features/auth/application/controllers/auth_controller.dart';

Future<void> authDI(GetIt sl) async {
  sl.registerLazySingleton<ScommAuthController>(
    () => ScommAuthController(),
  );
}
