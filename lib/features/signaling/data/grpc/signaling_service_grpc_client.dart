import '../../domain/entities/signaling_entities.dart';

typedef ResolveSignalingAccessToken = Future<String?> Function();

// abstract class SignalingServiceGrpcClient {
//   Future<Stream<SignalingEnvelope>> connect({required String deviceId});

//   Future<void> sendEnvelope(SignalingEnvelope envelope);

//   Stream<SignalingPresenceEvent> watchPresence({
//     required List<String> targetUris,
//   });

//   Future<void> disconnect();
// }


abstract class SignalingServiceGrpcClient {
  Stream<SignalingEnvelope> get messages;

  Stream<SignalingConnectionStatus> get connectionStatus;

  Future<void> connect({required String deviceId});

  Future<void> sendEnvelope(SignalingEnvelope envelope);

  Stream<SignalingPresenceEvent> watchPresence({
    required List<String> targetUris,
  });

  Future<void> disconnect();

  Future<void> dispose();
}