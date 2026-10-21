-- Migration 005: Tagesnotizen ("Die teuersten Einkaufsposten" in der Monatsansicht)
--
-- Pro Tag ein freier Text (wie die verbundene Zelle B:E im Excel-Monatsblatt).
CREATE TABLE IF NOT EXISTS tagesnotizen (
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    datum DATE NOT NULL,
    notiz VARCHAR(300) NOT NULL,
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (haushalt_id, datum),
    CONSTRAINT chk_tagesnotiz_text CHECK (length(trim(notiz)) > 0)
);
