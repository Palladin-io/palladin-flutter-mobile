import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/import/import_engine.dart';
import 'package:mobile_palladin/features/vault/data/import/import_models.dart';
import 'package:mobile_palladin/features/vault/data/import/import_normalizer.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

ParsedFile _parsed(String s) {
  final outcome = ImportEngine.parse(_bytes(s));
  expect(outcome, isA<ImportParsed>(),
      reason: 'expected ImportParsed, got ${outcome.runtimeType}');
  return (outcome as ImportParsed).result;
}

void main() {
  group('CSV detection + parsing', () {
    test('generic / chromium CSV', () {
      const csv = 'name,url,username,password,note\n'
          'GitHub,https://github.com,octocat,S3cr3t!,personal';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.genericCsv);
      expect(result.entries, hasLength(1));
      final e = result.entries.first;
      expect(e.name, 'GitHub');
      expect(e.username, 'octocat');
      expect(e.password, 'S3cr3t!');
      expect(e.urlDomain, 'github.com');
      expect(e.notes, 'personal');
    });

    test('generic CSV handles a quoted multi-line note', () {
      const csv = 'name,url,username,password,note\n'
          'AWS,https://console.aws.amazon.com,admin@acme.io,pw,"multi,\nline notes"';
      final result = _parsed(csv);
      expect(result.entries, hasLength(1));
      expect(result.entries.first.notes, 'multi,\nline notes');
    });

    test('strips a leading UTF-8 BOM', () {
      const csv = '﻿name,url,username,password,note\n'
          'GitHub,https://github.com,octocat,pw,';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.genericCsv);
      expect(result.entries.first.name, 'GitHub');
    });

    test('Firefox CSV — synthesises name from host (no title column)', () {
      const csv =
          '"url","username","password","httpRealm","formActionOrigin","guid","timeCreated","timeLastUsed","timePasswordChanged"\n'
          '"https://github.com","octocat","S3cr3t!",,"https://github.com","{9f8}","1699999999999",,"1699999999999"';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.firefoxCsv);
      final e = result.entries.first;
      expect(e.username, 'octocat');
      expect(e.urlDomain, 'github.com');
      expect(e.name, 'Github');
    });

    test('Safari CSV — maps OTPAuth to a passthrough otpauth URI', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'GitHub,https://github.com,octocat,S3cr3t!,,'
          'otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.safariCsv);
      expect(result.entries.first.totp,
          startsWith('otpauth://totp/GitHub:octocat'));
    });

    test('Bitwarden CSV', () {
      const csv =
          'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n'
          'Work,0,login,GitHub,notes,,0,https://github.com,octocat,S3cr3t!,';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.bitwardenCsv);
      final e = result.entries.first;
      expect(e.username, 'octocat');
      expect(e.folder, 'Work');
      expect(e.urlDomain, 'github.com');
    });

    test('LastPass CSV — secure note (url == http://sn) is skipped', () {
      const csv = 'url,username,password,totp,extra,name,grouping,fav\n'
          'https://github.com,octocat,S3cr3t!,,notes,GitHub,Work,0\n'
          'http://sn,,,,secure note body,My Note,Notes,0';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.lastpassCsv);
      expect(result.entries, hasLength(1));
      expect(result.entries.first.name, 'GitHub');
      expect(result.skippedCount, 1);
    });

    test('1Password 8 CSV — distinguished from Safari by Archived/Tags', () {
      const csv =
          'Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes\n'
          'GitHub,https://github.com,octocat,S3cr3t!,,false,false,dev,';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.onePasswordCsv);
      expect(result.entries.first.folder, 'dev');
    });

    test('Dashlane single CSV — bare otpSecret is wrapped into otpauth URI', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpSecret\n'
          'octocat,,,GitHub,S3cr3t!,notes,https://github.com,Dev,JBSWY3DPEHPK3PXP';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.dashlaneCsv);
      final e = result.entries.first;
      expect(e.totp, startsWith('otpauth://totp/'));
      expect(e.totp, contains('secret=JBSWY3DPEHPK3PXP'));
    });

    test('Dashlane username falls back to username2 when username is blank', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpSecret\n'
          ',fallback@acme.io,,GitHub,S3cr3t!,,https://github.com,,';
      final result = _parsed(csv);
      expect(result.entries.first.username, 'fallback@acme.io');
    });

    test('NordPass CSV', () {
      const csv =
          'name,url,username,password,note,cardholdername,cardnumber,cvc,expirydate,zipcode,folder\n'
          'GitHub,https://github.com,octocat,S3cr3t!,note,,,,,,Dev';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.nordpassCsv);
      expect(result.entries.first.folder, 'Dev');
    });

    test('NordPass card-only rows including CVC are skipped', () {
      const csv =
          'name,url,username,password,note,cardholdername,cardnumber,cvc,expirydate,zipcode,folder\n'
          'Travel card,,,,,Ada Lovelace,4242424242424242,123,12/30,00-001,Wallet';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.nordpassCsv);
      expect(result.entries, isEmpty);
      expect(result.skippedCount, 1);
    });

    test('RoboForm CSV', () {
      const csv = 'Name,Url,Login,Pwd,Note,Folder\n'
          'GitHub,https://github.com,octocat,S3cr3t!,note,Dev';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.roboformCsv);
      final e = result.entries.first;
      expect(e.username, 'octocat');
      expect(e.password, 'S3cr3t!');
    });

    test('Palladin CSV round-trips totp + folder', () {
      const csv = 'name,url,username,password,note,totp,folder\n'
          'GitHub,https://github.com,octocat,S3cr3t!,note,'
          'otpauth://totp/x?secret=ABC,Dev';
      final result = _parsed(csv);
      expect(result.format, ImportFormat.palladinCsv);
      final e = result.entries.first;
      expect(e.totp, 'otpauth://totp/x?secret=ABC');
      expect(e.folder, 'Dev');
    });

    test('row with only a password yields a null name (UI supplies fallback)',
        () {
      const csv = 'name,url,username,password,note\n'
          ',,,S3cr3t!,';
      final result = _parsed(csv);
      final e = result.entries.first;
      expect(e.name, isNull);
      expect(e.password, 'S3cr3t!');
    });

    test('unrecognised CSV yields a manual-mapping outcome', () {
      const csv = 'col_a,col_b,col_c\nfoo,bar,baz';
      final outcome = ImportEngine.parse(_bytes(csv));
      expect(outcome, isA<ImportNeedsMapping>());
      final table = (outcome as ImportNeedsMapping).table;
      expect(table.headers, ['col_a', 'col_b', 'col_c']);
    });

    test('manual mapping builds entries from chosen columns', () {
      const csv = 'col_a,col_b,col_c\nGitHub,octocat,S3cr3t!';
      final outcome = ImportEngine.parse(_bytes(csv));
      final table = (outcome as ImportNeedsMapping).table;
      final result = ImportEngine.parseWithMapping(
        table,
        const ColumnMapping(nameIndex: 0, usernameIndex: 1, passwordIndex: 2),
      );
      expect(result.format, ImportFormat.manualCsv);
      final e = result.entries.first;
      expect(e.name, 'GitHub');
      expect(e.password, 'S3cr3t!');
    });
  });

  group('JSON detection + parsing', () {
    test('Bitwarden JSON — only type==1 logins, folder resolved by id', () {
      final json = jsonEncode({
        'encrypted': false,
        'folders': [
          {'id': 'f1', 'name': 'Work'}
        ],
        'items': [
          {
            'type': 1,
            'name': 'GitHub',
            'folderId': 'f1',
            'notes': 'line1\nline2',
            'login': {
              'uris': [
                {'uri': 'https://github.com'},
                {'uri': 'https://gist.github.com'}
              ],
              'username': 'octocat',
              'password': 'S3cr3t!',
              'totp': 'otpauth://totp/x?secret=ABC'
            }
          },
          {
            'type': 2,
            'name': 'A secure note',
            'notes': 'not a login'
          }
        ]
      });
      final result = _parsed(json);
      expect(result.format, ImportFormat.bitwardenJson);
      expect(result.entries, hasLength(1));
      expect(result.skippedCount, 1);
      final e = result.entries.first;
      expect(e.folder, 'Work');
      expect(e.urlDomain, 'github.com');
      // Extra URIs are appended to notes so nothing is lost.
      expect(e.notes, contains('gist.github.com'));
    });

    test('Keeper JSON', () {
      final json = jsonEncode({
        'records': [
          {
            'title': 'GitHub',
            'login': 'octocat',
            'password': 'S3cr3t!',
            'login_url': 'https://github.com',
            'notes': 'note',
            'folders': [
              {'folder': 'Dev'}
            ]
          }
        ]
      });
      final result = _parsed(json);
      expect(result.format, ImportFormat.keeperJson);
      expect(result.entries.first.folder, 'Dev');
    });

    test('Proton Pass JSON — vaults keyed as an object, email→username', () {
      final json = jsonEncode({
        'version': '1',
        'vaults': {
          'v1': {
            'name': 'Personal',
            'items': [
              {
                'data': {
                  'metadata': {'name': 'GitHub', 'note': 'note'},
                  'content': {
                    'itemEmail': 'octo@acme.io',
                    'password': 'S3cr3t!',
                    'urls': ['https://github.com'],
                    'totpUri': 'otpauth://totp/x?secret=ABC'
                  }
                }
              }
            ]
          }
        }
      });
      final result = _parsed(json);
      expect(result.format, ImportFormat.protonPassJson);
      final e = result.entries.first;
      expect(e.username, 'octo@acme.io');
      expect(e.folder, 'Personal');
      expect(e.totp, 'otpauth://totp/x?secret=ABC');
    });

    test('Enpass JSON — per-field type, reported as its own format', () {
      final json = jsonEncode({
        'items': [
          {
            'title': 'GitHub',
            'note': 'note',
            'fields': [
              {'type': 'username', 'value': 'octocat'},
              {'type': 'password', 'value': 'S3cr3t!'},
              {'type': 'url', 'value': 'https://github.com'},
              {'type': 'totp', 'value': 'otpauth://totp/x?secret=ABC'}
            ]
          }
        ]
      });
      final result = _parsed(json);
      expect(result.format, ImportFormat.enpassJson);
      final e = result.entries.first;
      expect(e.name, 'GitHub');
      expect(e.username, 'octocat');
      expect(e.password, 'S3cr3t!');
      expect(e.urlDomain, 'github.com');
      expect(e.totp, 'otpauth://totp/x?secret=ABC');
    });

    test('Palladin JSON round-trips', () {
      final json = jsonEncode({
        'version': 1,
        'vaults': [
          {
            'name': 'Personal',
            'entries': [
              {
                'name': 'GitHub',
                'username': 'octocat',
                'password': 'S3cr3t!',
                'urlDomain': 'github.com',
                'totp': 'otpauth://totp/x?secret=ABC'
              }
            ]
          }
        ]
      });
      final result = _parsed(json);
      expect(result.format, ImportFormat.palladinJson);
      expect(result.entries.first.totp, 'otpauth://totp/x?secret=ABC');
    });
  });

  group('KeePass XML', () {
    test('parses entries and nested group path as folder', () {
      const xml = '''
<KeePassFile>
  <Root>
    <Group>
      <Name>Root</Name>
      <Group>
        <Name>Dev</Name>
        <Entry>
          <String><Key>Title</Key><Value>GitHub</Value></String>
          <String><Key>UserName</Key><Value>octocat</Value></String>
          <String><Key>Password</Key><Value ProtectInMemory="True">S3cr3t!</Value></String>
          <String><Key>URL</Key><Value>https://github.com</Value></String>
          <String><Key>Notes</Key><Value>a note</Value></String>
          <String><Key>otp</Key><Value>otpauth://totp/x?secret=ABC</Value></String>
        </Entry>
      </Group>
    </Group>
  </Root>
</KeePassFile>''';
      final result = _parsed(xml);
      expect(result.format, ImportFormat.keepassXml);
      final e = result.entries.first;
      expect(e.name, 'GitHub');
      expect(e.password, 'S3cr3t!');
      expect(e.folder, 'Root/Dev');
      expect(e.totp, 'otpauth://totp/x?secret=ABC');
    });
  });

  group('ZIP archives', () {
    test('1Password .1pux (export.data inside a ZIP)', () {
      final exportData = jsonEncode({
        'accounts': [
          {
            'vaults': [
              {
                'attrs': {'name': 'Private'},
                'items': [
                  {
                    'overview': {
                      'title': 'GitHub',
                      'url': 'https://github.com',
                      'urls': [
                        {'label': 'website', 'url': 'https://github.com'}
                      ]
                    },
                    'details': {
                      'loginFields': [
                        {'value': 'octocat', 'designation': 'username'},
                        {'value': 'S3cr3t!', 'designation': 'password'}
                      ],
                      'notesPlain': 'note',
                      'sections': [
                        {
                          'fields': [
                            {
                              'id': 'TOTP_abc',
                              'value': 'otpauth://totp/x?secret=ABC'
                            }
                          ]
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }
        ]
      });

      final archive = Archive();
      final attrs = utf8.encode('{"description":"1Password Unencrypted Export"}');
      archive.addFile(ArchiveFile('export.attributes', attrs.length, attrs));
      final data = utf8.encode(exportData);
      archive.addFile(ArchiveFile('export.data', data.length, data));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final outcome = ImportEngine.parse(zipBytes, fileName: 'export.1pux');
      expect(outcome, isA<ImportParsed>());
      final result = (outcome as ImportParsed).result;
      expect(result.format, ImportFormat.onePassword1pux);
      final e = result.entries.first;
      expect(e.name, 'GitHub');
      expect(e.username, 'octocat');
      expect(e.folder, 'Private');
      expect(e.totp, 'otpauth://totp/x?secret=ABC');
    });

    test('Dashlane ZIP (credentials.csv inside a ZIP)', () {
      const credentials =
          'username,username2,username3,title,password,note,url,category,otpSecret\n'
          'octocat,,,GitHub,S3cr3t!,,https://github.com,Dev,';
      final archive = Archive();
      final data = utf8.encode(credentials);
      archive.addFile(ArchiveFile('credentials.csv', data.length, data));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final outcome = ImportEngine.parse(zipBytes);
      expect(outcome, isA<ImportParsed>());
      final result = (outcome as ImportParsed).result;
      expect(result.entries.first.name, 'GitHub');
    });
  });

  group('unsupported files', () {
    test('empty file', () {
      expect(ImportEngine.parse(Uint8List(0)),
          isA<ImportUnsupported>().having((o) => o.reason, 'reason',
              ImportUnsupportedReason.empty));
    });

    test('binary / random bytes are unrecognised', () {
      final outcome = ImportEngine.parse(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(outcome, isA<ImportUnsupported>());
    });
  });

  group('ImportNormalizer.hostFrom — android app-credential URIs', () {
    test('derives domain from reverse-DNS package id', () {
      expect(
        ImportNormalizer.hostFrom(
            'android://zQxb6hXv1MJiC1Yyotdhi8HP@com.facebook.katana/'),
        'facebook.com',
      );
      expect(
        ImportNormalizer.hostFrom('android://hash@com.spotify.music/'),
        'spotify.com',
      );
    });

    test('rejects packages without a plausible TLD and dotless hosts', () {
      expect(ImportNormalizer.hostFrom('android://hash@localonly/'), isNull);
      expect(ImportNormalizer.hostFrom('android'), isNull);
    });
  });
}
