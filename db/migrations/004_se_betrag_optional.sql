-- Migration 004: Sonstige Einnahmen ohne Betrag erlauben
--
-- "Wiederholen" kopiert nur die Bezeichnung in die Folgemonate. Der Betrag bleibt leer
-- (gespeichert als 0) und wird später eingetragen. Betrag 0 zählt in keiner Summe mit.
ALTER TABLE sonstige_einnahmen DROP CONSTRAINT IF EXISTS chk_se_betrag;
ALTER TABLE sonstige_einnahmen ADD CONSTRAINT chk_se_betrag CHECK (betrag >= 0);
