-- Migration 003: Sonstige Einnahmen (Excel-Blatt "SE")
--
-- Freie Einzelbuchungen pro Monat (Rückzahlungen, Erstattungen, Dividenden, Zinsen ...).
-- Beginnt die Bezeichnung mit "Div." oder "Dividende", zählt sie als Dividende, beginnt sie
-- mit "Zins", als Zinsen, alles andere als Sonstiges. Die Art wird beim Lesen aus der
-- Bezeichnung abgeleitet und nicht gespeichert.
CREATE TABLE IF NOT EXISTS sonstige_einnahmen (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    monat DATE NOT NULL,
    bezeichnung VARCHAR(120) NOT NULL,
    betrag NUMERIC(14,2) NOT NULL,
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_se_monat CHECK (EXTRACT(DAY FROM monat) = 1),
    CONSTRAINT chk_se_betrag CHECK (betrag > 0),
    CONSTRAINT chk_se_bezeichnung CHECK (length(trim(bezeichnung)) > 0)
);
CREATE INDEX IF NOT EXISTS idx_se_haushalt_monat ON sonstige_einnahmen(haushalt_id, monat, erstellt_am);

-- Die Startliste von 0.3.0/0.3.1 enthielt die Einnahme-Posten "Dividenden", "Zinsen" und
-- "Sonstige Einnahmen". Dafür gibt es jetzt die Ansicht "Sonstige Einnahmen". Nicht
-- benutzte Posten werden entfernt, damit nichts doppelt gezählt werden kann.
DELETE FROM kategorien k
WHERE k.gruppe = 'Einnahmen'
  AND k.bezeichnung IN ('Dividenden', 'Zinsen', 'Sonstige Einnahmen')
  AND NOT EXISTS (SELECT 1 FROM monatswerte m WHERE m.kategorie_id = k.id)
  AND NOT EXISTS (SELECT 1 FROM buchungspositionen b WHERE b.kategorie_id = k.id)
  AND NOT EXISTS (SELECT 1 FROM regelmaessige_vorgaenge r WHERE r.kategorie_id = k.id);
