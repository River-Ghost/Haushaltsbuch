#!/bin/bash
# =============================================================================
# Haushaltsbuch – Datenbank aus einer Sicherung wiederherstellen
#
#   bash /opt/haushaltsbuch/scripts/restore.sh /pfad/zur/sicherung.dump
#
# Geeignet für Sicherungen aus backup.sh bzw. den automatischen "vor-update_*.dump"
# (Format "custom") sowie für reine SQL-Dateien (*.sql).
# ACHTUNG: Alle aktuellen Daten in der Datenbank werden durch die Sicherung ersetzt.
# Vorher wird eine Sicherheitskopie des aktuellen Standes in backups/ angelegt.
# =============================================================================
set -euo pipefail
cd /opt/haushaltsbuch

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Aufruf: bash scripts/restore.sh /pfad/zur/sicherung.dump" >&2
  echo "Vorhandene Sicherungen in diesem Container:" >&2
  ls -1t backups/*.dump 2>/dev/null | head -n 10 | sed 's/^/  /' >&2 || true
  exit 1
fi

DB_EXEC=(docker compose exec -T datenbank)
CUSTOM=1
[[ "$FILE" == *.sql ]] && CUSTOM=0

echo "Haushaltsbuch – Wiederherstellung"
echo "================================="
echo "Sicherung: $FILE ($(du -h "$FILE" | cut -f1))"

docker compose up -d datenbank >/dev/null
until "${DB_EXEC[@]}" pg_isready -U "${POSTGRES_USER:-haushaltsbuch}" -d "${POSTGRES_DB:-haushaltsbuch}" >/dev/null 2>&1; do sleep 2; done

# Erst prüfen, dann überschreiben: eine kaputte Datei darf die vorhandenen Daten nicht zerstören.
if ((CUSTOM)); then
  if ! "${DB_EXEC[@]}" pg_restore -l < "$FILE" >/dev/null 2>&1; then
    echo "Die Datei ist keine gültige PostgreSQL-Sicherung. Es wurde nichts verändert." >&2
    exit 1
  fi
  echo "Die Sicherung ist lesbar: $("${DB_EXEC[@]}" pg_restore -l < "$FILE" | grep -c 'TABLE DATA') Tabellen mit Daten."
fi

if [[ "${HB_RESTORE_YES:-}" != "ja" ]]; then
  read -r -p "Alle aktuellen Daten durch diese Sicherung ersetzen? Zum Bestätigen 'ja' eingeben: " ANSWER
  [[ "$ANSWER" == "ja" ]] || { echo "Abgebrochen. Es wurde nichts verändert."; exit 1; }
fi

mkdir -p backups
STAMP="$(date +%Y%m%d_%H%M%S)"
"${DB_EXEC[@]}" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "backups/vor-restore_${STAMP}.dump"
echo "Sicherheitskopie des bisherigen Standes: backups/vor-restore_${STAMP}.dump"

docker compose stop web >/dev/null 2>&1 || true

echo "Spiele die Sicherung ein …"
if ((CUSTOM)); then
  # --clean/--if-exists ersetzt die vorhandenen Tabellen. Einzelne Warnungen sind unkritisch.
  "${DB_EXEC[@]}" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-privileges' < "$FILE" \
    || echo "Hinweis: pg_restore hat Warnungen gemeldet (meist harmlos, z. B. nicht vorhandene Objekte beim Aufräumen)."
else
  "${DB_EXEC[@]}" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < "$FILE"
fi

# Sicherungen älterer Versionen enthalten neuere Tabellen noch nicht: fehlende Migrationen nachholen.
bash scripts/migrate.sh
docker compose up -d

echo
echo "Wiederherstellung abgeschlossen. Bitte die Weboberfläche öffnen und die Daten prüfen."
