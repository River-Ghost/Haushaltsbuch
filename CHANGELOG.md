# Änderungen

## 0.5.5
- **Behoben (Installer):** Auf Proxmox-Hosts, die Templates mehrerer Architekturen auflisten, wählte der Installer das alphabetisch letzte Template und damit `arm64`, auch auf Intel/AMD-Rechnern. Der Container ließ sich dann nicht starten (`sync_wait: 34 An error occurred in another process`). Jetzt wird nur ein Template der Architektur des Hosts gewählt (amd64 oder arm64), `pct create` setzt `--arch`, und bei einem Startfehler zeigt der Installer die Fehlerzeilen aus dem LXC-Protokoll.
- Neu (Monat): Spalte „Teuerste Einkäufe“ direkt nach dem Datum, ein freies Textfeld pro Tag (wie „Die teuersten Einkaufsposten“ im Excel-Monatsblatt, bis 300 Zeichen). Leeren des Feldes löscht die Notiz. Enter springt aus der Notiz in die erste Kategorie, beim Zeilenwechsel wird das Notizfeld übersprungen. Migration 005 legt die Tabelle `tagesnotizen` an.
- Neu: `scripts/restore.sh` stellt die Datenbank aus einer Sicherung wieder her (Format `.dump` aus backup.sh oder den automatischen „vor-update“-Sicherungen, auch `.sql`). Es prüft die Datei vor dem Überschreiben, legt eine Sicherheitskopie des bisherigen Standes an und holt fehlende Migrationen nach, sodass auch Sicherungen älterer Versionen funktionieren.
- Geändert: Der Befehl `update` schreibt die neue Versionsnummer erst nach einem erfolgreichen Update. Bricht ein Update ab, wird es beim nächsten Aufruf erneut ausgeführt und endet mit einer verständlichen Meldung. Wirkt ab dem Update, das dieses Skript installiert.

## 0.5.4
- Neu: Das Seitenmenü lässt sich ein- und ausklappen (Schalter unten im Menü). Eingeklappt zeigt es nur Symbole, die Breite sinkt von 220 auf 66 px. Der Zustand wird im Browser gemerkt.
- Neu: Alle Menüpunkte haben ein Symbol und einen Tooltip. Auf schmalen Bildschirmen ersetzen die Symbole die bisherigen „•“-Punkte.
- Geändert: Kürzere Menünamen: „Monat“, „Jahr“ (bisher „Jahresübersicht“) und „Nebeneinnahmen“ (bisher „Sonstige Einnahmen“). Überschrift und Hinweistexte wurden angepasst.

## 0.5.3
- Geändert (Jahr): Die Zeilen Gesamteinnahmen, Gesamtausgaben und Saldo stehen jetzt oben direkt unter den Monatsnamen und bleiben beim Scrollen fixiert.
- Neu (Jahr): Die Kennzahlen-Karten über der Tabelle sind ausblendbar (Button „Kennzahlen anzeigen/ausblenden“, Standard: ausgeblendet). Die Wahl wird im Browser gemerkt. Die Tabelle erhält dadurch mehr Platz.
- Geändert (Jahr): Die vier Abschnitte (Einnahmen, Feste Ausgaben, Sparen / Vermögen, Flexible Ausgaben) sind farblich getrennt: farbiger Streifen links, farbige Oberkante und getönter Kopf und Summenzeile, ohne zusätzliche Zeilen.
- Geändert (Jahr): Lange Postennamen werden nicht mehr gekürzt. Die Knöpfe ⇢ ✎ × erscheinen erst beim Darüberfahren über der Zeile (auf Touch-Geräten bleiben sie sichtbar). „+ Posten“ und „Ausgeblendet (n)“ stehen neben dem Abschnittstitel.
- Geändert (Jahr): Leere Posten zeigen in der Prozent-Spalte nichts mehr statt „0 %“.

## 0.5.2
- Geändert (Monat): Die Datumsspalte nutzt eine Festbreiten-Schrift für die Ziffern, der Wochentag steht in einer eigenen Spalte. Alle Beträge verwenden gleich breite Ziffern, damit Dezimalstellen genau untereinander stehen.
- Geändert (Monat): Die Karten „Feste Ausgaben & Sparen“ und „Flexible Ausgaben“ werden rot dargestellt.
- Geändert (Monat): Der untere Bereich mit Monatssummen und Hinweis entfällt. Die Summen stehen in der GESAMT-Zeile der Tabelle.
- Geändert (Jahr): Werte der Einnahmen grün, Werte der Ausgaben (feste Ausgaben, Sparen/Vermögen, flexible Ausgaben) rot. Der Saldo ist schwarz und nur bei negativem Wert rot, in der Tabelle wie in der Karte.

