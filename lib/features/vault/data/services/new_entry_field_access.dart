import '../../domain/entities/vault_plaintext.dart';

/// One policy for ordinary creation and received independent copies. This
/// creates visibility metadata, not an Agent grant or permission to deliver.
Map<String, AgentFieldAccess> newEntryFieldAccess(
  VaultEntryType type,
  MemberSecretContent content, {
  bool discoverDescription = false,
  bool exposeUsername = false,
  bool exposeDomain = false,
}) => {
  'memberLabel': AgentFieldAccess.never,
  'agentLabel': AgentFieldAccess.discovery,
  'description': discoverDescription
      ? AgentFieldAccess.discovery
      : AgentFieldAccess.never,
  'icon': AgentFieldAccess.never,
  'color': AgentFieldAccess.never,
  'entryType': AgentFieldAccess.discovery,
  for (final id in content.fieldValues().keys)
    id: switch ((type, id)) {
      (VaultEntryType.credential, 'credential.username') =>
        exposeUsername
            ? AgentFieldAccess.discovery
            : AgentFieldAccess.onGrantValue,
      (VaultEntryType.credential, 'credential.urlDomain') =>
        exposeDomain ? AgentFieldAccess.discovery : AgentFieldAccess.never,
      (VaultEntryType.credential, 'credential.totp') =>
        AgentFieldAccess.onGrantDerived,
      (VaultEntryType.script, 'script.interpreter') =>
        AgentFieldAccess.discovery,
      (VaultEntryType.script, 'script.source' || 'script.refs') =>
        AgentFieldAccess.onGrantRuntime,
      (VaultEntryType.creditCard, 'creditCard.billingAddress') =>
        (content as CreditCardSecretContent).billingAddress == null
            ? AgentFieldAccess.never
            : AgentFieldAccess.onGrantRuntime,
      (VaultEntryType.creditCard, 'notes') => AgentFieldAccess.never,
      (VaultEntryType.creditCard, _) => AgentFieldAccess.onGrantRuntime,
      _ => AgentFieldAccess.onGrantValue,
    },
  for (final field in content.customFields)
    field.fieldId: field.kind == 'totp'
        ? AgentFieldAccess.onGrantDerived
        : type == VaultEntryType.creditCard
        ? AgentFieldAccess.onGrantRuntime
        : field.includeInMemberIndex
        ? AgentFieldAccess.discovery
        : type == VaultEntryType.script
        ? AgentFieldAccess.onGrantRuntime
        : AgentFieldAccess.onGrantValue,
};
