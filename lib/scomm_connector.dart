export 'package:scommconnector/core/errors/errors.dart';
export 'package:scommconnector/core/auth/signaling_access_token_provider.dart';
export 'package:scommconnector/core/di/service_locator.dart';
export 'package:scommconnector/features/auth/auth.dart';
export 'package:scommconnector/features/webrtc/webrtc.dart';
export 'package:scommconnector/features/identity/identity.dart';
export 'package:scommconnector/features/signaling/signaling.dart';
export 'package:scommconnector/features/scomm_session_state.dart';
export 'package:scommconnector/features/connect/connect_controller.dart';
export 'package:scommconnector/features/connect/datachannel/scomm_datachannel_protocol.dart';
export 'package:scommconnector/features/connect/datachannel/scomm_message_router.dart';
export 'package:scommconnector/features/connect/datachannel/scomm_datachannel_transport.dart';
export 'package:scommconnector/features/connect/datachannel/scomm_datachannel_controller.dart';
export 'package:scommconnector/features/connect/datachannel/scomm_transfer_speed.dart';


import 'package:scommconnector/core/di/service_locator.dart';
import 'package:scommconnector/core/logging/log.dart';
import 'package:shared_preferences/shared_preferences.dart';


export 'package:scommconnector/scomm_connector_controller.dart';
export 'package:scommconnector/scomm_start_config.dart';

Future<void> runScommConnectorDI(String host, int port, bool useTls) async {
  infoLog("Host: $host, Port: $port, Use TLS: $useTls");
  await setupDependencies(host: host, port: port, useTls: useTls);
}


Future<void> clearCache() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}