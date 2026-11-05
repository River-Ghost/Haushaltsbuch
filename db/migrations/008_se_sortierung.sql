-- Migration 008: Manuelle Reihenfolge der Nebeneinnahmen im Monat (Ziehen per Maus oder Finger)
--
-- Bisher wurde nach Erstellzeit sortiert. Jetzt gibt es eine eigene Spalte "sortierung".
-- Bestehende Einträge behalten ihre bisherige Reihenfolge (pro Monat von 1 an durchnummeriert).
ALTER TABLE sonstige_einnahmen ADD COLUMN IF NOT EXISTS sortierung INTEGER NOT NULL DEFAULT 0;

UPDATE sonstige_einnahmen s
   SET sortierung = n.rn
  FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY haushalt_id, monat ORDER BY erstellt_am, id) AS rn
          FROM sonstige_einnahmen) n
 WHERE s.id = n.id AND s.sortierung = 0;
