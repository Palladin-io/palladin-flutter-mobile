import 'dart:typed_data';

/// Borrowed current app key and prepared metadata scope. The app retains key
/// ownership; request work validates that same session before every read.
final class AutoFillRequestSession {
  AutoFillRequestSession({
    required this.privateKey,
    required Iterable<String> vaultIds,
    required this.validateCurrent,
  }) : vaultIds = List.unmodifiable(vaultIds);
  final Uint8List privateKey;
  final List<String> vaultIds;
  final void Function() validateCurrent;
}
