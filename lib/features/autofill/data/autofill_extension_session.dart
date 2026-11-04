import 'dart:async';
import 'dart:typed_data';

import 'autofill_credential_source.dart';
import 'autofill_request_controller.dart';

/// One freshly authenticated extension request. Native retains the original OS
/// origin and performs the final source-fenced handoff; no body is opened for UI.
final class AutoFillExtensionSession {
  AutoFillExtensionSession({
    required this.request,
    required AutoFillCredentialSource source,
    required Iterable<String> vaultIds,
    required Uint8List memberPrivateKey,
    required Future<bool> Function() validateNative,
    required Future<void> Function(Map<String, Object?>) completeNative,
    required void Function() clearRuntime,
  }) : _source = source,
       _vaultIds = List.unmodifiable(vaultIds),
       _privateKey = Uint8List.fromList(memberPrivateKey),
       _validateNative = validateNative,
       _completeNative = completeNative,
       _clearRuntime = clearRuntime {
    if (memberPrivateKey.length != 32) {
      close();
      throw const AutoFillRequestInvalidated();
    }
    _expiry = Timer.periodic(const Duration(seconds: 1), (_) {
      if (request.expired) close();
    });
  }

  final AutoFillRequest request;
  final AutoFillCredentialSource _source;
  final List<String> _vaultIds;
  final Uint8List _privateKey;
  final Future<bool> Function() _validateNative;
  final Future<void> Function(Map<String, Object?>) _completeNative;
  final void Function() _clearRuntime;
  final Map<String, AutoFillCandidate> _selections = {};
  Timer? _expiry;
  bool _closed = false;
  bool _selecting = false;
  bool _listing = false;

  void _validate() {
    if (_closed || request.expired) {
      throw const AutoFillRequestInvalidated();
    }
  }

  Future<void> _validateSource() async {
    _validate();
    if (!await _validateNative()) {
      throw const AutoFillRequestInvalidated();
    }
    _validate();
  }

  Future<List<Map<String, Object?>>> candidates() async {
    try {
      _validate();
      if (_listing || _selecting || _selections.isNotEmpty) {
        throw const AutoFillRequestInvalidated();
      }
      _listing = true;
      await _validateSource();
      final candidates = request.mode == AutoFillRequestMode.manualNative
          ? await _source.manualCandidates(
              vaultIds: _vaultIds,
              validateRequest: _validate,
            )
          : await _source.candidates(
              vaultIds: _vaultIds,
              verifiedHosts: request.verifiedHosts,
              validateRequest: _validate,
            );
      await _validateSource();
      final result = <Map<String, Object?>>[];
      for (var index = 0; index < candidates.length; index++) {
        final candidate = candidates[index];
        final id = '${request.id}/$index';
        _selections[id] = candidate;
        result.add({
          'selectionId': id,
          'label': candidate.label,
          'domains': candidate.domains,
        });
      }
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _listing = false;
    }
  }

  Future<void> select({
    required String selectionId,
    required String selectedHost,
    required bool manualConfirmed,
  }) async {
    try {
      _validate();
      final candidate = _selections[selectionId];
      final manual = request.mode == AutoFillRequestMode.manualNative;
      if (_listing ||
          _selecting ||
          candidate == null ||
          !candidate.domains.contains(selectedHost) ||
          (manual && !manualConfirmed) ||
          (!manual && !request.verifiedHosts.contains(selectedHost))) {
        throw const AutoFillRequestInvalidated();
      }
      _selecting = true;
      await _validateSource();
      await _source.withCredential(
        candidate: candidate,
        selectedHost: selectedHost,
        memberPrivateKey: _privateKey,
        validateRequest: _validate,
        complete: (credential) async {
          await _validateSource();
          // Native rechecks its own request, manual consent, lease and source
          // epoch under the cross-process fence before completing with the OS.
          final response = <String, Object?>{
            'requestId': request.id,
            'selectionId': selectionId,
            'selectedHost': selectedHost,
            'username': credential.username,
            'password': credential.password,
            'accessContext': credential.accessContext.toJson(),
          };
          try {
            _validate();
            await _completeNative(response);
          } finally {
            response.clear();
          }
        },
      );
    } finally {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    _selections.clear();
    _privateKey.fillRange(0, _privateKey.length, 0);
    _clearRuntime();
  }
}
