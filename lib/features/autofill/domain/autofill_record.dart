class AutoFillRecord {
  const AutoFillRecord({
    required this.id,
    required this.label,
    required this.username,
    required this.password,
    required this.domains,
  });

  final String id;
  final String label;
  final String username;
  final String password;
  final List<String> domains;

  Map<String, Object> toPlatformMap() => {
    'id': id,
    'label': label,
    'username': username,
    'password': password,
    'domains': domains,
  };
}
