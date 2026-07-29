/// Public, non-secret asset returned by the Palladin catalog.
class PublicAsset {
  const PublicAsset({
    required this.id,
    required this.type,
    required this.name,
    required this.revision,
    required this.deliveryUrl,
  });

  final String id;
  final String type;
  final String name;
  final int revision;

  /// Complete URL selected by the server for the current environment.
  final Uri deliveryUrl;

  String get reference => 'public-asset:$id';
}
