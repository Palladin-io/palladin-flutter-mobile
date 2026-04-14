/// UX-level password strength score on a 0..4 scale.
///
/// `0 = Too short`, `1 = Weak`, `2 = Fair`, `3 = Strong`, `4 = Very strong`.
///
/// Mirrors the rubric used by the web panel so the same password
/// produces the same strength signal on either platform.
enum PasswordStrength {
  tooShort(0),
  weak(1),
  fair(2),
  strong(3),
  veryStrong(4);

  const PasswordStrength(this.score);

  /// 0..4 numeric score used to drive the strength-bar UI.
  final int score;

  /// Minimum strength required to proceed with master-password setup.
  ///
  /// Matches the web panel's `MINIMUM_ACCEPTABLE_SCORE = 2`.
  static const PasswordStrength minimumAcceptable = PasswordStrength.fair;

  /// `true` if this score is at or above [minimumAcceptable].
  bool get isAcceptable => score >= minimumAcceptable.score;
}

/// Estimates master-password strength on a 0..4 scale.
///
/// The rubric is intentionally simple and deterministic so the UI
/// feels responsive: length contributes most, character-class variety
/// fills in the rest. This is a UX signal, **not** a security gate —
/// the real protection comes from Argon2id's cost parameters applied
/// to whatever password the user picks.
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.length < 8) {
    return PasswordStrength.tooShort;
  }

  var score = 1;
  if (password.length >= 12) score += 1;
  if (password.length >= 16) score += 1;

  final classes = _countCharacterClasses(password);
  if (classes >= 3) score += 1;

  final clamped = score.clamp(0, 4);
  return PasswordStrength.values.firstWhere((s) => s.score == clamped);
}

int _countCharacterClasses(String password) {
  var classes = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) classes += 1;
  if (RegExp(r'[A-Z]').hasMatch(password)) classes += 1;
  if (RegExp(r'[0-9]').hasMatch(password)) classes += 1;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) classes += 1;
  return classes;
}
