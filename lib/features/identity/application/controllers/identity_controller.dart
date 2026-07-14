import 'dart:async';

import 'package:scommconnector/features/identity/domain/usecases/add_allow_devices_usecase.dart';
import 'package:scommconnector/features/identity/domain/usecases/list_allow_devices_usecase.dart';
import 'package:scommconnector/features/identity/domain/usecases/remove_allow_devices_usecase.dart';
import 'package:scommconnector/features/identity/domain/usecases/update_allow_devices_usecase.dart';

import '../../../../core/errors/errors.dart';
import '../../../../core/auth/jwt_sub_reader.dart';
import '../../../../core/logging/scomm_diag_log.dart';
import '../../domain/entities/device_mode.dart';
import '../../domain/entities/device_service.dart';
import '../../domain/entities/identity_device.dart';
import '../../domain/entities/saved_device_identity.dart';
import '../../domain/usecases/delete_device_usecase.dart';
import '../../domain/usecases/delete_service_usecase.dart';
import '../../domain/usecases/list_device_services_usecase.dart';
import '../../domain/usecases/list_my_devices_usecase.dart';
import '../../domain/usecases/params/delete_device_params.dart';
import '../../domain/usecases/params/delete_service_params.dart';
import '../../domain/usecases/params/list_device_services_params.dart';
import '../../domain/usecases/params/register_device_params.dart';
import '../../domain/usecases/params/register_service_params.dart';
import '../../domain/usecases/params/update_device_params.dart';
import '../../domain/usecases/params/update_service_params.dart';
import '../../domain/usecases/register_device_usecase.dart';
import '../../domain/usecases/register_service_usecase.dart';
import '../../domain/usecases/update_device_usecase.dart';
import '../../domain/usecases/update_service_usecase.dart';
import '../state/identity_state.dart';

class IdentityController {
  final RegisterDeviceUseCase registerDeviceUseCase;
  final UpdateDeviceUseCase updateDeviceUseCase;
  final DeleteDeviceUseCase deleteDeviceUseCase;
  final ListMyDevicesUseCase listMyDevicesUseCase;
  final RegisterServiceUseCase registerServiceUseCase;
  final ListDeviceServicesUseCase listDeviceServicesUseCase;
  final UpdateServiceUseCase updateServiceUseCase;
  final DeleteServiceUseCase deleteServiceUseCase;

  final ListAllowUserDevicesUsecase listAllowUserDevicesUseCase;
  final UpdateAllowUserDeviceUsecase updateAllowUserDeviceUseCase;
  final AddAllowUserDeviceUsecase addAllowUserDeviceUseCase;
  final RemoveAllowUserDeviceUsecase removeAllowUserDeviceUseCase;

  IdentityState _state = const IdentityState();

  IdentityController({
    required this.registerDeviceUseCase,
    required this.updateDeviceUseCase,
    required this.deleteDeviceUseCase,
    required this.listMyDevicesUseCase,
    required this.registerServiceUseCase,
    required this.listDeviceServicesUseCase,
    required this.updateServiceUseCase,
    required this.deleteServiceUseCase,

    required this.listAllowUserDevicesUseCase,
    required this.updateAllowUserDeviceUseCase,
    required this.addAllowUserDeviceUseCase,
    required this.removeAllowUserDeviceUseCase,
  });

  IdentityState get state => _state;

  final _identityStateController = StreamController<IdentityState>.broadcast();
  Stream<IdentityState> get identityStates => _identityStateController.stream;

    void _notify(IdentityState newState) {
    _state = newState;
    _identityStateController.add(_state);
  }


