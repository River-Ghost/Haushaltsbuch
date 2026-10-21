-- Haushaltsbuch – schlankes PostgreSQL-Datenbankschema
-- Version: 2.0
-- Sprache: Deutsch
-- Ziel: lokale Installation auf Proxmox
--
-- Bewusst nicht enthalten:
--   * Kassenbon-/Belegdateien
--   * OCR
--   * Excel-Importverwaltung
--   * separate Dokumentenspeicherung
--
-- OCR/Scanner kann später ergänzt werden, ohne die Grundstruktur
-- des Haushaltsbuchs ändern zu müssen.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE buchungsart AS ENUM (
    'EINNAHME',
    'AUSGABE',
    'ERSTATTUNG',
    'UEBERTRAGUNG',
    'INVESTITION'
);

CREATE TYPE kategorienart AS ENUM (
    'EINNAHME',
    'AUSGABE',
    'REGELMAESSIG',
    'SPAREN',
    'INVESTITION'
);

CREATE TYPE regelmaessige_art AS ENUM (
    'FIXKOSTEN',
    'SPAREN',
    'INVESTITION'
);

CREATE TYPE rhythmus AS ENUM (
    'EINMALIG',
    'MONATLICH',
    'VIERTELJAEHRLICH',
    'HALBJAEHRLICH',
    'JAEHRLICH'
);

CREATE TYPE buchungsstatus AS ENUM (
    'ENTWURF',
    'BESTAETIGT',
    'STORNIERT'
);

CREATE TYPE quelle AS ENUM (
    'MANUELL',
    'SYSTEM'
);

CREATE TYPE kontenart AS ENUM (
    'GIROKONTO',
    'TAGESGELD',
    'BARGELD',
    'KREDITKARTE',
    'DEPOT',
    'SONSTIGES'
);

CREATE TYPE vermoegensart AS ENUM (
    'TAGESGELD',
    'DEPOT',
    'P2P_ANLAGE',
    'KRYPTOWAEHRUNG',
    'SONSTIGE_ANLAGE'
);

CREATE TYPE objektart AS ENUM (
    'FAHRZEUG',
    'WOHNUNG',
    'VERSICHERUNG',
    'SONSTIGES'
);

CREATE TYPE benutzerrolle AS ENUM (
    'ADMIN',
    'BENUTZER'
);

-- ============================================================
-- HAUSHALT
-- ============================================================

CREATE TABLE haushalte (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    waehrung CHAR(3) NOT NULL DEFAULT 'EUR',
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_haushalte_name
        CHECK (length(trim(name)) > 0),

    CONSTRAINT chk_haushalte_waehrung
        CHECK (waehrung ~ '^[A-Z]{3}$')
);

-- ============================================================
-- BENUTZER
-- ============================================================

CREATE TABLE benutzer (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    benutzername TEXT NOT NULL,
    passwort_hash TEXT NOT NULL,
    rolle benutzerrolle NOT NULL DEFAULT 'BENUTZER',
    aktiv BOOLEAN NOT NULL DEFAULT TRUE,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    zuletzt_angemeldet_am TIMESTAMPTZ,

    CONSTRAINT uq_benutzer_haushalt_benutzername
        UNIQUE (haushalt_id, benutzername),

    CONSTRAINT chk_benutzername
        CHECK (length(trim(benutzername)) >= 2),

    CONSTRAINT chk_passwort_hash
        CHECK (length(trim(passwort_hash)) > 0)
);

-- ============================================================
-- KONTEN
-- ============================================================

CREATE TABLE konten (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    bezeichnung TEXT NOT NULL,
    art kontenart NOT NULL,

    anfangsbestand NUMERIC(14,2) NOT NULL DEFAULT 0,
    aktiv BOOLEAN NOT NULL DEFAULT TRUE,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_konten_haushalt_bezeichnung
        UNIQUE (haushalt_id, bezeichnung),

    CONSTRAINT chk_konten_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0)
);

-- ============================================================
-- KATEGORIEN
-- ============================================================

