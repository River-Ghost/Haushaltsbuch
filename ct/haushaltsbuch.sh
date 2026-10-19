#!/usr/bin/env bash
# =============================================================================
# Haushaltsbuch – Proxmox-LXC-Installer
#
# Einzeiler (auf dem Proxmox-Host als root ausführen):
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/River-Ghost/Haushaltsbuch/main/ct/haushaltsbuch.sh)"
#
# Das Skript legt einen LXC-Container an, installiert Docker und das Haushaltsbuch
# (FastAPI + PostgreSQL) und zeigt am Ende die Adresse der Weboberfläche an.
# Erneut gestartet, kann es einen bestehenden Container aktualisieren.
# =============================================================================
set -Eeuo pipefail

APP="Haushaltsbuch"
GH_USER="${HB_GH_USER:-River-Ghost}"
GH_REPO="${HB_GH_REPO:-Haushaltsbuch}"
GH_BRANCH="${HB_GH_BRANCH:-main}"
RAW_BASE="${HB_RAW_BASE:-https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${GH_BRANCH}}"
REPO_URL="https://github.com/${GH_USER}/${GH_REPO}"
APP_PORT=8080
CREATED=0
CTID=""

# --- Ausgabe ----------------------------------------------------------------
if [[ -t 1 ]]; then RD=$'\033[31m' GN=$'\033[32m' YW=$'\033[33m' BL=$'\033[36m' CL=$'\033[0m'; else RD='' GN='' YW='' BL='' CL=''; fi
msg_info() { printf '%s[ .. ]%s %s\n' "$BL" "$CL" "$*"; }
msg_ok()   { printf '%s[ OK ]%s %s\n' "$GN" "$CL" "$*"; }
msg_warn() { printf '%s[WARN]%s %s\n' "$YW" "$CL" "$*"; }
msg_err()  { printf '%s[FEHL]%s %s\n' "$RD" "$CL" "$*" >&2; }

# --- Dialoge (whiptail, sonst einfache Texteingabe) -------------------------
USE_TUI=0
if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then USE_TUI=1; fi
BACKTITLE="${APP} – Proxmox LXC"

cancelled() { echo; msg_warn "Abgebrochen."; exit 0; }

ask() { # ask VARIABLE "Text" "Vorgabe"
  local __v="$1" __t="$2" __d="${3:-}" __r
  if ((USE_TUI)); then
    __r=$(whiptail --backtitle "$BACKTITLE" --title "$APP" --inputbox "$__t" 11 68 "$__d" 3>&1 1>&2 2>&3) || cancelled
  else
    read -r -p "$__t [$__d]: " __r || cancelled
    __r="${__r:-$__d}"
  fi
  printf -v "$__v" '%s' "$__r"
}

