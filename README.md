<p align="center"><img src="app/static/icon-192.png" width="96" alt="Haushaltsbuch"></p>

# Haushaltsbuch

Web-Haushaltsbuch nach dem Vorbild einer Excel-Vorlage. Es läuft in einem LXC-Container unter Proxmox
(FastAPI + PostgreSQL in Docker) und ist von mehreren Geräten im Heimnetz erreichbar.
Keine Bankanbindung, kein Excel-Import, keine Belegbilder.

## Installation auf Proxmox (ein Befehl)

Auf dem Proxmox-Host in der Shell als `root` eingeben:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/River-Ghost/Haushaltsbuch/main/ct/haushaltsbuch.sh)"
```

Das Skript fragt nach „Standard“ oder „Erweitert“, legt den Container an, installiert Docker und das
Haushaltsbuch und zeigt am Ende die Adresse der Weboberfläche an (`http://<IP>:8080`).
Details und Fehlersuche: [INSTALLATION.md](INSTALLATION.md).

## Aktualisieren

Im Container (Konsole in Proxmox) einfach eingeben:

```bash
update
```

Alternativ den Installationsbefehl auf dem Proxmox-Host erneut starten und
„Vorhandenen Container aktualisieren“ wählen. Vor jedem Update wird automatisch ein
Datenbank-Backup in `/opt/haushaltsbuch/backups/` angelegt. Deine Daten und Zugangsdaten bleiben erhalten.

## Funktionen

**Monat** – Excel-ähnliche Tagesmatrix für die flexiblen Ausgaben (10 Kategorien als Spalten),
automatische Tages-, Kategorie- und Monatssummen, Monatswechsel vor/zurück.

**Jahresübersicht** – entspricht dem Excel-Blatt „GESAMT“:

- Blöcke *Einnahmen*, *Feste Ausgaben*, *Sparen / Vermögen* und *Flexible Ausgaben* (aus der Monatsansicht)
- Beträge pro Posten und Monat direkt in der Tabelle eintragen
- **⇢ Ausfüllen nach rechts:** Wert der zuletzt bearbeiteten Zelle bis Dezember übernehmen
- Summen je Block, Gesamteinnahmen, Gesamtausgaben, Saldo, Jahressumme und Prozentanteile
- Posten hinzufügen (`+ Posten`), umbenennen (✎), ausblenden (×) und über „Ausgeblendet“ wieder einblenden (↺)

**Sonstige Einnahmen** (entspricht dem Excel-Blatt „SE“) – freie Einträge pro Monat mit Bezeichnung und
Betrag, z. B. Rückzahlungen, Dividenden oder Zinsen. Beginnt die Bezeichnung mit „Div.“ oder „Dividende“,
zählt der Betrag als Dividende, beginnt sie mit „Zins“, als Zinsen, alles andere als Sonstiges.

- **⇢ Wiederholen:** Ein Eintrag lässt sich monatlich, vierteljährlich, halbjährlich oder jährlich bis Dezember
  (dieses oder nächstes Jahr) wiederholen. Eine Vorschau zeigt die Zielmonate. Es entstehen normale Einträge,
  die einzeln änderbar sind. Monate, in denen der Eintrag schon existiert, werden übersprungen.
- Die Jahrestabelle zeigt Dividenden, Zinsen, Sonstiges und „Dividenden + Zinsen“ je Monat.
- Die Monatssummen erscheinen als schreibgeschützte Zeile „Sonstiges (SE)“ in der Jahresübersicht
  und in den Einnahmen der Monatskarten.

## Tastatur

| Ansicht | Enter | Shift+Enter | Tab | ↑ / ↓ |
|---|---|---|---|---|
| Monat | ein Feld nach rechts (am Zeilenende in die nächste Zeile) | ein Feld nach links | ein Feld nach rechts | eine Zeile höher / tiefer |
| Jahresübersicht | eine Zeile tiefer (am Spaltenende in die nächste Spalte) | eine Zeile höher | ein Feld nach rechts | eine Zeile höher / tiefer |
| Sonstige Einnahmen | Bezeichnung → Betrag → nächste Zeile | rückwärts | ein Feld nach rechts | – |

Beim Weiterspringen wird der Wert automatisch gespeichert.

## Auf dem Handy

Die Seite hat ein Icon und ein Web-App-Manifest. Im Browser des Handys lässt sich das Haushaltsbuch über
„Zum Startbildschirm hinzufügen“ ablegen. Über reines HTTP entsteht dabei eine Verknüpfung mit dem Icon, die
im Browser öffnet. Als eigenständige App ohne Browserleiste lässt es sich installieren, sobald die Seite über
HTTPS erreichbar ist (z. B. über einen vorgeschalteten Nginx mit Zertifikat).

## Proxmox-Speicher und Backups

Der Container liegt ausschließlich auf einem von Proxmox verwalteten Storage. Es gibt keinen separaten
Host-Mount für Anwendungs- oder PostgreSQL-Daten, daher lässt sich der komplette Container über die normalen
Proxmox-Backups sichern und wiederherstellen. Details stehen in [PROXMOX_BACKUP.md](PROXMOX_BACKUP.md).

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `ct/haushaltsbuch.sh` | Installer, läuft auf dem Proxmox-Host (legt den Container an) |
| `install/haushaltsbuch-install.sh` | läuft im Container (Docker, Download, Start) |
| `scripts/self-update.sh` | der Befehl `update` im Container |
| `scripts/update.sh`, `migrate.sh`, `backup.sh` | Backup, Datenbankmigrationen, Neustart |
| `app/` | Anwendung (FastAPI, `index.html`, Icons in `static/`) |
| `db/` | Datenbankschema und nummerierte Migrationen |
| `docker-compose.yml` | Anwendung und PostgreSQL |
| `nginx/` | Beispielkonfiguration für einen vorgeschalteten Nginx |
