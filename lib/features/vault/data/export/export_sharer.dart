import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Hands a generated export file to the OS share sheet.
///
/// Follows the recovery-key precedent: the content is passed as in-memory
/// bytes via [XFile.fromData] rather than written to a predictable
/// plaintext file in temp. share_plus may spill a UUID-named file into
/// the app's own cache sandbox for the duration of the share, which the
/// OS manages — we never create a plaintext secrets file at a path we
/// control. This is isolated behind an interface so the export cubit is
/// testable without a platform channel.
abstract interface class ExportSharer {
  Future<void> share({
    required String content,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  });
}

class SharePlusExportSharer implements ExportSharer {
  const SharePlusExportSharer();

  @override
  Future<void> share({
    required String content,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    try {
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: mimeType)],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );
    } finally {
      // Zero the plaintext byte buffer we created before it is GC'd. The
      // share sheet has already copied what it needs.
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
