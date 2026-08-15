import '../../domain/entities/encrypted_reason.dart';

/// Strict wire mapper for the canonical protocol-2 encrypted reason envelope.
final class EncryptedReasonModel {
  const EncryptedReasonModel._();

  static EncryptedReason fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Missing encrypted reason');
    }
    final json = Map<String, dynamic>.from(value);
    return EncryptedReason(
      descriptor: Map<String, dynamic>.from(json['descriptor'] as Map),
      encodedSuitePayload: json['encodedSuitePayload'] as String,
      wrappedReasonDek: Map<String, dynamic>.from(
        json['wrappedReasonDek'] as Map,
      ),
      agentSignature: json['agentSignature'] as String,
    );
  }
}
