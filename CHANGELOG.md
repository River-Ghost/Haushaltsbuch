# Änderungen

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
