---
name: read-write-context-convention
description: Read-modify-write endpointy ładują encję z write contextu, nie read; bez jawnego domainContext.Update()
metadata:
  type: feedback
---

W endpointach typu read-modify-write encję ładuj z **write contextu** (`{Module}DbWriteContext`), nie z read contextu. Po mutacji wywołaj tylko `domainContext.CommitAsync()` — NIE wołaj `domainContext.Update(entity)`.

**Why:** `domainContext.Update(...)` (czyli `DbContext.Update`) oznacza WSZYSTKIE kolumny jako dirty i UPDATE przepisuje niezmienione kolumny. Encja załadowana z write contextu jest śledzona przez change tracker, więc `SaveChanges` emituje minimalny UPDATE tylko zmienionych kolumn. Dodatkowo ładowanie z read contextu + zapis przez write context to niespójność (read/write split).

**How to apply:** Dotyczy każdego HTTP endpointu który czyta encję, mutuje ją i zapisuje (np. RevokeApiKey, ActivateApiKey, UpdateOrg, DeleteApiKey). Precedens: `Identity/Features/SetupAccount.cs` — wstrzykuje `IdentityDbWriteContext`. Dla czystych odczytów (queries) nadal używaj read contextu. Potwierdzone w review PR #14 (CVT-38).

Powiązane: [[no-repository-pattern]] — DomainContext do zapisów (dispatchuje eventy), ReadContext do odczytów.