CREATE TABLE kategorien (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    uebergeordnete_kategorie_id UUID,

    bezeichnung TEXT NOT NULL,
    art kategorienart NOT NULL,

    gruppe TEXT,
    sortierung INTEGER NOT NULL DEFAULT 0,
    aktiv BOOLEAN NOT NULL DEFAULT TRUE,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_kategorien_elternkategorie
        FOREIGN KEY (uebergeordnete_kategorie_id)
        REFERENCES kategorien(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_kategorien_haushalt_bezeichnung
        UNIQUE (haushalt_id, bezeichnung),

    CONSTRAINT chk_kategorien_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0),

    CONSTRAINT chk_kategorien_keine_eigene_elternkategorie
        CHECK (
            uebergeordnete_kategorie_id IS NULL
            OR uebergeordnete_kategorie_id <> id
        )
);

-- ============================================================
-- HÄNDLER
-- ============================================================

CREATE TABLE haendler (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    bezeichnung TEXT NOT NULL,
    normalisierte_bezeichnung TEXT NOT NULL,

    standard_kategorie_id UUID
        REFERENCES kategorien(id) ON DELETE SET NULL,

    aktiv BOOLEAN NOT NULL DEFAULT TRUE,
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_haendler_haushalt_normalisiert
        UNIQUE (haushalt_id, normalisierte_bezeichnung),

    CONSTRAINT chk_haendler_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0)
);

-- ============================================================
-- OBJEKTE
-- z.B. Auto, Wohnung, Versicherung
-- ============================================================

CREATE TABLE objekte (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    bezeichnung TEXT NOT NULL,
    art objektart NOT NULL,

    aktiv BOOLEAN NOT NULL DEFAULT TRUE,
    notiz TEXT,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_objekte_haushalt_bezeichnung
        UNIQUE (haushalt_id, bezeichnung),

    CONSTRAINT chk_objekte_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0)
);

-- ============================================================
-- VERMÖGENSKONTEN
-- z.B. Depot, Tagesgeld, P2P
-- ============================================================

CREATE TABLE vermoegenskonten (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    bezeichnung TEXT NOT NULL,
    art vermoegensart NOT NULL,
    anbieter TEXT,

    aktiv BOOLEAN NOT NULL DEFAULT TRUE,
    notiz TEXT,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_vermoegenskonten_haushalt_bezeichnung
        UNIQUE (haushalt_id, bezeichnung),

    CONSTRAINT chk_vermoegenskonten_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0)
);

-- ============================================================
-- VERMÖGENSSTÄNDE
-- Stichtagswerte eines Vermögenskontos
-- ============================================================

CREATE TABLE vermoegensstaende (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vermoegenskonto_id UUID NOT NULL
        REFERENCES vermoegenskonten(id) ON DELETE CASCADE,

    datum DATE NOT NULL,
    betrag NUMERIC(14,2) NOT NULL,
    notiz TEXT,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_vermoegensstaende_konto_datum
        UNIQUE (vermoegenskonto_id, datum)
);

-- ============================================================
-- BUCHUNGEN
-- ============================================================

CREATE TABLE buchungen (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    konto_id UUID
        REFERENCES konten(id) ON DELETE RESTRICT,

    gegenkonto_id UUID
        REFERENCES konten(id) ON DELETE RESTRICT,

    vermoegenskonto_id UUID
        REFERENCES vermoegenskonten(id) ON DELETE RESTRICT,

    haendler_id UUID
        REFERENCES haendler(id) ON DELETE SET NULL,

    objekt_id UUID
        REFERENCES objekte(id) ON DELETE SET NULL,

    datum DATE NOT NULL,
    buchungsart buchungsart NOT NULL,
    betrag NUMERIC(14,2) NOT NULL,

    bezeichnung TEXT,
    notiz TEXT,

    status buchungsstatus NOT NULL DEFAULT 'BESTAETIGT',
    quelle quelle NOT NULL DEFAULT 'MANUELL',

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_buchungen_betrag
        CHECK (betrag > 0),

    CONSTRAINT chk_buchungen_uebertragung
        CHECK (
            buchungsart <> 'UEBERTRAGUNG'
            OR (
                konto_id IS NOT NULL
                AND gegenkonto_id IS NOT NULL
                AND konto_id <> gegenkonto_id
            )
        ),

    CONSTRAINT chk_buchungen_investition
        CHECK (
            buchungsart <> 'INVESTITION'
            OR (
                konto_id IS NOT NULL
                AND vermoegenskonto_id IS NOT NULL
            )
        ),

    CONSTRAINT chk_buchungen_konto_gegenkonto
        CHECK (
            gegenkonto_id IS NULL
            OR konto_id IS NULL
            OR konto_id <> gegenkonto_id
        )
);

