-- Migration 007: Kategorie "Beh./Gaststätten" heißt jetzt "Beh./Gast."
--
-- Der kürzere Name macht die Spalte in der Monatsansicht schmaler. Beträge bleiben erhalten,
-- weil nur die Bezeichnung geändert wird (gleiche ID). Ein bereits vorhandener Eintrag mit dem
-- neuen Namen wird nicht überschrieben.
UPDATE kategorien k
   SET bezeichnung = 'Beh./Gast.'
 WHERE k.bezeichnung = 'Beh./Gaststätten'
   AND k.gruppe = 'Flexible Ausgaben'
   AND NOT EXISTS (SELECT 1 FROM kategorien k2
                    WHERE k2.haushalt_id = k.haushalt_id AND k2.bezeichnung = 'Beh./Gast.');