  Future<SavedDeviceIdentity?> loadSavedDeviceIdentity(String email) async {
    _setLoading();
    ScommDiagLog.identity('load_saved_start', {
      'lookupKey': email,
      'looksLikeEmail': looksLikeEmail(email),
      'priorIsRegistered': _state.isRegistered,
      'priorDeviceId': _state.savedDeviceIdentity?.deviceId,
    });

    if (!looksLikeEmail(email)) {
      ScommDiagLog.identity('load_saved_skipped_non_email', {
        'lookupKey': email,
      });
      _state = _state.copyWith(
        status: IdentityStatus.success,
        clearError: true,
        clearMessage: true,
      );
      _notify(_state);
      return null;
    }

    try {
      final savedIdentity = await registerDeviceUseCase.repository
          .loadSavedDeviceIdentity(email);

      _state = _state.copyWith(
        status: IdentityStatus.success,
        isRegistered: savedIdentity != null,
        savedDeviceIdentity: savedIdentity,
        clearSavedDeviceIdentity: savedIdentity == null,
        clearError: true,
        clearMessage: true,
      );
      _notify(_state);
      ScommDiagLog.identity('load_saved_result', {
        'lookupKey': email,
        'found': savedIdentity != null,
        'savedUserId': savedIdentity?.userId,
        'savedDeviceId': savedIdentity?.deviceId,
        'isRegistered': _state.isRegistered,
      });
      return savedIdentity;
    } catch (error) {
      ScommDiagLog.identity('load_saved_failed', {
        'lookupKey': email,
        'error': error,
      });
      _setFailure(error);
      rethrow;
    }
  }

  Future<IdentityDevice> registerDevice({
    required String deviceName,
    required String deviceType,
    required DeviceMode mode,
  }) async {
    _setLoading();
    ScommDiagLog.identity('register_start', {
      'deviceName': deviceName,
      'deviceType': deviceType,
      'mode': mode.name,
    });

    try {
      final device = await registerDeviceUseCase(
        RegisterDeviceParams(
          deviceName: deviceName,
          deviceType: deviceType,
          mode: mode,
        ),
      );
      ScommDiagLog.identity('register_ok', {
        'deviceId': device.deviceId,
        'userId': device.userId,
        'deviceName': device.deviceName,
      });
      _setDeviceSuccess(device, 'Device registered successfully');
      return device;
    } catch (error) {
      ScommDiagLog.identity('register_failed', {'error': error});
      _setFailure(error);
      rethrow;
    }
  }

