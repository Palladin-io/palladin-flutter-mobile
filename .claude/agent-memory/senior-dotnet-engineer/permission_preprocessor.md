---
name: Permission preprocessor pattern
description: Generic FastEndpoints preprocessor for bitwise permission checks instead of inline HasFlag
type: feedback
---

W Palladin backend uprawnienia oparte o `[Flags] Permission` enum (Core.Security/Permission.cs). Zamiast inline `permissions.HasFlag(Permission.X)` w każdym handlerze, używaj generycznego preprocessora.

**Why:** Owner explicitly requested generic mechanism in PR #10 review (#3183568302, #3183793213). HasFlag boxuje argumenty na każde wywołanie, manual check duplikuje 401/403 logikę.

**How to apply:** W `Endpoint.Configure()` dodaj `PreProcessors(new RequirePermissionPreProcessor<TRequest>(Permission.X))` (instancja, bo trzeba przekazać konkretny Permission). PreProcessor:
- weryfikuje claims (UserId + OrganizationId nie null) → 401
- robi `(granted & required) == required` (bez boxowania) → 403
- jeśli OK puszcza dalej do HandleAsync gdzie można użyć `User.GetUserId()!.Value`

Plik: `src/core/Palladin.Core.Security/RequirePermissionPreProcessor.cs`. Wymaga FastEndpoints PackageRef w Core.Security.csproj.

Endpointy które tego używają: CreateVault (VaultCreate), Update/DeleteVault (VaultManage). GetVault celowo nie używa preprocessora — robi membership check zamiast permission.
