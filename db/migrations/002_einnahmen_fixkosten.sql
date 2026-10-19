-- Migration 002: Einnahmen, feste Ausgaben und Sparen/Vermögen (Jahresübersicht)
--
-- Die Beträge liegen weiterhin in "monatswerte" (Datum = 1. des Monats), daher
-- ist keine Tabellenänderung nötig. Die Posten selbst sind Einträge in "kategorien"
-- mit den Gruppen 'Einnahmen', 'Fixe Ausgaben' und 'Sparen/Vermögen'.
--
-- Version 0.2.x hat vier Beispiel-Posten angelegt, die in der Oberfläche nie
-- benutzbar waren. Sie werden entfernt (nur wenn sie nirgends verwendet werden),
-- damit die App beim nächsten Start die neue Startliste anlegen kann.
DELETE FROM kategorien k
WHERE k.gruppe IN ('Einnahmen', 'Fixe Ausgaben')
  AND k.bezeichnung IN ('Gehalt', 'Sonstige Einnahmen', 'Wohnen', 'Versicherungen')
  AND NOT EXISTS (SELECT 1 FROM monatswerte m WHERE m.kategorie_id = k.id)
  AND NOT EXISTS (SELECT 1 FROM buchungspositionen b WHERE b.kategorie_id = k.id)
  AND NOT EXISTS (SELECT 1 FROM regelmaessige_vorgaenge r WHERE r.kategorie_id = k.id);
