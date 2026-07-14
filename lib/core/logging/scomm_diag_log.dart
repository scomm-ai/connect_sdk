import 'package:scommconnector/core/logging/scomm_logger.dart';

/// TEMPORARY diagnostics for SComm connect + device registration.
///
/// Emits via [ScommLog] only (no package prints). Register a [ScommLogger] in
/// the host app to see these lines. Search for: `[SCOMM_DIAG]`
///
/// Set [enabled] to `false` after the issues are fixed.
abstract final class ScommDiagLog {
  /// Flip to false to silence all temp diagnostics without removing call sites.
  static const bool enabled = true;

  static const String _tag = 'SCOMM_DIAG';

  /// Connection request / accept / WebRTC negotiation path.
  static void connect(String step, [Map<String, Object?> data = const {}]) {
    _emit(area: 'CONNECT', step: step, data: data);
  }

  /// Device register / restore / isRegistered path.
  static void identity(String step, [Map<String, Object?> data = const {}]) {
    _emit(area: 'IDENTITY', step: step, data: data);
  }

  static void _emit({
    required String area,
    required String step,
    required Map<String, Object?> data,
  }) {
    if (!enabled) return;

    final buffer = StringBuffer('[$_tag][$area] $step');
    if (data.isNotEmpty) {
      buffer.write(' | ');
      buffer.write(
        data.entries
            .map((entry) => '${entry.key}=${_stringify(entry.value)}')
            .join(' '),
      );
    }

    ScommLog.debug(buffer.toString());
  }

  static String _stringify(Object? value) {
    if (value == null) return 'null';
    final text = value.toString().replaceAll('\n', ' ');
    if (text.length <= 160) return text;
    return '${text.substring(0, 157)}...';
  }
}
