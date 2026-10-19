-- Migration 001: Excel-ähnliche Monatszellen
CREATE TABLE IF NOT EXISTS monatswerte (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    datum DATE NOT NULL,
    kategorie_id UUID NOT NULL REFERENCES kategorien(id) ON DELETE RESTRICT,
    betrag NUMERIC(14,2) NOT NULL DEFAULT 0,
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_monatswerte_zelle UNIQUE (haushalt_id, datum, kategorie_id),
    CONSTRAINT chk_monatswerte_betrag CHECK (betrag >= 0)
);
CREATE INDEX IF NOT EXISTS idx_monatswerte_haushalt_datum ON monatswerte(haushalt_id, datum);