  Future<IdentityDevice> updateDevice({
    required String deviceId,
    required String deviceName,
    required String deviceType,
    required DeviceMode mode,
  }) async {
    _setLoading();

    try {
      final device = await updateDeviceUseCase(
        UpdateDeviceParams(
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: deviceType,
          mode: mode,
        ),
      );
      _setDeviceSuccess(device, 'Device updated successfully');
      return device;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<String> deleteDevice({required String deviceId}) async {
    _setLoading();

    try {
      final message = await deleteDeviceUseCase(
        DeleteDeviceParams(deviceId: deviceId),
      );
      _state = _state.copyWith(
        status: IdentityStatus.success,
        message: message,
        clearDevice: true,
        clearError: true,
      );
      _notify(_state);
      return message;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<List<IdentityDevice>> listMyDevices() async {
    _setLoading();

    try {
      final devices = await listMyDevicesUseCase();
      _setDevicesSuccess(devices);
      return devices;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<DeviceService> registerService({
    required String deviceId,
    required String serviceName,
  }) async {
    _setLoading();

    try {
      final service = await registerServiceUseCase(
        RegisterServiceParams(deviceId: deviceId, serviceName: serviceName),
      );
      _setServiceSuccess(service, 'Service registered successfully');
      return service;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<List<DeviceService>> listDeviceServices({
    required String deviceId,
  }) async {
    _setLoading();

    try {
      final services = await listDeviceServicesUseCase(
        ListDeviceServicesParams(deviceId: deviceId),
      );
      _setServicesSuccess(services);
      return services;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<DeviceService> updateService({
    required String serviceId,
    required String serviceName,
  }) async {
    _setLoading();

    try {
      final service = await updateServiceUseCase(
        UpdateServiceParams(serviceId: serviceId, serviceName: serviceName),
      );
      _setServiceSuccess(service, 'Service updated successfully');
      return service;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<String> deleteService({required String serviceId}) async {
    _setLoading();

    try {
      final message = await deleteServiceUseCase(
        DeleteServiceParams(serviceId: serviceId),
      );
      _state = _state.copyWith(
        status: IdentityStatus.success,
        message: message,
        clearService: true,
        clearError: true,
      );
      return message;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  void _setLoading() {
    _state = _state.copyWith(
      status: IdentityStatus.loading,
      clearError: true,
      clearMessage: true,
    );
    _notify(_state);
  }

  void _setDeviceSuccess(IdentityDevice device, String message) {
    final emailKey = looksLikeEmail(device.userId)
        ? normalizeSignalingUserId(device.userId)
        : null;
    _state = _state.copyWith(
      status: IdentityStatus.success,
      device: device,
      savedDeviceIdentity: SavedDeviceIdentity(
        userId: emailKey ?? device.userId,
        deviceId: device.deviceId,
      ),
      isRegistered: true,
      message: message,
      clearError: true,
    );
    _notify(_state);
  }

  void _setDevicesSuccess(List<IdentityDevice> devices) {
    _state = _state.copyWith(
      status: IdentityStatus.success,
      devices: devices,
      clearError: true,
      clearMessage: true,
    );
    _notify(_state);
  }

  void _setServiceSuccess(DeviceService service, String message) {
    final nextServices = [..._state.services];
    final index = nextServices.indexWhere((item) => item.serviceId == service.serviceId);
    if (index >= 0) {
      nextServices[index] = service;
    } else {
      nextServices.add(service);
    }

    _state = _state.copyWith(
      status: IdentityStatus.success,
      service: service,
      services: nextServices,
      message: message,
      clearError: true,
    );
    _notify(_state);
  }

  void _setServicesSuccess(List<DeviceService> services) {
    _state = _state.copyWith(
      status: IdentityStatus.success,
      services: services,
      clearError: true,
      clearMessage: true,
    );
    _notify(_state);
  }

  void _setFailure(Object error) {
    _state = _state.copyWith(
      status: IdentityStatus.failure,
      error: _toUserMessage(error),
    );
    _notify(_state);
  }

  String _toUserMessage(Object error) {
    if (error is AppException) {
      return error.message;
    }

    return 'Identity request failed. Please try again.';
  }

  Future<List<IdentityDevice>> listAllowUserDevices({
    required String deviceId,
  }) async {
    _setLoading();

    try {
      final devices = await listAllowUserDevicesUseCase(deviceId: deviceId);
      _state = _state.copyWith(
        status: IdentityStatus.success,
        message: 'Allow user devices loaded',
        clearError: true,
      );
      return devices;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<IdentityDevice> addAllowUserDevice({
    required String userId,
    required String deviceId,
    required String state,
  }) async {
    _setLoading();

    try {
      final device = await addAllowUserDeviceUseCase(
        userId: userId,
        deviceId: deviceId,
        state: state,
      );
      _setDeviceSuccess(device, 'Device added to allow list successfully');
      return device;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<void> removeAllowUserDevice({
    required String userId,
    required String deviceId,
  }) async {
    _setLoading();

    try {
      await registerDeviceUseCase.repository.removeAllowUserDevice(
        userId: userId,
        deviceId: deviceId,
      );
      _state = _state.copyWith(
        status: IdentityStatus.success,
        message: 'Device removed from allow list successfully',
        clearError: true,
      );
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }

  Future<IdentityDevice> updateAllowUserDevice({
    required String userId,
    required String deviceId,
    required String state,
  }) async {
    _setLoading();

    try {
      final device = await updateAllowUserDeviceUseCase(
        userId: userId,
        deviceId: deviceId,
        state: state,
      );
      _setDeviceSuccess(device, 'Allow device updated successfully');
      return device;
    } catch (error) {
      _setFailure(error);
      rethrow;
    }
  }
}
