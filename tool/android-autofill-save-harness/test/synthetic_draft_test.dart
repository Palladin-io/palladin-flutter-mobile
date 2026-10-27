import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';
import '../main.dart';

void main() {
  AutoFillSaveDraft draft({
    String password = 'synthetic-save-password-1',
    String source = 'io.palladin.autofill.savefixture.form',
    List<String> domains = const ['fixture.invalid'],
    bool isWeb = false,
  }) => AutoFillSaveDraft(
    id: 'opaque-capture',
    session: 'opaque-session',
    packageName: source,
    domains: domains,
    isWeb: isWeb,
    username: 'synthetic-save-user',
    password: password,
  );

  test('accepts only the expected real handoff values and native source', () {
    expect(matchesSyntheticDraft(draft()), isTrue);
    expect(matchesSyntheticDraft(draft(password: 'wrong')), isFalse);
    expect(matchesSyntheticDraft(draft(source: 'other.package')), isFalse);
    expect(matchesSyntheticDraft(draft(domains: ['other.invalid'])), isFalse);
    expect(
      matchesSyntheticDraft(
        draft(domains: ['fixture.invalid', 'other.invalid']),
      ),
      isFalse,
    );
    expect(matchesSyntheticDraft(draft(isWeb: true)), isFalse);
    final cancelled = draft()..clear();
    expect(matchesSyntheticDraft(cancelled), isFalse);
  });
}
