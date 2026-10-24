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

### Update über mehrere Versionen auf einmal

Ein Update installiert immer den kompletten neuesten Stand und spielt alle Datenbankänderungen, die dem Container noch fehlen,
der Reihe nach ein. Man kann also Versionen überspringen, z. B. direkt von 0.5.1 auf die neueste Version. Die Daten bleiben erhalten,
und vorher wird automatisch eine Sicherung angelegt.

Bei Installationen **älter als 0.5.7** meldet der Befehl `update` am Ende eventuell `unexpected EOF while looking for matching`.
Das Update ist dann trotzdem vollständig durchgelaufen. Die Meldung vermeidest du, indem du zuerst das neue Update-Skript holst:

```bash
curl -fsSL https://raw.githubusercontent.com/River-Ghost/Haushaltsbuch/main/scripts/self-update.sh -o /opt/haushaltsbuch/scripts/self-update.sh && update
```

Der Weg über den Installer auf dem Proxmox-Host („Vorhandenen Container aktualisieren“) macht das automatisch.

## Fehlersuche

| Meldung | Ursache und Lösung |
|---|---|
| „Konnte … /VERSION nicht laden“ | Der Proxmox-Host hat kein Internet, oder das GitHub-Repository ist nicht öffentlich bzw. nicht vollständig hochgeladen. |
| Container startet nicht, Meldung `sync_wait: 34 An error occurred in another process` und ein Template mit `arm64` im Namen | Das Template passt nicht zur Prozessor-Architektur (Intel/AMD braucht `amd64`). Mit Version 0.5.5 behoben. Den unfertigen Container löschen (`pct destroy <CT-ID> --purge`) und den Installer erneut starten. Weitere Diagnose: `lxc-start -n <CT-ID> -F -l DEBUG -o /tmp/lxc.log` und die ERROR-Zeilen in der Datei lesen. |
| „Im Container ist nach 2 Minuten kein Internet erreichbar“ | Bridge, VLAN, Gateway oder DNS falsch. Im erweiterten Modus prüfen. |
| „Der Docker-Dienst startet nicht“ | Beim Container muss unter Optionen → Funktionen **Nesting** aktiviert sein (der Installer setzt das). |
| Container-Start mit Fehler zu `sysctl net.ipv4.ip_unprivileged_port_start` | Bekannte Unverträglichkeit neuerer runc-Versionen in unprivilegierten LXC. Dann bitte die Logausgabe melden. |
| „Das Haushaltsbuch antwortet nach 3 Minuten nicht“ | Die letzten Logzeilen stehen direkt darüber. Weitere Logs: `cd /opt/haushaltsbuch && docker compose logs --tail=100`. |

Bricht die Installation ab, bietet das Skript an, den unfertigen Container wieder zu löschen.

## Sicherung auf einen anderen Rechner kopieren

Eine Sicherung ist nur dann hilfreich, wenn sie **nicht** auf demselben Datenträger liegt wie das Haushaltsbuch.
Die folgenden Befehle laufen auf dem Proxmox-Host (statt `100` die eigene CT-ID verwenden).

**Frische Sicherung erstellen und direkt auf einen anderen Rechner im Netz schicken** (schont den Datenträger, es wird
nichts zwischengespeichert; `benutzer@rechner` ist ein Rechner mit SSH):

```bash
pct exec 100 -- bash -c 'cd /opt/haushaltsbuch && docker compose exec -T datenbank sh -c "pg_dump -U \$POSTGRES_USER -d \$POSTGRES_DB -Fc"' \
  | ssh benutzer@rechner 'cat > haushaltsbuch_$(date +%F).dump'
```

**Vorhandene Sicherungen aus dem Container holen:**

```bash
pct exec 100 -- ls -lt /opt/haushaltsbuch/backups          # zeigt die Sicherungen, neueste zuerst
pct pull 100 /opt/haushaltsbuch/backups/<Dateiname> /root/<Dateiname>
```

Danach die Datei vom Host auf einen anderen Rechner kopieren (z. B. mit `scp` oder WinSCP).

## Wiederherstellen (z. B. auf neuer Hardware)

1. Haushaltsbuch wie oben neu installieren (Einzeiler auf dem neuen Proxmox-Host).
2. Sicherung in den neuen Container kopieren: `pct push <CT-ID> /pfad/zur/haushaltsbuch.dump /root/haushaltsbuch.dump`
3. Im Container einspielen:

```bash
bash /opt/haushaltsbuch/scripts/restore.sh /root/haushaltsbuch.dump
```

Das Skript prüft die Datei, legt eine Sicherheitskopie des bisherigen Standes an, ersetzt die Daten, holt fehlende
Datenbankänderungen nach und startet das Haushaltsbuch. Es funktioniert auch mit Sicherungen älterer Versionen.

