---
name: Test DB cleanup
description: Stale test databases from previous runs block AutoMigration with "relation already exists"
type: feedback
---

Integration testy używają `palladin-test-vault`, `palladin-test-identity`, `jb-automatictests-palladin-hangfire` w lokalnym `postgres-vector-gis` containerze (host `127.0.0.1:5432`). `AutoMigration: true` w appsettings.Testing.json próbuje stosować migracje przy starcie.

**Why:** Jeśli test DB istnieje z poprzedniego runu z innym schematem (np. po dodaniu nowej migracji), `Vaults` table już istnieje → `42P07: relation "Vaults" already exists`.

**How to apply:** Po dodaniu migracji EF, dropnij stale test DBy:
```bash
docker exec postgres-vector-gis psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS \"palladin-test-vault\" WITH (FORCE);"
# powtórz dla -identity i jb-automatictests-palladin-hangfire
docker exec postgres-vector-gis psql -U postgres -d postgres -c "CREATE DATABASE \"palladin-test-vault\";"
docker exec postgres-vector-gis psql -U postgres -d "palladin-test-vault" -c "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS hstore;"
```

CI używa świeżego Testcontainers więc tego problemu tam nie ma — to tylko local dev.
