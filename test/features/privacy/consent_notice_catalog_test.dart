import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/privacy/data/consent_notice_catalog.dart';

void main() {
  final archive =
      jsonDecode(
            File('docs/consent-notices/2026-09-18.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final row in archive['notices'] as List) {
    final notice = row as Map<String, dynamic>;
    test(
      'matches archived ${notice['purpose']} / ${notice['locale']} text and version',
      () {
        final displayed = consentNotice(
          notice['purpose'] as String,
          notice['locale'] as String,
        )!;
        expect(consentNoticeVersion, archive['version']);
        expect(displayed.version, archive['version']);
        expect(displayed.locale, notice['locale']);
        expect(displayed.text, notice['text']);
      },
    );
  }
}
