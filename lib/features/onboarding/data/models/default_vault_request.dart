/// DTO sent to `POST /api/account/default-vault` during onboarding.
///
/// The endpoint creates the user's initial "Personal" vault. [name] is
/// the localized vault name supplied by the caller so the data layer has
/// no dependency on BuildContext. [wrappedVK] is the base64-encoded
/// sealed-box ciphertext matching the same format used by
/// `POST /api/vaults`.
class DefaultVaultRequest {
  const DefaultVaultRequest({
    required this.name,
    required this.wrappedVK,
    this.description,
    this.icon,
    this.color,
  });

  final String name;
  final String wrappedVK;
  final String? description;
  final String? icon;
  final String? color;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      'wrappedVK': wrappedVK,
    };
  }
}