choose() { # choose VARIABLE "Text" tag1 "Beschreibung1" tag2 "Beschreibung2" ...
  local __v="$1" __t="$2" __r; shift 2
  if ((USE_TUI)); then
    __r=$(whiptail --backtitle "$BACKTITLE" --title "$APP" --menu "$__t" 19 78 9 "$@" 3>&1 1>&2 2>&3) || cancelled
  else
    local -a tags=(); local i=1
    echo; echo "$__t"
    while (($# >= 2)); do tags+=("$1"); printf '  %d) %s\n' "$i" "$2"; i=$((i + 1)); shift 2; done
    local n; read -r -p "Auswahl [1]: " n || cancelled; n="${n:-1}"
    [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#tags[@]})) || { msg_err "Ungültige Auswahl."; exit 1; }
    __r="${tags[n-1]}"
  fi
  printf -v "$__v" '%s' "$__r"
}

confirm() { # confirm "Text"  -> 0 = ja
  if ((USE_TUI)); then
    whiptail --backtitle "$BACKTITLE" --title "$APP" --yesno "$1" 22 76
    return $?
  fi
  local r; printf '%b\n' "$1"; read -r -p "(j/n) [j]: " r || return 1
  [[ "${r:-j}" =~ ^[JjYy]$ ]]
}

# --- Fehlerbehandlung -------------------------------------------------------
fail_cleanup() {
  local ec="${1:-1}"
  trap - ERR
  msg_err "Die Installation ist fehlgeschlagen (Code ${ec})."
  if ((CREATED)) && [[ -n "$CTID" ]]; then
    if confirm "Den unfertigen Container ${CTID} jetzt wieder löschen?\n\n(Bei Nein bleibt er zur Fehlersuche bestehen: pct enter ${CTID})"; then
      pct stop "$CTID" >/dev/null 2>&1 || true
      pct destroy "$CTID" --purge >/dev/null 2>&1 && msg_ok "Container ${CTID} wurde gelöscht." || msg_warn "Container ${CTID} konnte nicht gelöscht werden."
    else
      msg_warn "Container ${CTID} bleibt bestehen. Konsole: pct enter ${CTID}"
    fi
  fi
  exit "$ec"
}
die() { msg_err "$*"; fail_cleanup 1; }
trap 'fail_cleanup $?' ERR

# --- Prüfungen --------------------------------------------------------------
check_env() {
  [[ $EUID -eq 0 ]] || { msg_err "Bitte als root auf dem Proxmox-Host ausführen."; exit 1; }
  local c
  for c in pct pveam pvesm curl; do
    command -v "$c" >/dev/null 2>&1 || { msg_err "'$c' wurde nicht gefunden. Dieses Skript gehört auf einen Proxmox-VE-Host."; exit 1; }
  done
  msg_info "Prüfe Verbindung zu GitHub …"
  APP_VERSION="$(curl -fsSL --max-time 15 "${RAW_BASE}/VERSION" 2>/dev/null | tr -d '[:space:]')" || true
  [[ -n "$APP_VERSION" ]] || { msg_err "Konnte ${RAW_BASE}/VERSION nicht laden. Internetzugang des Hosts prüfen und ob das Repository öffentlich ist: ${REPO_URL}"; exit 1; }
  msg_ok "${APP} ${APP_VERSION} gefunden."
}

# --- Hilfsfunktionen für Standardwerte --------------------------------------
valid_ctid() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 100 && 10#$1 <= 999999999)); }
ctid_free() { ! pct status "$1" >/dev/null 2>&1 && [[ ! -e "/etc/pve/qemu-server/$1.conf" ]]; }
valid_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_cidr() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]; }

next_ctid() {
  local id; id="$(pvesh get /cluster/nextid 2>/dev/null || true)"
  if valid_ctid "$id" && ctid_free "$id"; then printf '%s' "$id"; return; fi
  for id in $(seq 100 9999); do ctid_free "$id" && { printf '%s' "$id"; return; }; done
  die "Keine freie CT-ID gefunden."
}

storages() { pvesm status -content "$1" 2>/dev/null | awk 'NR>1 && $1 != "" {print $1}'; }
pick_storage() { # pick_storage content bevorzugt
  local s list; list="$(storages "$1")"
  if grep -qx "$2" <<<"$list"; then printf '%s' "$2"; else head -n1 <<<"$list"; fi
}
default_bridge() {
  local b; b="$(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^vmbr' | head -n1 || true)"
  printf '%s' "${b:-vmbr0}"
}

set_defaults() {
  CTID="$(next_ctid)"; HOSTNAME_CT="haushaltsbuch"
  CORES=2; RAM=2048; SWAP=512; DISK=10
  BRIDGE="$(default_bridge)"; NETMODE="dhcp"; IP=""; GATEWAY=""; VLAN=""; DNS=""
  CONTAINER_STORAGE="$(pick_storage rootdir local-lvm)"
  TEMPLATE_STORAGE="$(pick_storage vztmpl local)"
  TAGS="haushaltsbuch"
  [[ -n "$CONTAINER_STORAGE" ]] || die "Kein Storage für Container-Laufwerke (rootdir) gefunden."
  [[ -n "$TEMPLATE_STORAGE" ]] || die "Kein Storage für Container-Templates (vztmpl) gefunden."
}

advanced_settings() {
  local v
  while true; do
    ask v "Container-ID (CT-ID):" "$CTID"
    if valid_ctid "$v" && ctid_free "$v"; then CTID="$v"; break; fi
    msg_warn "CT-ID ${v} ist ungültig oder schon vergeben."
    ((USE_TUI)) && whiptail --msgbox "CT-ID ${v} ist ungültig oder schon vergeben." 8 56 || true
  done
  ask HOSTNAME_CT "Hostname:" "$HOSTNAME_CT"
  ask CORES "CPU-Kerne:" "$CORES"
  ask RAM "Arbeitsspeicher in MiB:" "$RAM"
  ask DISK "Festplatte in GB:" "$DISK"
  ask BRIDGE "Netzwerk-Bridge:" "$BRIDGE"
  choose NETMODE "IP-Adresse:" dhcp "Automatisch per DHCP (empfohlen, im Router reservieren)" static "Feste IP-Adresse"
  if [[ "$NETMODE" == static ]]; then
    while true; do ask IP "IPv4-Adresse mit Netzmaske (z. B. 192.168.178.50/24):" "${IP:-192.168.178.50/24}"; valid_cidr "$IP" && break; msg_warn "Bitte im Format 192.168.178.50/24 angeben."; done
    while true; do ask GATEWAY "Gateway:" "${GATEWAY:-192.168.178.1}"; valid_ipv4 "$GATEWAY" && break; msg_warn "Bitte z. B. 192.168.178.1 angeben."; done
  fi
  ask VLAN "VLAN-ID (leer = keine):" "$VLAN"
  ask DNS "DNS-Server (leer = Standard des Hosts):" "$DNS"
  local -a opts=() s
  while read -r s; do [[ -n "$s" ]] && opts+=("$s" "Storage"); done < <(storages rootdir)
  ((${#opts[@]})) && choose CONTAINER_STORAGE "Speicherort für das Container-Laufwerk:" "${opts[@]}"
  ask TAGS "Proxmox-Tags (durch Komma getrennt):" "$TAGS"
}

validate() {
  [[ "$CORES" =~ ^[0-9]+$ ]] && ((CORES >= 1)) || die "CPU-Kerne müssen eine Zahl ab 1 sein."
  [[ "$RAM" =~ ^[0-9]+$ ]] && ((RAM >= 1024)) || die "Arbeitsspeicher muss mindestens 1024 MiB betragen."
  [[ "$DISK" =~ ^[0-9]+$ ]] && ((DISK >= 6)) || die "Die Festplatte muss mindestens 6 GB groß sein."
  [[ -z "$VLAN" || "$VLAN" =~ ^[0-9]+$ ]] || die "VLAN-ID muss eine Zahl sein."
  [[ "$HOSTNAME_CT" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || die "Ungültiger Hostname."
}

summary() {
  local net="DHCP"; [[ "$NETMODE" == static ]] && net="${IP} via ${GATEWAY}"
  confirm "Folgender Container wird angelegt:\n
  CT-ID:        ${CTID}
  Hostname:     ${HOSTNAME_CT}
  Netzwerk:     ${net} (${BRIDGE}${VLAN:+, VLAN ${VLAN}})
  CPU / RAM:    ${CORES} Kerne / ${RAM} MiB
  Festplatte:   ${DISK} GB auf ${CONTAINER_STORAGE}
  Version:      ${APP} ${APP_VERSION}\n
Installation starten?" || cancelled
}

# --- Container anlegen ------------------------------------------------------
find_template() {
  msg_info "Aktualisiere die Template-Liste …"
  pveam update >/dev/null 2>&1 || msg_warn "pveam update schlug fehl, verwende vorhandene Liste."
  TEMPLATE="$(pveam available --section system | awk '$2 ~ /^debian-13-standard/ {print $2}' | sort -V | tail -n1)"
  [[ -n "$TEMPLATE" ]] || TEMPLATE="$(pveam available --section system | awk '$2 ~ /^debian-12-standard/ {print $2}' | sort -V | tail -n1)"
  [[ -n "$TEMPLATE" ]] || die "Kein Debian-13- oder Debian-12-Template gefunden."
  if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk '{print $1}' | grep -qx "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"; then
    msg_info "Lade ${TEMPLATE} herunter …"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null || die "Template-Download fehlgeschlagen."
  fi
  msg_ok "Template ${TEMPLATE} bereit."
}

create_container() {
  local net0="name=eth0,bridge=${BRIDGE}"
  if [[ "$NETMODE" == static ]]; then net0+=",ip=${IP},gw=${GATEWAY}"; else net0+=",ip=dhcp"; fi
  [[ -n "$VLAN" ]] && net0+=",tag=${VLAN}"
  ROOT_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
  [[ -n "$ROOT_PASSWORD" ]] || die "Konnte kein Passwort erzeugen."
  local -a args=(
    "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
    --hostname "$HOSTNAME_CT" --cores "$CORES" --memory "$RAM" --swap "$SWAP"
    --rootfs "${CONTAINER_STORAGE}:${DISK}" --net0 "$net0" --password "$ROOT_PASSWORD"
    --unprivileged 1 --features "nesting=1,keyctl=1" --onboot 1 --tags "$TAGS"
  )
  [[ -n "$DNS" ]] && args+=(--nameserver "$DNS")
  msg_info "Erstelle Container ${CTID} …"
  pct create "${args[@]}" >/dev/null
  CREATED=1
  msg_ok "Container ${CTID} wurde erstellt."
  pct start "$CTID"
  msg_info "Warte auf das Netzwerk im Container …"
  local i
  for i in $(seq 1 60); do
    pct exec "$CTID" -- getent hosts github.com >/dev/null 2>&1 && break
    [[ $i -eq 60 ]] && die "Im Container ist nach 2 Minuten kein Internet erreichbar. Bridge, VLAN, Gateway und DNS prüfen."
    sleep 2
  done
  msg_ok "Netzwerk ist bereit."
}

container_ip() {
  local ip=""
  ip="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [[ -n "$ip" ]] || ip="$(pct exec "$CTID" -- ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  printf '%s' "$ip"
}

run_install() {
  local tmp; tmp="$(mktemp)"
  curl -fsSL "${RAW_BASE}/install/haushaltsbuch-install.sh" -o "$tmp" || die "Konnte das Installationsskript nicht von GitHub laden."
  pct push "$CTID" "$tmp" /root/haushaltsbuch-install.sh --perms 0755
  rm -f "$tmp"
  msg_info "Installiere Docker und ${APP} im Container (das dauert einige Minuten) …"
  pct exec "$CTID" -- env HB_GH_USER="$GH_USER" HB_GH_REPO="$GH_REPO" HB_GH_BRANCH="$GH_BRANCH" HB_TARBALL_URL="${HB_TARBALL_URL:-}" \
    bash /root/haushaltsbuch-install.sh
  pct exec "$CTID" -- rm -f /root/haushaltsbuch-install.sh
}

finish_install() {
  IP_ADDR="$(container_ip)"; [[ -n "$IP_ADDR" ]] || IP_ADDR="<IP-des-Containers>"
  local cred="/root/haushaltsbuch-${CTID}.creds"
  umask 077
  cat >"$cred" <<CRED
Haushaltsbuch – Zugangsdaten
============================
Erstellt:     $(date '+%Y-%m-%d %H:%M:%S %z')
Container:    ${CTID} (${HOSTNAME_CT})
Weboberfläche: http://${IP_ADDR}:${APP_PORT}
Root-Passwort des Containers: ${ROOT_PASSWORD}

Die Datenbank-Zugangsdaten liegen nur im Container: /opt/haushaltsbuch/.env
CRED
  chmod 600 "$cred"
  pct set "$CTID" --description "<div align='center'><a href='${REPO_URL}' target='_blank' rel='noopener noreferrer'><img src='${RAW_BASE}/app/static/icon-192.png' style='width:81px;height:81px;'/></a>
<h2 style='font-size: 24px; margin: 16px 0;'>${APP}</h2>
<p>Weboberfläche auf Port ${APP_PORT} &middot; Update: im Container <code>update</code> eingeben</p>
<p><a href='${REPO_URL}' target='_blank' rel='noopener noreferrer'>GitHub</a></p></div>" >/dev/null 2>&1 || true
  echo
  echo "=============================================================="
  msg_ok "${APP} ${APP_VERSION} ist installiert."
  echo "=============================================================="
  echo "  Weboberfläche:   http://${IP_ADDR}:${APP_PORT}"
  echo "  Container:       ${CTID} (${HOSTNAME_CT})"
  echo "  Zugangsdaten:    ${cred}"
  echo "  Konsole:         pct enter ${CTID}"
  echo "  Aktualisieren:   im Container 'update' eingeben oder dieses Skript erneut starten"
  [[ "$NETMODE" == dhcp ]] && echo "  Hinweis:         Reserviere die IP-Adresse im Router, damit sie sich nicht ändert."
  echo "  Für Nginx:       Proxy-Ziel http://${IP_ADDR}:${APP_PORT}"
  echo
}

# --- Aktualisieren ----------------------------------------------------------
update_existing() {
  local id found=""
  for id in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
    if pct config "$id" 2>/dev/null | grep -qE '^tags:.*haushaltsbuch'; then found="$id"; break; fi
  done
  ask CTID "CT-ID des Haushaltsbuch-Containers:" "$found"
  valid_ctid "$CTID" && pct status "$CTID" >/dev/null 2>&1 || { msg_err "Container ${CTID} gibt es nicht."; exit 1; }
  pct status "$CTID" | grep -q running || { msg_err "Container ${CTID} läuft nicht. Bitte zuerst starten: pct start ${CTID}"; exit 1; }
  pct exec "$CTID" -- test -f /opt/haushaltsbuch/docker-compose.yml || { msg_err "In Container ${CTID} ist kein Haushaltsbuch installiert."; exit 1; }
  local tmp; tmp="$(mktemp)"
  curl -fsSL "${RAW_BASE}/scripts/self-update.sh" -o "$tmp" || { msg_err "Konnte das Update-Skript nicht laden."; exit 1; }
  pct push "$CTID" "$tmp" /opt/haushaltsbuch/scripts/self-update.sh --perms 0755
  rm -f "$tmp"
  CREATED=0
  pct exec "$CTID" -- env HB_GH_USER="$GH_USER" HB_GH_REPO="$GH_REPO" HB_GH_BRANCH="$GH_BRANCH" HB_TARBALL_URL="${HB_TARBALL_URL:-}" \
    bash /opt/haushaltsbuch/scripts/self-update.sh
}

# --- Hauptablauf ------------------------------------------------------------
main() {
  echo
  echo "  ${APP} – Installation auf Proxmox"
  echo "  ${REPO_URL}"
  echo
  check_env
  local mode
  choose mode "Was möchtest du tun?  (Version ${APP_VERSION})" \
    install  "Neu installieren (empfohlen, sinnvolle Standardwerte)" \
    advanced "Neu installieren mit erweiterten Einstellungen" \
    update   "Vorhandenen Container aktualisieren" \
    quit     "Beenden"
  case "$mode" in
    quit) exit 0 ;;
    update) update_existing; exit 0 ;;
    install) set_defaults ;;
    advanced) set_defaults; advanced_settings ;;
  esac
  validate
  summary
  find_template
  create_container
  run_install
  finish_install
}

# Läuft main nur, wenn das Skript nicht per "source" geladen wurde (funktioniert auch bei bash -c "$(curl ...)").
if ! (return 0 2>/dev/null); then main "$@"; fi
