import 'package:scommconnector/core/di/lazy_value.dart';

/// Compile-time-friendly service registry for the Scomm Connector package.
///
/// Wiring modules call [call] / [isRegistered] the same way as before
/// (`scommDi<T>()`), without a runtime DI package.
final class ScommServiceBuilder {
  final Map<_TypeKey, _Entry> _entries = {};
  bool _disposed = false;

  bool isRegistered<T extends Object>({String? instanceName}) {
    return _entries.containsKey(_TypeKey(T, instanceName));
  }

  T call<T extends Object>({String? instanceName}) {
    final key = _TypeKey(T, instanceName);
    final entry = _entries[key];
    if (entry == null) {
      throw StateError(
        'Object/factory with type $T'
        '${instanceName != null ? ' and name $instanceName' : ''} is not registered',
      );
    }
    return entry.resolve<T>();
  }

  LazyValue<T> registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
  }) {
    _ensureOpen();
    final value = LazyValue<T>(() => instance);
    _put(_TypeKey(T, instanceName), _LazyValueEntry<T>(value));
    return value;
  }

  LazyValue<T> registerLazySingleton<T extends Object>(
    T Function() create, {
    String? instanceName,
  }) {
    _ensureOpen();
    final value = LazyValue<T>(create);
    _put(_TypeKey(T, instanceName), _LazyValueEntry<T>(value));
    return value;
  }

  void registerFactory<T extends Object>(
    T Function() create, {
    String? instanceName,
  }) {
    _ensureOpen();
    _put(_TypeKey(T, instanceName), _FactoryEntry(create));
  }

  /// Removes a prior registration so a type can be wired again.
  void unregister<T extends Object>({String? instanceName}) {
    _ensureOpen();
    _entries.remove(_TypeKey(T, instanceName));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entries.clear();
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('ScommServiceBuilder is disposed');
    }
  }

  void _put(_TypeKey key, _Entry entry) {
    if (_entries.containsKey(key)) {
      throw StateError('Type ${key.type} is already registered');
    }
    _entries[key] = entry;
  }
}

final class _TypeKey {
  const _TypeKey(this.type, this.instanceName);

  final Type type;
  final String? instanceName;

  @override
  bool operator ==(Object other) {
    return other is _TypeKey &&
        other.type == type &&
        other.instanceName == instanceName;
  }

  @override
  int get hashCode => Object.hash(type, instanceName);
}

sealed class _Entry {
  T resolve<T extends Object>();
}

final class _LazyValueEntry<S extends Object> extends _Entry {
  _LazyValueEntry(this.lazy);

  final LazyValue<S> lazy;

  @override
  T resolve<T extends Object>() => lazy.value as T;
}

final class _FactoryEntry extends _Entry {
  _FactoryEntry(this.factory);

  final Object Function() factory;

  @override
  T resolve<T extends Object>() => factory() as T;
}
