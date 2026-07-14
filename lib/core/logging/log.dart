import 'package:scommconnector/core/logging/scomm_logger.dart';

export 'package:scommconnector/core/logging/scomm_logger.dart';

/// Internal helpers used across the package.
///
/// All output goes through [ScommLog]. With no consumer logger registered,
/// these are silent no-ops.
void debugLog(String message) => ScommLog.debug(message);

void infoLog(String message) => ScommLog.info(message);

void warningLog(String message, [Object? error, StackTrace? stackTrace]) =>
    ScommLog.warning(message, error, stackTrace);

void errorLog(String message, [Object? error, StackTrace? stackTrace]) =>
    ScommLog.error(message, error, stackTrace);