-- ============================================================
-- BUCHUNGSPOSITIONEN
-- Eine Buchung kann auf mehrere Kategorien aufgeteilt werden.
-- ============================================================

CREATE TABLE buchungspositionen (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    buchung_id UUID NOT NULL
        REFERENCES buchungen(id) ON DELETE CASCADE,

    kategorie_id UUID NOT NULL
        REFERENCES kategorien(id) ON DELETE RESTRICT,

    beschreibung TEXT,
    betrag NUMERIC(14,2) NOT NULL,

    menge NUMERIC(14,3),
    einzelpreis NUMERIC(14,2),

    quelle quelle NOT NULL DEFAULT 'MANUELL',

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_buchungspositionen_betrag
        CHECK (betrag > 0),

    CONSTRAINT chk_buchungspositionen_menge
        CHECK (menge IS NULL OR menge > 0),

    CONSTRAINT chk_buchungspositionen_einzelpreis
        CHECK (einzelpreis IS NULL OR einzelpreis >= 0)
);

-- ============================================================
-- REGELMÄSSIGE VORGÄNGE
-- ============================================================

CREATE TABLE regelmaessige_vorgaenge (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    bezeichnung TEXT NOT NULL,
    art regelmaessige_art NOT NULL,

    betrag NUMERIC(14,2) NOT NULL,

    kategorie_id UUID
        REFERENCES kategorien(id) ON DELETE RESTRICT,

    konto_id UUID
        REFERENCES konten(id) ON DELETE RESTRICT,

    vermoegenskonto_id UUID
        REFERENCES vermoegenskonten(id) ON DELETE RESTRICT,

    objekt_id UUID
        REFERENCES objekte(id) ON DELETE SET NULL,

    rhythmus rhythmus NOT NULL,
    ausfuehrungstag INTEGER,

    startdatum DATE NOT NULL,
    enddatum DATE,

    aktiv BOOLEAN NOT NULL DEFAULT TRUE,
    notiz TEXT,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_regelmaessige_bezeichnung
        CHECK (length(trim(bezeichnung)) > 0),

    CONSTRAINT chk_regelmaessige_betrag
        CHECK (betrag > 0),

    CONSTRAINT chk_regelmaessige_ausfuehrungstag
        CHECK (
            ausfuehrungstag IS NULL
            OR (ausfuehrungstag BETWEEN 1 AND 31)
        ),

    CONSTRAINT chk_regelmaessige_zeitraum
        CHECK (
            enddatum IS NULL
            OR enddatum >= startdatum
        ),

    CONSTRAINT chk_regelmaessige_investition
        CHECK (
            art <> 'INVESTITION'
            OR vermoegenskonto_id IS NOT NULL
        )
);

-- ============================================================
-- BUDGETS
-- monatliches Budget: monat = 1..12
-- Jahresbudget: monat = NULL
-- ============================================================

CREATE TABLE budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    kategorie_id UUID NOT NULL
        REFERENCES kategorien(id) ON DELETE CASCADE,

    jahr INTEGER NOT NULL,
    monat INTEGER,

    betrag NUMERIC(14,2) NOT NULL,
    aktiv BOOLEAN NOT NULL DEFAULT TRUE,

    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_budgets_jahr
        CHECK (jahr BETWEEN 2000 AND 2200),

    CONSTRAINT chk_budgets_monat
        CHECK (monat IS NULL OR monat BETWEEN 1 AND 12),

    CONSTRAINT chk_budgets_betrag
        CHECK (betrag >= 0)
);

-- Verhindert auch doppelte Jahresbudgets (monat = NULL).
CREATE UNIQUE INDEX uq_budgets_haushalt_kategorie_jahr_monat
    ON budgets (haushalt_id, kategorie_id, jahr, COALESCE(monat, 0));

-- ============================================================
-- ÄNDERUNGSPROTOKOLL
-- Kein Belegarchiv; nur Änderungen an Daten werden protokolliert.
-- ============================================================

