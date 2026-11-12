import 'dart:async';
import 'dart:collection';

import '../data/autofill_credential_source.dart';
import '../data/autofill_request_controller.dart';

/// Request-local username memo. Only two legacy bodies may be open at once.
final class AutoFillUsernamePreviews {
  final _values = <Object, Future<AutoFillUsernamePreview>>{};
  final _queue = Queue<_PreviewRead>();
  int _active = 0, _generation = 0;

  Future<String> read(
    Object identity,
    Future<AutoFillUsernamePreview> Function() load,
  ) async {
    final generation = _generation;
    var pending = _values[identity];
    if (pending == null) {
      final read = _PreviewRead(load, generation);
      pending = read.result.future;
      _values[identity] = pending;
      _queue.add(read);
      _drain();
    }
    try {
      final preview = await pending;
      if (generation != _generation) throw const AutoFillRequestInvalidated();
      preview.validateCurrent();
      return preview.username;
    } catch (_) {
      if (identical(_values[identity], pending)) _values.remove(identity);
      rethrow;
    }
  }

  void clear() {
    _generation++;
    _values.clear();
    while (_queue.isNotEmpty) {
      _queue.removeFirst().result.completeError(
        const AutoFillRequestInvalidated(),
      );
    }
  }

  void _drain() {
    while (_active < 2 && _queue.isNotEmpty) {
      final read = _queue.removeFirst();
      _active++;
      unawaited(_run(read));
    }
  }

  Future<void> _run(_PreviewRead read) async {
    try {
      final preview = await read.load();
      if (read.generation != _generation) {
        throw const AutoFillRequestInvalidated();
      }
      preview.validateCurrent();
      read.result.complete(preview);
    } catch (error, stack) {
      read.result.completeError(error, stack);
    } finally {
      _active--;
      _drain();
    }
  }
}

final class _PreviewRead {
  _PreviewRead(this.load, this.generation);
  final Future<AutoFillUsernamePreview> Function() load;
  final int generation;
  final result = Completer<AutoFillUsernamePreview>();
}
