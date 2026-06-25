---
name: FastEndpoints typed test client
description: Use POSTAsync/GETAsync<TEndpoint, TRequest, TResponse> for tests with NodaTime DTOs
type: feedback
---

W integration testach `client.PostAsJsonAsync(...)` + `response.Content.ReadFromJsonAsync<T>()` nie używa konfiguracji FastEndpoints (bez NodaTime serializera) → `JsonException: The JSON value could not be converted to NodaTime.Instant`.

**Why:** ReadFromJsonAsync używa default `JsonSerializerOptions`. FastEndpoints rejestruje serializer z `ConfigureForNodaTime` w `Program.cs`. Typed clients (`POSTAsync<...>`, `GETAsync<...>`) z `FastEndpoints.Testing` używają zarejestrowanej konfiguracji.

**How to apply:** Zawsze w testach Vault/Identity/innych z `Instant`/`LocalDate`/etc. używaj typed clientów:
```csharp
var (response, result) = await client.POSTAsync<CreateVaultEndpoint, CreateVaultRequest, CreateVaultResponse>(req);
var (response, result) = await client.GETAsync<GetVaultEndpoint, GetVaultRequest, GetVaultResponse>(new GetVaultRequest { Id = vault.Id });
```

Wymaga `using FastEndpoints;` (extension methods na HttpClient). `FastEndpoints.Testing` jest globally w `tests/.../GlobalUsings.cs` ale samo `FastEndpoints` nie jest.

Owner reviewer flaguje surowe `client.PostAsJsonAsync` z anonim object jako silent breakage przy zmianie kontraktu requesta.