CREATE TABLE aenderungsprotokoll (
    id BIGSERIAL PRIMARY KEY,

    haushalt_id UUID NOT NULL
        REFERENCES haushalte(id) ON DELETE CASCADE,

    benutzer_id UUID
        REFERENCES benutzer(id) ON DELETE SET NULL,

    zeitpunkt TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    tabelle TEXT NOT NULL,
    datensatz_id UUID,

    aktion TEXT NOT NULL,
    alte_daten JSONB,
    neue_daten JSONB,

    CONSTRAINT chk_aenderungsprotokoll_aktion
        CHECK (aktion IN ('ERSTELLT', 'GEAENDERT', 'GELOESCHT'))
);

-- ============================================================
-- INDIZES
-- ============================================================

CREATE INDEX idx_benutzer_haushalt
    ON benutzer(haushalt_id);

CREATE INDEX idx_konten_haushalt
    ON konten(haushalt_id);

CREATE INDEX idx_kategorien_haushalt
    ON kategorien(haushalt_id);

CREATE INDEX idx_kategorien_eltern
    ON kategorien(uebergeordnete_kategorie_id);

CREATE INDEX idx_haendler_haushalt
    ON haendler(haushalt_id);

CREATE INDEX idx_objekte_haushalt
    ON objekte(haushalt_id);

CREATE INDEX idx_vermoegenskonten_haushalt
    ON vermoegenskonten(haushalt_id);

CREATE INDEX idx_vermoegensstaende_konto_datum
    ON vermoegensstaende(vermoegenskonto_id, datum DESC);

CREATE INDEX idx_buchungen_haushalt_datum
    ON buchungen(haushalt_id, datum DESC);

CREATE INDEX idx_buchungen_konto_datum
    ON buchungen(konto_id, datum DESC);

CREATE INDEX idx_buchungen_haendler
    ON buchungen(haendler_id);

CREATE INDEX idx_buchungen_objekt
    ON buchungen(objekt_id);

CREATE INDEX idx_buchungen_art_datum
    ON buchungen(buchungsart, datum DESC);

CREATE INDEX idx_buchungen_status
    ON buchungen(status);

CREATE INDEX idx_buchungspositionen_buchung
    ON buchungspositionen(buchung_id);

CREATE INDEX idx_buchungspositionen_kategorie
    ON buchungspositionen(kategorie_id);

CREATE INDEX idx_regelmaessige_vorgaenge_haushalt
    ON regelmaessige_vorgaenge(haushalt_id);

CREATE INDEX idx_regelmaessige_vorgaenge_aktiv
    ON regelmaessige_vorgaenge(aktiv);

CREATE INDEX idx_budgets_haushalt_jahr
    ON budgets(haushalt_id, jahr, monat);

CREATE INDEX idx_aenderungsprotokoll_haushalt_zeit
    ON aenderungsprotokoll(haushalt_id, zeitpunkt DESC);

-- ============================================================
-- HILFSFUNKTIONEN / KONSISTENZPRÜFUNGEN
-- ============================================================

-- Automatische Aktualisierung von aktualisiert_am.
CREATE OR REPLACE FUNCTION aktualisiere_zeitstempel()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.aktualisiert_am = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_buchungen_zeitstempel
BEFORE UPDATE ON buchungen
FOR EACH ROW
EXECUTE FUNCTION aktualisiere_zeitstempel();

-- Prüft, dass alle direkt referenzierten Datensätze zur
-- gleichen Haushalts-ID gehören.
CREATE OR REPLACE FUNCTION pruefe_buchung_haushalt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    ref_haushalt UUID;
BEGIN
    IF NEW.konto_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM konten WHERE id = NEW.konto_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION 'Konto % gehört nicht zum Haushalt %.',
                NEW.konto_id, NEW.haushalt_id;
        END IF;
    END IF;

    IF NEW.gegenkonto_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM konten WHERE id = NEW.gegenkonto_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION 'Gegenkonto % gehört nicht zum Haushalt %.',
                NEW.gegenkonto_id, NEW.haushalt_id;
        END IF;
    END IF;

    IF NEW.vermoegenskonto_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM vermoegenskonten WHERE id = NEW.vermoegenskonto_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION 'Vermögenskonto % gehört nicht zum Haushalt %.',
                NEW.vermoegenskonto_id, NEW.haushalt_id;
        END IF;
    END IF;

    IF NEW.haendler_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM haendler WHERE id = NEW.haendler_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION 'Händler % gehört nicht zum Haushalt %.',
                NEW.haendler_id, NEW.haushalt_id;
        END IF;
    END IF;

    IF NEW.objekt_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM objekte WHERE id = NEW.objekt_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION 'Objekt % gehört nicht zum Haushalt %.',
                NEW.objekt_id, NEW.haushalt_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_buchung_haushalt
