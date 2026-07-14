/// Pluggable logger for the Scomm Connector package.
///
/// The package never prints on its own. Register a [ScommLogger] from the host
/// app if you want package logs:
///
/// ```dart
/// ScommLog.setLogger(MyAppScommLogger());
/// ```
abstract class ScommLogger {
  void debug(String message);

  void info(String message);

  void warning(String message, [Object? error, StackTrace? stackTrace]);

  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Global log facade used by the package internals.
abstract final class ScommLog {
  static ScommLogger? _logger;

  /// Currently registered logger, or `null` when logging is disabled.
  static ScommLogger? get logger => _logger;

  /// Install a host-app logger. Pass `null` to silence package logs again.
  static void setLogger(ScommLogger? logger) {
    _logger = logger;
  }

  static void debug(String message) => _logger?.debug(message);

  static void info(String message) => _logger?.info(message);

  static void warning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      _logger?.warning(message, error, stackTrace);

  static void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      _logger?.error(message, error, stackTrace);
}
