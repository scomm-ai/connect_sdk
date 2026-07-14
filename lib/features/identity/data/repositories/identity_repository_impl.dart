import '../../domain/entities/device_mode.dart';
import '../../domain/entities/device_service.dart';
import '../../domain/entities/identity_device.dart';
import '../../domain/entities/saved_device_identity.dart';
import '../../domain/repositories/identity_repository.dart';
import '../../../../core/auth/jwt_sub_reader.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/logging/scomm_diag_log.dart';
import '../datasources/local/identity_local_datasource.dart';
import '../datasources/remote/identity_remote_datasource.dart';

class IdentityRepositoryImpl implements IdentityRepository {
  final IdentityRemoteDataSource remoteDataSource;
  final IdentityLocalDataSource localDataSource;

  const IdentityRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  /// Device identity is always keyed by email, never by opaque JWT ids.
  String? _resolveEmailStorageKey(String? candidate) {
    final normalizedCandidate = normalizeSignalingUserId(candidate ?? '');
    if (looksLikeEmail(normalizedCandidate)) {
      return normalizedCandidate;
    }

    if (scommDi.isRegistered<AuthSessionState>()) {
      final sessionUserId = normalizeSignalingUserId(
        scommDi<AuthSessionState>().userIdOrNull ?? '',
      );
      if (looksLikeEmail(sessionUserId)) {
        return sessionUserId;
      }
    }

    return null;
  }

  @override
  Future<IdentityDevice> registerDevice({
    required String deviceName,
    required String deviceType,
    required DeviceMode mode,
  }) async {
    final response = await remoteDataSource.registerDevice(
      deviceName: deviceName,
      deviceType: deviceType,
      mode: mode,
    );
    final device = response.toEntity();
    final persistKey = _resolveEmailStorageKey(device.userId);
    ScommDiagLog.identity('repo_register_persist', {
      'deviceId': device.deviceId,
      'deviceUserId': device.userId,
      'persistKey': persistKey,
      'note': 'persist_key_must_be_email',
    });
    if (persistKey == null) {
      throw StateError(
        'Cannot persist device identity without an email. '
        'Got userId="${device.userId}".',
      );
    }
    await localDataSource.saveRegisteredDeviceIdentity(
      userId: persistKey,
      deviceId: device.deviceId,
    );
    return device;
  }

  @override
  Future<SavedDeviceIdentity?> loadSavedDeviceIdentity(String userId) async {
    final emailKey = _resolveEmailStorageKey(userId);
    ScommDiagLog.identity('repo_load_saved', {
      'lookupKey': userId,
      'emailKey': emailKey,
      'note': 'load_requires_email',
    });
    if (emailKey == null) {
      return null;
    }

    final saved = await localDataSource.loadRegisteredDeviceIdentity(emailKey);
    if (saved == null) {
      return null;
    }

    return SavedDeviceIdentity(userId: emailKey, deviceId: saved.deviceId);
  }

  @override
  Future<IdentityDevice> updateDevice({
    required String deviceId,
    required String deviceName,
    required String deviceType,
    required DeviceMode mode,
  }) async {
    final response = await remoteDataSource.updateDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
      mode: mode,
    );
    return response.toEntity();
  }

  @override
  Future<String> deleteDevice({required String deviceId}) {
    return remoteDataSource.deleteDevice(deviceId: deviceId);
  }

  @override
  Future<List<IdentityDevice>> listMyDevices() async {
    final response = await remoteDataSource.listMyDevices();
    return response.map((device) => device.toEntity()).toList(growable: false);
  }

  @override
  Future<DeviceService> registerService({
    required String deviceId,
    required String serviceName,
  }) async {
    final response = await remoteDataSource.registerService(
      deviceId: deviceId,
      serviceName: serviceName,
    );
    return response.toEntity();
  }

  @override
  Future<List<DeviceService>> listDeviceServices({
    required String deviceId,
  }) async {
    final response = await remoteDataSource.listDeviceServices(
      deviceId: deviceId,
    );
    return response
        .map((service) => service.toEntity())
        .toList(growable: false);
  }

  @override
  Future<DeviceService> updateService({
    required String serviceId,
    required String serviceName,
  }) async {
    final response = await remoteDataSource.updateService(
      serviceId: serviceId,
      serviceName: serviceName,
    );
    return response.toEntity();
  }

  @override
  Future<String> deleteService({required String serviceId}) {
    return remoteDataSource.deleteService(serviceId: serviceId);
  }
  
  @override
  Future<IdentityDevice> addAllowUserDevice({required String userId, required String deviceId, required String state}) async {
    final response = await remoteDataSource.addAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
      state: state,
    );
    return response.toEntity();
  }
  
  @override
  Future<List<IdentityDevice>> listAllowUserDevices({required String deviceId}) {
    return remoteDataSource.listAllowUserDevices(deviceId: deviceId).then(
      (response) => response
          .map((device) => device.toEntity())
          .toList(growable: false),
    );
  }
  
  @override
  Future<String> removeAllowUserDevice({required String userId, required String deviceId}) {
    return remoteDataSource.removeAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
    );
  }
  
  @override
  Future<IdentityDevice> updateAllowUserDevice({required String userId, required String deviceId, required String state}) {
    return remoteDataSource.updateAllowUserDevice(
      userId: userId,
      deviceId: deviceId,
      state: state,
    ).then((response) => response.toEntity());
  }
}
