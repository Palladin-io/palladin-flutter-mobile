import '../../../../../config/env_config.dart';
import '../../../domain/entities/entry_share.dart';
import 'entry_share_secrets.dart';

final class EntryShareLinkService {
  EntryShareLinkService(EnvConfig config) : _origin = _resolve(config);
  final Uri _origin;

  String get displayOrigin => _origin.origin;

  String create({required String shareId, required String fragment}) {
    final secrets = EntryShareSecrets.fromFragment(fragment);
    secrets.dispose();
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(shareId) ||
        !RegExp(
          r'^#v=1&key=[A-Za-z0-9_-]{43}&access=[A-Za-z0-9_-]{43}$',
        ).hasMatch(fragment)) {
      throw const EntryShareException(EntryShareErrorKind.invalidLink);
    }
    return '${_origin.origin}/share/$shareId$fragment';
  }

  static Uri _resolve(EnvConfig config) {
    const invalid = EntryShareException(EntryShareErrorKind.invalidLink);
    final uri = Uri.tryParse(config.sharingWebOrigin);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        config.sharingWebOrigin.trim() != config.sharingWebOrigin ||
        (uri.scheme != 'https' && !(config.isLocal && uri.scheme == 'http'))) {
      throw invalid;
    }
    if (!config.isLocal) {
      final staging =
          Uri.parse(config.apiBaseUrl).host == 'api.stage.palladin.io';
      if (uri.port != 443 ||
          (staging && uri.host != 'stage.palladin.io') ||
          (!staging &&
              (uri.host == 'stage.palladin.io' ||
                  !(uri.host == 'palladin.io' ||
                      uri.host.endsWith('.palladin.io'))))) {
        throw invalid;
      }
    }
    return uri;
  }
}