## 0.5.1
- Neu: Hinweis im README, in der Installationsanleitung und im Installer, dass das Projekt mit Hilfe von KI erstellt wurde und nicht supportet wird.
- Geändert: „Wiederholen“ in den Sonstigen Einnahmen kopiert nur noch die Bezeichnung. Der Betrag bleibt leer und wird später eingetragen.
- Neu: Migration 004 erlaubt für Sonstige Einnahmen den Betrag 0 („noch offen“). Ein geleertes Betragsfeld setzt den Betrag auf 0, statt zurückgesetzt zu werden.

## 0.5.0
- Neu: Installation per Einzeiler direkt von GitHub (`ct/haushaltsbuch.sh`) mit Dialogen (Standard/Erweitert), DHCP als Standard, automatischer Wahl von CT-ID, Storage und Template und Aufräum-Angebot bei Fehlern.
- Neu: Befehl `update` im Container und Update-Modus im Installer. Vor jedem Update wird ein Datenbank-Backup angelegt.
- Neu: Sonstige Einnahmen: Eintrag wiederholen (monatlich, vierteljährlich, halbjährlich, jährlich) mit Vorschau der Zielmonate.
- Neu: Icon (Favicon, Apple-Touch-Icon, Android/Maskable) und Web-App-Manifest. Das Haushaltsbuch lässt sich als App zum Startbildschirm hinzufügen.
- Geändert: In der Monatsmatrix springt Enter ein Feld nach rechts (Shift+Enter nach links). Jahresübersicht und Sonstige Einnahmen sind unverändert.
- Entfernt: `scripts/install-lxc.sh` und `scripts/install-app.sh`, ersetzt durch den neuen Installer.

## 0.4.1
- Neu: Enter springt wie in Excel eine Zeile tiefer (Monat, Jahresübersicht), Shift+Enter eine Zeile höher, ↑/↓ funktionieren ebenfalls. Am Spaltenende geht es oben in der nächsten Spalte weiter.
- Neu: In den Sonstigen Einnahmen springt Enter von der Bezeichnung zum Betrag und danach in die nächste Zeile. Dabei wird gespeichert.

## 0.4.0
- Neu: Ansicht „Sonstige Einnahmen“ (Excel-Blatt SE) im linken Menü, mit Monatsliste und Jahrestabelle für Dividenden, Zinsen und Sonstiges. Die Art wird aus der Bezeichnung abgeleitet.
- Neu: Die Summen fließen als schreibgeschützte Zeile „Sonstiges (SE)“ in die Jahresübersicht und in die Einnahmen der Monatskarten ein.
- Neu: Migration 003 legt die Tabelle `sonstige_einnahmen` an (auch in `01_schema.sql` für Neuinstallationen) und entfernt die ungenutzten Posten „Dividenden“, „Zinsen“ und „Sonstige Einnahmen“ aus der Startliste von 0.3.x, damit nichts doppelt gezählt wird. Benutzte Posten bleiben erhalten.
- Geändert: Die Startliste der Einnahmen enthält nur noch Gehalt 1, Gehalt 2 und Kindergeld.

## 0.3.1
- Geändert: Kompakteres Layout. Die Monatsmatrix passt auf einem Full-HD-Bildschirm ohne Scrollen, die GESAMT-Zeile bleibt unten sichtbar. Die Zeilenhöhe steht zentral in `--row-h` (app/index.html).
- Neu: Ausgeblendete Posten lassen sich über den Button „Ausgeblendet (n)“ im jeweiligen Block der Jahresübersicht wieder einblenden.

## 0.3.0
- Neu: Jahresübersicht mit Einnahmen, festen Ausgaben, Sparen/Vermögen und flexiblen Ausgaben, Saldo und Prozentanteilen.
- Neu: „Ausfüllen nach rechts“ (⇢) für feste Ausgaben und Einnahmen.
- Neu: Posten hinzufügen, umbenennen, ausblenden und wieder einblenden.
- Neu: Startliste an Posten aus der Excel-Vorlage (alles änderbar).
- Neu: Migration 002 entfernt die in 0.2.x angelegten, nie benutzbaren Beispiel-Posten.
- Behoben: Port 8080 war nur auf 127.0.0.1 im LXC gebunden, die Weboberfläche war von außen nicht erreichbar.
- Behoben: Monatsansicht baut die Tabelle beim Speichern nicht mehr neu auf. Mit Tab springt der Fokus nun zuverlässig in die nächste Zelle.
- Behoben: Beträge mit Punkt als Dezimaltrenner (47.82) werden nicht mehr als 4782 gelesen.
- Behoben: Einnahmen und feste Ausgaben werden in der Monatsmatrix nicht mehr als flexible Ausgaben mitgezählt.
- Geändert: Die Version steht im Code (nicht mehr in der .env) und kann nach einem Update nicht veralten.
- Entfernt: Strom- und Heizkostenrechner (wird nicht benötigt).

## 0.2.1-test
- Erste lauffähige Testversion mit Monatsmatrix.
