#!/bin/bash
set -euo pipefail
cd /opt/haushaltsbuch; mkdir -p backups; set -a; source .env; set +a; STAMP=$(date +%Y-%m-%d_%H-%M-%S)
docker compose exec -T datenbank pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom > "backups/haushaltsbuch_${STAMP}.dump"
find backups -type f -name '*.dump' -mtime +30 -delete
echo "Backup erstellt: backups/haushaltsbuch_${STAMP}.dump"