BEFORE INSERT OR UPDATE ON buchungen
FOR EACH ROW
EXECUTE FUNCTION pruefe_buchung_haushalt();

-- Prüft die Kategorie einer Buchungsposition.
CREATE OR REPLACE FUNCTION pruefe_buchungsposition_haushalt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    buchung_haushalt UUID;
    kategorie_haushalt UUID;
BEGIN
    SELECT haushalt_id INTO buchung_haushalt
    FROM buchungen
    WHERE id = NEW.buchung_id;

    SELECT haushalt_id INTO kategorie_haushalt
    FROM kategorien
    WHERE id = NEW.kategorie_id;

    IF buchung_haushalt IS NULL THEN
        RAISE EXCEPTION 'Buchung % existiert nicht.', NEW.buchung_id;
    END IF;

    IF kategorie_haushalt IS NULL THEN
        RAISE EXCEPTION 'Kategorie % existiert nicht.', NEW.kategorie_id;
    END IF;

    IF buchung_haushalt <> kategorie_haushalt THEN
        RAISE EXCEPTION
            'Buchung und Kategorie gehören zu unterschiedlichen Haushalten.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_buchungsposition_haushalt
BEFORE INSERT OR UPDATE ON buchungspositionen
FOR EACH ROW
EXECUTE FUNCTION pruefe_buchungsposition_haushalt();

-- Prüft die Haushaltszugehörigkeit des Standard-Händlers.
CREATE OR REPLACE FUNCTION pruefe_haendler_haushalt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    ref_haushalt UUID;
BEGIN
    IF NEW.standard_kategorie_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM kategorien WHERE id = NEW.standard_kategorie_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION
                'Standardkategorie % gehört nicht zum Haushalt %.',
                NEW.standard_kategorie_id, NEW.haushalt_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_haendler_haushalt
BEFORE INSERT OR UPDATE ON haendler
FOR EACH ROW
EXECUTE FUNCTION pruefe_haendler_haushalt();

-- Prüft die Elternkategorie auf denselben Haushalt.
CREATE OR REPLACE FUNCTION pruefe_kategorie_haushalt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    ref_haushalt UUID;
BEGIN
    IF NEW.uebergeordnete_kategorie_id IS NOT NULL THEN
        SELECT haushalt_id INTO ref_haushalt
        FROM kategorien WHERE id = NEW.uebergeordnete_kategorie_id;

        IF ref_haushalt IS NULL OR ref_haushalt <> NEW.haushalt_id THEN
            RAISE EXCEPTION
                'Elternkategorie % gehört nicht zum Haushalt %.',
                NEW.uebergeordnete_kategorie_id, NEW.haushalt_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_kategorie_haushalt
BEFORE INSERT OR UPDATE ON kategorien
FOR EACH ROW
EXECUTE FUNCTION pruefe_kategorie_haushalt();

-- Prüft die Summe der Buchungspositionen.
-- Übertragungen dürfen ohne Kategorien/Positionen existieren.
CREATE OR REPLACE FUNCTION pruefe_buchungssumme()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    buchung_id_pruefen UUID;
    erwarteter_betrag NUMERIC(14,2);
    positionssumme NUMERIC(14,2);
    art_pruefen buchungsart;
BEGIN
    buchung_id_pruefen := COALESCE(NEW.buchung_id, OLD.buchung_id);

    SELECT betrag, buchungsart
    INTO erwarteter_betrag, art_pruefen
    FROM buchungen
    WHERE id = buchung_id_pruefen;

    IF erwarteter_betrag IS NULL THEN
        RETURN NULL;
    END IF;

    IF art_pruefen = 'UEBERTRAGUNG' THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(betrag), 0)
    INTO positionssumme
    FROM buchungspositionen
    WHERE buchung_id = buchung_id_pruefen;

    IF positionssumme <> erwarteter_betrag THEN
        RAISE EXCEPTION
            'Buchung %: Positionen ergeben %, erwartet werden %.',
            buchung_id_pruefen,
            positionssumme,
            erwarteter_betrag;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_buchungssumme_positionen
