-- Migration 006: Notizen an Zellen der Jahresübersicht (wie Kommentare in Excel)
--
-- Eine Notiz gehört zu einem Posten (Kategorie) und einem Monat, z. B. "Siemens 5 Stk, 492,00 €"
-- an der Zelle "Aktienkauf / Februar". Das Datum ist der Monatserste, wie bei monatswerte.
CREATE TABLE IF NOT EXISTS zellnotizen (
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    kategorie_id UUID NOT NULL REFERENCES kategorien(id) ON DELETE CASCADE,
    datum DATE NOT NULL,
    notiz VARCHAR(500) NOT NULL,
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (haushalt_id, kategorie_id, datum),
    CONSTRAINT chk_zellnotiz_monat CHECK (EXTRACT(DAY FROM datum) = 1),
    CONSTRAINT chk_zellnotiz_text CHECK (length(trim(notiz)) > 0)
);
