import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scommconnector/core/logging/log.dart';
import 'package:scommconnector/core/logging/scomm_diag_log.dart';
import 'identity_local_datasource.dart';

class IdentityLocalDataSourceImpl implements IdentityLocalDataSource {
  final FlutterSecureStorage _secureStorage;

  IdentityLocalDataSourceImpl({required FlutterSecureStorage secureStorage})
    : _secureStorage = secureStorage;

  String _deviceStoreKey(String userId) => 'identity_device_store_$userId';
  @override
  Future<void> saveRegisteredDeviceIdentity({
    required String userId,
    required String deviceId,
  }) async {
    final key = _deviceStoreKey(userId);
    ScommDiagLog.identity('secure_save', {
      'storageKey': key,
      'userId': userId,
      'deviceId': deviceId,
    });
    await _secureStorage.write(key: key, value: deviceId);
  }

  @override
  Future<({String userId, String deviceId})?> loadRegisteredDeviceIdentity(
    String userId,
  ) async {
    infoLog('Loading registered device identity for userId: $userId');
    final key = _deviceStoreKey(userId);
    // await _secureStorage.delete(key: _deviceStoreKey(userId)); // For testing
    final deviceId = await _secureStorage.read(key: key);

    ScommDiagLog.identity('secure_load', {
      'storageKey': key,
      'lookupUserId': userId,
      'found': deviceId != null && deviceId.isNotEmpty,
      'deviceId': deviceId,
    });

    if (deviceId == null || deviceId.isEmpty) return null;

    return (userId: userId, deviceId: deviceId);
  }
}
