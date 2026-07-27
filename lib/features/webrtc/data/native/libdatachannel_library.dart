import 'dart:ffi';
import 'dart:io';

import 'libdatachannel_bindings.dart';

/// Loads the shared libdatachannel library for the current platform.
///
/// Bundled automatically when [scommconnector] is used as a Flutter FFI plugin
/// (`ffiPlugin: true` for Android / Windows / Linux; Apple via CocoaPods build).
class LibDataChannelLibrary {
  LibDataChannelLibrary._(this.bindings);

  final LibDataChannelBindings bindings;

  static LibDataChannelLibrary? _instance;

  /// Process-wide singleton — loads native libdatachannel once.
  static LibDataChannelLibrary instance() {
    final existing = _instance;
    if (existing != null) return existing;

    final lib = _open();
    final bindings = LibDataChannelBindings(lib);
    bindings.rtcPreload();
    return _instance = LibDataChannelLibrary._(bindings);
  }

  static DynamicLibrary _open() {
    final override = Platform.environment['LIBDATACHANNEL_PATH'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }

    if (Platform.isAndroid || Platform.isLinux) {
      return _openFirst(const [
        'libdatachannel.so',
      ]);
    }

    if (Platform.isWindows) {
      return _openWindows();
    }

    if (Platform.isIOS || Platform.isMacOS) {
      // Statically linked via CocoaPods -force_load, or framework bundle.
      try {
        return DynamicLibrary.open('datachannel.framework/datachannel');
      } catch (_) {
        try {
          return DynamicLibrary.open('scommconnector.framework/scommconnector');
        } catch (_) {
          return DynamicLibrary.process();
        }
      }
    }

    throw UnsupportedError(
      'libdatachannel FFI is not supported on ${Platform.operatingSystem}',
    );
  }

  static DynamicLibrary _openWindows() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      // Flutter FFI plugin bundles this next to the exe.
      'datachannel.dll',
      'libdatachannel.dll',
      '$exeDir${Platform.pathSeparator}datachannel.dll',
      '$exeDir${Platform.pathSeparator}libdatachannel.dll',
      _packageRelative(
        'native${Platform.pathSeparator}build${Platform.pathSeparator}'
        'libdatachannel${Platform.pathSeparator}Release'
        '${Platform.pathSeparator}datachannel.dll',
      ),
      _packageRelative(
        'src${Platform.pathSeparator}..${Platform.pathSeparator}native'
        '${Platform.pathSeparator}build${Platform.pathSeparator}'
        'libdatachannel${Platform.pathSeparator}Release'
        '${Platform.pathSeparator}datachannel.dll',
      ),
    ];

    Object? lastError;
    for (final path in candidates) {
      try {
        return DynamicLibrary.open(path);
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'Failed to load libdatachannel (datachannel.dll). '
      'Rebuild the Windows app so the FFI plugin can bundle the DLL, '
      'or set LIBDATACHANNEL_PATH. Last error: $lastError',
    );
  }

  static DynamicLibrary _openFirst(List<String> names) {
    Object? lastError;
    for (final name in names) {
      try {
        return DynamicLibrary.open(name);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'Failed to load libdatachannel ($names). '
      'Ensure the scommconnector FFI plugin built native code for this '
      'platform (flutter clean && rebuild). Last error: $lastError',
    );
  }

  static String _packageRelative(String relative) {
    final roots = <String>[
      Directory.current.path,
      '${Directory.current.path}${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}scommconnector',
      '${Directory.current.path}${Platform.pathSeparator}..'
          '${Platform.pathSeparator}package${Platform.pathSeparator}Scomm'
          '${Platform.pathSeparator}scommconnector',
      'C:${Platform.pathSeparator}dev${Platform.pathSeparator}package'
          '${Platform.pathSeparator}Scomm${Platform.pathSeparator}scommconnector',
    ];
    for (final root in roots) {
      final path = '$root${Platform.pathSeparator}$relative';
      if (File(path).existsSync()) return path;
    }
    return relative;
  }
}
