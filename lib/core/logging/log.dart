// import 'dart:developer' as developer;

/// Default **on**; set `--dart-define=INFO_LOG=false` to disable.
const bool infoLogFlag = bool.fromEnvironment('INFO_LOG', defaultValue: false);
const bool debugLogFlag = bool.fromEnvironment(
  'DEBUG_LOG',
  defaultValue: false,
);
const bool warningLogFlag = bool.fromEnvironment(
  'WARNING_LOG',
  defaultValue: true,
);
const bool errorLogFlag = bool.fromEnvironment('ERROR_LOG', defaultValue: true);

class LogLevel {
  static const int debug = 500;
  static const int info = 800;
  static const int warning = 900;
  static const int error = 1000;
}

void debugLog(String message) {
  if (!debugLogFlag) return;
}

void infoLog(String message) {
  if (!infoLogFlag) return;
}

void warningLog(String message, [Object? error]) {
  if (!warningLogFlag) return;
}

void errorLog(String message, [Object? error, StackTrace? stackTrace]) {}
