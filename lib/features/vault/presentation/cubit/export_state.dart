import '../../data/export/export_models.dart';

sealed class ExportState {
  const ExportState();
}

final class ExportInitial extends ExportState {
  const ExportInitial();
}

final class ExportInProgress extends ExportState {
  const ExportInProgress();
}

final class ExportSuccess extends ExportState {
  const ExportSuccess({required this.entryCount, required this.format});
  final int entryCount;
  final ExportFormat format;
}

final class ExportFailure extends ExportState {
  const ExportFailure(this.reason);
  final ExportErrorKind reason;
}
