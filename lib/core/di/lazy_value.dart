/// A statically typed, retryable lazy value.
///
/// Failed construction is not cached. Recursive access is reported as a
/// dependency cycle instead of overflowing the stack.
final class LazyValue<T extends Object> {
  LazyValue(this._create);

  final T Function() _create;
  T? _value;
  bool _resolving = false;

  bool get isInitialized => _value != null;

  T get value {
    final cached = _value;
    if (cached != null) return cached;
    if (_resolving) {
      throw StateError(
        'Circular dependency detected while resolving LazyValue<$T>',
      );
    }

    _resolving = true;
    try {
      final created = _create();
      _value = created;
      return created;
    } finally {
      _resolving = false;
    }
  }
}
