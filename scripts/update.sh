#!/bin/bash
set -euo pipefail
cd /opt/haushaltsbuch

echo "Haushaltsbuch – Update"
echo "===================="

mkdir -p backups
STAMP="$(date +%Y%m%d_%H%M%S)"
docker compose up -d datenbank >/dev/null
until docker compose exec -T datenbank pg_isready -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" >/dev/null 2>&1; do sleep 2; done
docker compose exec -T datenbank sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "backups/vor-update_${STAMP}.dump"
echo "Backup erstellt: backups/vor-update_${STAMP}.dump"

bash scripts/migrate.sh
docker compose build --pull web
docker compose up -d

docker image prune -f >/dev/null 2>&1 || true

echo
echo "Update abgeschlossen."
docker compose ps
