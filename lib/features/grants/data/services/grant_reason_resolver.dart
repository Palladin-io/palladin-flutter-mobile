import 'dart:typed_data';

import '../models/grant_model.dart';

/// Opens encrypted Agent justifications for grant-history presentation.
///
/// Plaintext is returned only to the in-memory domain projection. Keys and
/// plaintext byte buffers must be wiped by implementations before completion.
abstract interface class GrantReasonResolver {
  Future<Map<String, String>> resolve({
    required List<GrantModel> grants,
    required Uint8List memberPrivateKey,
  });
}
