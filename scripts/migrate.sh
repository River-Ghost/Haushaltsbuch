#!/bin/bash
set -euo pipefail
cd /opt/haushaltsbuch

mkdir -p /opt/haushaltsbuch/backups

docker compose up -d datenbank >/dev/null

echo "Warte auf PostgreSQL …"
until docker compose exec -T datenbank pg_isready -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" >/dev/null 2>&1; do sleep 2; done

docker compose exec -T datenbank psql -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" -v ON_ERROR_STOP=1 -c 'CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW());'

for file in db/migrations/*.sql; do
  [[ -f "$file" ]] || continue
  version="$(basename "$file" .sql)"
  if docker compose exec -T datenbank psql -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" -Atc "SELECT 1 FROM schema_migrations WHERE version='${version}'" | grep -q '^1$'; then
    continue
  fi
  echo "Wende Migration ${version} an …"
  docker compose exec -T datenbank psql -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" -v ON_ERROR_STOP=1 < "$file"
  docker compose exec -T datenbank psql -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" -v ON_ERROR_STOP=1 -c "INSERT INTO schema_migrations(version) VALUES ('${version}') ON CONFLICT DO NOTHING;"
done

echo "Datenbankmigrationen abgeschlossen."