AFTER INSERT OR UPDATE OR DELETE ON buchungspositionen
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION pruefe_buchungssumme();

-- Auch eine neue/änderte Buchung selbst wird am Transaktionsende geprüft.
CREATE CONSTRAINT TRIGGER trg_buchungssumme_buchung
AFTER INSERT OR UPDATE ON buchungen
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION pruefe_buchungssumme();

-- ============================================================
-- AUSWERTUNGEN
-- ============================================================

CREATE VIEW monatsbuchungen AS
SELECT
    b.id,
    b.haushalt_id,
    b.datum,
    EXTRACT(YEAR FROM b.datum)::INTEGER AS jahr,
    EXTRACT(MONTH FROM b.datum)::INTEGER AS monat,
    b.buchungsart,
    b.betrag,
    b.status,
    b.quelle,
    b.bezeichnung,
    k.id AS konto_id,
    k.bezeichnung AS konto,
    h.id AS haendler_id,
    h.bezeichnung AS haendler,
    o.id AS objekt_id,
    o.bezeichnung AS objekt
FROM buchungen b
LEFT JOIN konten k ON k.id = b.konto_id
LEFT JOIN haendler h ON h.id = b.haendler_id
LEFT JOIN objekte o ON o.id = b.objekt_id;

CREATE VIEW ausgaben_nach_kategorie AS
SELECT
    b.haushalt_id,
    EXTRACT(YEAR FROM b.datum)::INTEGER AS jahr,
    EXTRACT(MONTH FROM b.datum)::INTEGER AS monat,
    k.id AS kategorie_id,
    k.bezeichnung AS kategorie,
    k.gruppe,
    SUM(bp.betrag) AS betrag
FROM buchungen b
JOIN buchungspositionen bp ON bp.buchung_id = b.id
JOIN kategorien k ON k.id = bp.kategorie_id
WHERE b.buchungsart IN ('AUSGABE', 'ERSTATTUNG')
  AND b.status = 'BESTAETIGT'
GROUP BY
    b.haushalt_id,
    EXTRACT(YEAR FROM b.datum),
    EXTRACT(MONTH FROM b.datum),
    k.id,
    k.bezeichnung,
    k.gruppe;

CREATE VIEW aktuelle_vermoegensstaende AS
SELECT DISTINCT ON (v.vermoegenskonto_id)
    vk.haushalt_id,
    vk.id AS vermoegenskonto_id,
    vk.bezeichnung,
    vk.art,
    v.datum,
    v.betrag
FROM vermoegenskonten vk
JOIN vermoegensstaende v
    ON v.vermoegenskonto_id = vk.id
ORDER BY v.vermoegenskonto_id, v.datum DESC;

COMMIT;

-- ============================================================
-- MONATSWERTE
-- Direkte Zellwerte der Monatsansicht (Excel-ähnliche Eingabe).
-- Eine Kombination aus Tag und Kategorie entspricht genau einer Zelle.
-- ============================================================

CREATE TABLE monatswerte (
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

CREATE INDEX idx_monatswerte_haushalt_datum ON monatswerte(haushalt_id, datum);

-- Sonstige Einnahmen (Migration 003)
CREATE TABLE IF NOT EXISTS sonstige_einnahmen (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    monat DATE NOT NULL,
    bezeichnung VARCHAR(120) NOT NULL,
    betrag NUMERIC(14,2) NOT NULL,
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_se_monat CHECK (EXTRACT(DAY FROM monat) = 1),
    CONSTRAINT chk_se_betrag CHECK (betrag >= 0),
    CONSTRAINT chk_se_bezeichnung CHECK (length(trim(bezeichnung)) > 0)
);
CREATE INDEX IF NOT EXISTS idx_se_haushalt_monat ON sonstige_einnahmen(haushalt_id, monat, erstellt_am);

-- Tagesnotizen (Migration 005)
CREATE TABLE IF NOT EXISTS tagesnotizen (
    haushalt_id UUID NOT NULL REFERENCES haushalte(id) ON DELETE CASCADE,
    datum DATE NOT NULL,
    notiz VARCHAR(300) NOT NULL,
    aktualisiert_am TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (haushalt_id, datum),
    CONSTRAINT chk_tagesnotiz_text CHECK (length(trim(notiz)) > 0)
);
