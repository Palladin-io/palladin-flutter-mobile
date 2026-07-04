import '../../data/export/export_models.dart';

sealed class ExportState {
  const ExportState();
}

/// Idle — the format dialog is open but nothing has run yet.
final class ExportInitial extends ExportState {
  const ExportInitial();
}

/// Decrypting entries and building the export file.
final class ExportInProgress extends ExportState {
  const ExportInProgress();
}

/// The file was built and handed to the share sheet.
final class ExportSuccess extends ExportState {
  const ExportSuccess({required this.entryCount, required this.format});

  final int entryCount;
  final ExportFormat format;
}

/// The export could not complete.
final class ExportFailure extends ExportState {
  const ExportFailure(this.reason);

  final ExportFailureReason reason;
}

enum ExportFailureReason { empty, crypto, network, unknown }
