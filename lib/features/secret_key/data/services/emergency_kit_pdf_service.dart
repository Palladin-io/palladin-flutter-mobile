import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../../core/crypto/identity/secret_key_codec.dart';

/// Localized, already formatted text for the Emergency Kit PDF.
final class EmergencyKitLabels {
  const EmergencyKitLabels({
    required this.title,
    required this.intro,
    required this.account,
    required this.secretKey,
    required this.secretKeyQr,
    required this.masterPassword,
    required this.signInAddress,
    required this.generated,
    required this.footer,
  });

  final String title;
  final String intro;
  final String account;
  final String secretKey;
  final String secretKeyQr;
  final String masterPassword;
  final String signInAddress;
  final String generated;
  final String footer;
}

/// Builds the Emergency Kit locally (`identity-kdf/v3` `emergencyKit`).
///
/// The kit holds only the e-mail, the Secret Key (text and QR), a blank
/// master-password field, the sign-in address and the date. It never holds
/// the recovery phrase, the password or any other key.
class EmergencyKitPdfService {
  EmergencyKitPdfService({
    Future<ByteData> Function(String asset)? assetLoader,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(XFile file)? shareFile,
  }) : _assetLoader = assetLoader ?? rootBundle.load,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _shareFile = shareFile ?? _systemShare;

  static const fileName = 'Palladin Emergency Kit.pdf';

  final Future<ByteData> Function(String asset) _assetLoader;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(XFile file) _shareFile;

  Future<Uint8List> build({
    required String email,
    required String accountId,
    required Uint8List accountSecret,
    required String signInAddress,
    required String generatedDate,
    required EmergencyKitLabels labels,
  }) async {
    final display = SecretKeyCodec.format(accountId, accountSecret);
    final qr = SecretKeyCodec.emergencyKitQr(accountId, accountSecret);
    final regular = pw.Font.ttf(
      await _assetLoader('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await _assetLoader('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document(
      title: labels.title,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (_) =>
            _page(labels, email, display, qr, signInAddress, generatedDate),
      ),
    );
    return document.save();
  }

  /// Shares the PDF through the system sheet. The only file is a private
  /// temporary copy that is deleted once the sheet completes.
  Future<void> share(Uint8List bytes) async {
    final root = await _temporaryDirectory();
    final parent = await Directory(
      p.join(root.path, 'emergency-kit'),
    ).create(recursive: true);
    final directory = await parent.createTemp();
    try {
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      await _shareFile(XFile(file.path, mimeType: 'application/pdf'));
    } finally {
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  }

  static Future<void> _systemShare(XFile file) async {
    await Share.shareXFiles([file]);
  }

  pw.Widget _page(
    EmergencyKitLabels labels,
    String email,
    String display,
    String qr,
    String signInAddress,
    String generatedDate,
  ) {
    pw.Widget field(String label, pw.Widget value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          value,
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.title,
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(labels.intro, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 28),
        field(
          labels.account,
          pw.Text(email, style: const pw.TextStyle(fontSize: 13)),
        ),
        field(
          labels.secretKey,
          pw.Text(
            display,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
        field(
          labels.secretKeyQr,
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qr,
            width: 140,
            height: 140,
          ),
        ),
        field(
          labels.masterPassword,
          pw.Container(
            height: 32,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey600),
              borderRadius: pw.BorderRadius.circular(4),
            ),
          ),
        ),
        field(
          labels.signInAddress,
          pw.Text(signInAddress, style: const pw.TextStyle(fontSize: 13)),
        ),
        field(
          labels.generated,
          pw.Text(generatedDate, style: const pw.TextStyle(fontSize: 13)),
        ),
        pw.Spacer(),
        pw.Text(
          labels.footer,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }
}
