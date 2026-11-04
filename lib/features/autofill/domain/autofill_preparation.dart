/// Value-free, in-memory view of the current native cache preparation.
enum AutoFillPreparationPhase {
  unknown,
  checking,
  preparing,
  publishing,
  ready,
  empty,
  failed,
}

class AutoFillPreparation {
  const AutoFillPreparation(this.phase, {this.examined = 0, this.total});

  final AutoFillPreparationPhase phase;
  final int examined;
  final int? total;
}
