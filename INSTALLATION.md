# Installation auf Proxmox

> Hinweis: Dieses Projekt wurde mit Hilfe von KI erstellt und wird nicht supportet. Nutzung auf eigene Verantwortung, siehe README.

## 1. Befehl ausführen

In der Proxmox-Weboberfläche den Host auswählen, **Shell** öffnen und eingeben:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/River-Ghost/Haushaltsbuch/main/ct/haushaltsbuch.sh)"
```

## 2. Modus wählen

- **Neu installieren (empfohlen):** Alles Nötige wird automatisch gewählt: freie CT-ID, Hostname
  `haushaltsbuch`, DHCP, 2 CPU-Kerne, 2 GB RAM, 10 GB Festplatte, passender Storage.
- **Neu installieren mit erweiterten Einstellungen:** CT-ID, Hostname, Ressourcen, Bridge, feste IP,
  VLAN, DNS, Storage und Tags frei wählbar.
- **Vorhandenen Container aktualisieren:** siehe unten.

Nach der Zusammenfassung mit „Ja“ bestätigen. Die Installation dauert einige Minuten (Docker und die
Anwendung werden geladen und gebaut).

## 3. Fertig

Am Ende steht die Adresse der Weboberfläche da, z. B. `http://192.168.178.50:8080`.

- Das Root-Passwort des Containers liegt in `/root/haushaltsbuch-<CT-ID>.creds` auf dem Proxmox-Host.
- Die Datenbank-Zugangsdaten werden zufällig erzeugt und liegen nur im Container in `/opt/haushaltsbuch/.env`.
- Bei DHCP die IP-Adresse im Router reservieren, damit sie sich nicht ändert.
- Ein vorhandener Nginx kann später davor geschaltet werden (Proxy-Ziel `http://<IP>:8080`,
  Beispiel in `nginx/haushaltsbuch.conf.example`).

## Aktualisieren

Im Container (in Proxmox: Container auswählen → **Konsole**):

```bash
update
```

Oder auf dem Proxmox-Host den Installationsbefehl erneut ausführen und
„Vorhandenen Container aktualisieren“ wählen. Das Skript erkennt den Container am Tag `haushaltsbuch`.
Ein Datenbank-Backup wird vorher automatisch angelegt (`/opt/haushaltsbuch/backups/`).

## Fehlersuche

| Meldung | Ursache und Lösung |
|---|---|
| „Konnte … /VERSION nicht laden“ | Der Proxmox-Host hat kein Internet, oder das GitHub-Repository ist nicht öffentlich bzw. nicht vollständig hochgeladen. |
| „Im Container ist nach 2 Minuten kein Internet erreichbar“ | Bridge, VLAN, Gateway oder DNS falsch. Im erweiterten Modus prüfen. |
| „Der Docker-Dienst startet nicht“ | Beim Container muss unter Optionen → Funktionen **Nesting** aktiviert sein (der Installer setzt das). |
| Container-Start mit Fehler zu `sysctl net.ipv4.ip_unprivileged_port_start` | Bekannte Unverträglichkeit neuerer runc-Versionen in unprivilegierten LXC. Dann bitte die Logausgabe melden. |
| „Das Haushaltsbuch antwortet nach 3 Minuten nicht“ | Die letzten Logzeilen stehen direkt darüber. Weitere Logs: `cd /opt/haushaltsbuch && docker compose logs --tail=100`. |

Bricht die Installation ab, bietet das Skript an, den unfertigen Container wieder zu löschen.
