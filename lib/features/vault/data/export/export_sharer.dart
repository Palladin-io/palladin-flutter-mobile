import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Hands one protected staged file to the OS share sheet.
abstract interface class ExportSharer {
  Future<void> share({
    required String path,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  });
}

class SharePlusExportSharer implements ExportSharer {
  const SharePlusExportSharer();

  @override
  Future<void> share({
    required String path,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) => Share.shareXFiles(
    [XFile(path, mimeType: mimeType)],
    subject: subject,
    sharePositionOrigin: sharePositionOrigin,
  );
}
