import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConsentActivation {
  const ConsentActivation(this.noticeVersion, this.revision);
  final String noticeVersion;
  final int revision;
}

/// Contains only an installation's explicit activation of a notice/epoch.
/// No keys, tokens, anonymous landing identity or analytics session is stored.
class ConsentActivationStore {
  ConsentActivationStore({Future<Directory> Function()? cacheDirectory})
    : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _cacheDirectory;

  Future<File> _file(String userId) async {
    final cache = await _cacheDirectory();
    // Cache files are not migrated by normal iOS backups. Losing this file is
    // safe: analytics stays off until this installation is explicitly activated.
    // Encode the filename independently of the authenticated API's ID format.
    final name = base64Url.encode(utf8.encode(userId));
    return File('${cache.path}/consent-activation/$name.json');
  }

  Future<ConsentActivation?> read(String userId) async {
    try {
      final file = await _file(userId);
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map ||
          value['noticeVersion'] is! String ||
          value['revision'] is! int ||
          value['revision'] <= 0) {
        return null;
      }
      return ConsentActivation(
        value['noticeVersion'] as String,
        value['revision'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, ConsentActivation? activation) async {
    final file = await _file(userId);
    if (activation == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'noticeVersion': activation.noticeVersion,
        'revision': activation.revision,
      }),
      flush: true,
    );
  }
}
