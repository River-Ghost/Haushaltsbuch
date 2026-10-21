#!/usr/bin/env bash
# =============================================================================
# Haushaltsbuch – Update auf die neueste Version von GitHub (läuft im Container)
#   update            Aktualisiert, falls eine neuere Version vorhanden ist
#   update --force    Spielt die aktuelle Version erneut ein
# Vor dem Update wird automatisch ein Datenbank-Backup in backups/ angelegt.
# =============================================================================
set -Eeuo pipefail

GH_USER="${HB_GH_USER:-River-Ghost}"
GH_REPO="${HB_GH_REPO:-Haushaltsbuch}"
GH_BRANCH="${HB_GH_BRANCH:-main}"
TARBALL_URL="${HB_TARBALL_URL:-https://github.com/${GH_USER}/${GH_REPO}/archive/refs/heads/${GH_BRANCH}.tar.gz}"
APP_DIR="${HB_APP_DIR:-/opt/haushaltsbuch}"
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# Das ganze Skript steckt in einer Funktion und endet mit "exit": Bash liest die Funktion
# vollständig ein, bevor sie läuft. So ist es unkritisch, dass dieses Skript beim Update
# durch eine neue Fassung ersetzt wird.
main() {
  [[ -f "$APP_DIR/docker-compose.yml" ]] || { echo "Haushaltsbuch ist nicht in ${APP_DIR} installiert." >&2; return 1; }
  cd "$APP_DIR"
  local old new tmp
  old="$(tr -d '[:space:]' <VERSION 2>/dev/null || echo unbekannt)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo "Haushaltsbuch – Update"
  echo "======================"
  echo "Installierte Version: ${old}"
  curl -fsSL "$TARBALL_URL" | tar -xz --strip-components=1 -C "$tmp" \
    || { echo "Download fehlgeschlagen: ${TARBALL_URL}" >&2; return 1; }
  [[ -f "$tmp/docker-compose.yml" && -f "$tmp/VERSION" ]] || { echo "Das heruntergeladene Archiv ist unvollständig." >&2; return 1; }
  new="$(tr -d '[:space:]' <"$tmp/VERSION")"
  echo "Verfügbare Version:   ${new}"

  if [[ "$old" == "$new" && "${1:-}" != "--force" ]]; then
    echo "Das Haushaltsbuch ist bereits aktuell. (Erneut einspielen: update --force)"
    return 0
  fi

  # .env und backups/ sind nicht im Archiv und bleiben unverändert.
  cp -a "$tmp"/. "$APP_DIR"/
  # Die Versionsnummer wird erst nach einem erfolgreichen Update geschrieben. Bricht das Update
  # ab, erkennt der nächste Aufruf von "update", dass es noch nicht abgeschlossen ist.
  printf '%s\n' "$old" > "$APP_DIR/VERSION"
  mkdir -p "$APP_DIR/scripts"
  chmod +x "$APP_DIR"/scripts/*.sh 2>/dev/null || true

  cat >/usr/local/bin/update <<'UPD'
#!/usr/bin/env bash
exec bash /opt/haushaltsbuch/scripts/self-update.sh "$@"
UPD
  chmod +x /usr/local/bin/update

  if ! bash "$APP_DIR/scripts/update.sh"; then
    echo >&2
    echo "Das Update ist fehlgeschlagen. Vorhandene Datenbank-Sicherungen liegen in ${APP_DIR}/backups/." >&2
    echo "Nach der Fehlerbehebung (z. B. 'docker compose ps' prüfen) einfach erneut 'update' eingeben." >&2
    return 1
  fi

  for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
      cp "$tmp/VERSION" "$APP_DIR/VERSION"
      echo
      echo "Update von ${old} auf ${new} erfolgreich."
      return 0
    fi
    sleep 2
  done
  echo "Das Haushaltsbuch antwortet nach dem Update nicht. Logs: cd ${APP_DIR} && docker compose logs --tail=50" >&2
  return 1
}

main "$@"
exit $?
