#!/usr/bin/env bash
# =============================================================================
# Haushaltsbuch – Installation IM Container (wird von ct/haushaltsbuch.sh gestartet)
# Installiert Docker, lädt das Haushaltsbuch von GitHub und startet es.
# =============================================================================
set -Eeuo pipefail

GH_USER="${HB_GH_USER:-River-Ghost}"
GH_REPO="${HB_GH_REPO:-Haushaltsbuch}"
GH_BRANCH="${HB_GH_BRANCH:-main}"
TARBALL_URL="${HB_TARBALL_URL:-https://github.com/${GH_USER}/${GH_REPO}/archive/refs/heads/${GH_BRANCH}.tar.gz}"
APP_DIR="${HB_APP_DIR:-/opt/haushaltsbuch}"
export DEBIAN_FRONTEND=noninteractive

if [[ -t 1 ]]; then RD=$'\033[31m' GN=$'\033[32m' BL=$'\033[36m' CL=$'\033[0m'; else RD='' GN='' BL='' CL=''; fi
msg_info() { printf '%s[ .. ]%s %s\n' "$BL" "$CL" "$*"; }
msg_ok()   { printf '%s[ OK ]%s %s\n' "$GN" "$CL" "$*"; }
msg_err()  { printf '%s[FEHL]%s %s\n' "$RD" "$CL" "$*" >&2; }
die()      { msg_err "$*"; exit 1; }

have_compose() { docker compose version >/dev/null 2>&1; }

install_base() {
  msg_info "Aktualisiere Paketlisten und installiere Grundpakete …"
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl openssl tar gzip >/dev/null
  msg_ok "Grundpakete installiert."
}

# Docker: zuerst die Debian-Pakete (haben sich in unprivilegierten LXC-Containern bewährt),
# danach als Rückfall das offizielle Docker-Repository.
install_docker() {
  if command -v docker >/dev/null 2>&1 && have_compose; then msg_ok "Docker ist bereits installiert."; return; fi
  msg_info "Installiere Docker …"
  if apt-get install -y -qq docker.io docker-compose-plugin >/dev/null 2>&1 && have_compose; then
    msg_ok "Docker aus den Debian-Paketen installiert."
  elif apt-get install -y -qq docker.io docker-compose >/dev/null 2>&1 && have_compose; then
    msg_ok "Docker aus den Debian-Paketen installiert."
  else
    msg_info "Debian-Pakete reichen nicht aus, verwende das offizielle Docker-Repository …"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      >/etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
    have_compose || die "Docker Compose konnte nicht installiert werden."
    msg_ok "Docker aus dem offiziellen Repository installiert."
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do docker info >/dev/null 2>&1 && return 0; sleep 1; done
  die "Der Docker-Dienst startet nicht. Prüfe, ob der Container 'Nesting' aktiviert hat (Optionen > Funktionen)."
}

download_app() {
  msg_info "Lade das Haushaltsbuch von GitHub …"
  mkdir -p "$APP_DIR"
  curl -fsSL "$TARBALL_URL" | tar -xz --strip-components=1 -C "$APP_DIR" \
    || die "Download fehlgeschlagen: ${TARBALL_URL}"
  [[ -f "$APP_DIR/docker-compose.yml" ]] || die "Im Archiv fehlt docker-compose.yml. Ist das Repository vollständig hochgeladen?"
  msg_ok "Version $(tr -d '[:space:]' <"$APP_DIR/VERSION" 2>/dev/null || echo '?') heruntergeladen."
}

make_env() {
  cd "$APP_DIR"
  if [[ -f .env ]]; then msg_ok ".env ist bereits vorhanden."; return; fi
  local dbpw secret
  dbpw="$(openssl rand -hex 24)"; secret="$(openssl rand -hex 32)"
  # Wird bewusst direkt geschrieben und nicht aus .env.example kopiert: Punkt-Dateien gehen
  # beim Hochladen auf GitHub leicht verloren, die Installation soll davon nicht abhängen.
  (
    umask 077
    cat >.env <<ENV
POSTGRES_DB=haushaltsbuch
POSTGRES_USER=haushaltsbuch
POSTGRES_PASSWORD=${dbpw}
APP_SECRET=${secret}
APP_NAME=Haushaltsbuch
ENV
  )
  chmod 600 .env
  msg_ok "Zugangsdaten für die Datenbank erzeugt (.env)."
}

start_app() {
  cd "$APP_DIR"
  msg_info "Baue und starte die Anwendung (der erste Start dauert 1 bis 3 Minuten) …"
  docker compose up -d --build >/dev/null
  for _ in $(seq 1 90); do
    if curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1; then msg_ok "Das Haushaltsbuch antwortet."; return 0; fi
    sleep 2
  done
  docker compose ps || true
  docker compose logs --tail=40 || true
  die "Das Haushaltsbuch antwortet nach 3 Minuten nicht. Die letzten Logzeilen stehen oben."
}

install_helpers() {
  cat >/usr/local/bin/update <<'UPD'
#!/usr/bin/env bash
# Aktualisiert das Haushaltsbuch auf die neueste Version von GitHub.
exec bash /opt/haushaltsbuch/scripts/self-update.sh "$@"
UPD
  chmod +x /usr/local/bin/update
  cat >/etc/motd <<'MOTD'

  Haushaltsbuch
  -------------
  update                      Auf die neueste Version aktualisieren
  bash /opt/haushaltsbuch/scripts/backup.sh   Datenbank-Backup erstellen
  cd /opt/haushaltsbuch && docker compose logs -f   Logs ansehen

MOTD
  msg_ok "Befehl 'update' eingerichtet."
}

main() {
  install_base
  install_docker
  download_app
  make_env
  start_app
  install_helpers
}

# Nur ausführen, wenn nicht per "source" geladen (funktioniert auch bei bash -c).
if ! (return 0 2>/dev/null); then main "$@"; fi
