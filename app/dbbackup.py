"""Datensicherung und Wiederherstellung des Haushaltsbuchs als JSON-Datei (gzip).

Warum kein pg_dump: Der Web-Container enthält keine PostgreSQL-Werkzeuge, und pg_dump muss zur
Datenbank-Version passen. Diese Sicherung liest und schreibt die Tabellen selbst. Sie ist deshalb
unabhängig von der PostgreSQL-Version, lässt sich auf einem zweiten Server einspielen und bleibt
lesbar.

Die Wiederherstellung ersetzt nur DATEN. Das Schema der laufenden Version bleibt unverändert.
Alles geschieht in einer Transaktion: bei einem Fehler ändert sich nichts.

Aufruf auf der Kommandozeile (im Web-Container):
    python /app/dbbackup.py export  > sicherung.json.gz
    python /app/dbbackup.py import  < sicherung.json.gz
"""
import gzip
import json
import os
import sys
import zlib
from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import UUID

import psycopg
from psycopg import sql
from psycopg.rows import dict_row, tuple_row
from psycopg.types.json import Jsonb

FORMAT = "haushaltsbuch-datensicherung"
FORMAT_VERSION = 1
# Wird von migrate.sh verwaltet und gehört nicht zu den Daten.
AUSGENOMMEN = {"schema_migrations"}
MAX_ENTPACKT = 200 * 1024 * 1024
LOCK_ID = 7231001

# Daten-Migrationen, die bei einer Wiederherstellung aus einer älteren Sicherung nachgeholt werden müssen
# (die Struktur-Migrationen entfallen, weil das Schema nicht angefasst wird).
# Bei jeder neuen Migration, die Daten ändert, hier ergänzen. Siehe db/migrations/.
NACHARBEIT = [
    # 007: "Beh./Gaststätten" heißt jetzt "Beh./Gast."
    """UPDATE kategorien k SET bezeichnung = 'Beh./Gast.'
        WHERE k.bezeichnung = 'Beh./Gaststätten' AND k.gruppe = 'Flexible Ausgaben'
          AND NOT EXISTS (SELECT 1 FROM kategorien k2
                           WHERE k2.haushalt_id = k.haushalt_id AND k2.bezeichnung = 'Beh./Gast.')""",
]


class BackupError(Exception):
    """Fehler mit einer Meldung, die dem Benutzer angezeigt werden darf."""


def _schema(cur):
    """{tabelle: [(spalte, datentyp), ...]} aller Datentabellen im Schema public."""
    cur.execute(
        """SELECT c.table_name, c.column_name, c.data_type, c.is_generated, c.identity_generation
             FROM information_schema.columns c
             JOIN information_schema.tables t
               ON t.table_schema = c.table_schema AND t.table_name = c.table_name
            WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
            ORDER BY c.table_name, c.ordinal_position"""
    )
    tabellen = {}
    for r in cur.fetchall():
        if r["table_name"] in AUSGENOMMEN:
            continue
        if r["is_generated"] == "ALWAYS" or r["identity_generation"] == "ALWAYS":
            continue
        tabellen.setdefault(r["table_name"], []).append((r["column_name"], r["data_type"]))
    return tabellen


def _kodieren(wert):
    if wert is None or isinstance(wert, (bool, int, float, str, dict, list)):
        return wert
    if isinstance(wert, (Decimal, UUID)):
        return str(wert)
    if isinstance(wert, (datetime, date)):
        return wert.isoformat()
    raise BackupError(f"Datentyp {type(wert).__name__} wird von der Sicherung nicht unterstützt.")


def export_backup(conn, app_version):
    """Liefert die komplette Sicherung als gzip-komprimierte JSON-Daten (bytes)."""
    # Konsistenter Schnappschuss: alle Tabellen zum selben Zeitpunkt lesen.
    conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
    conn.read_only = True
    daten = {
        "format": FORMAT,
        "formatversion": FORMAT_VERSION,
        "app_version": app_version,
        "erstellt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tabellen": {},
    }
    with conn.cursor(row_factory=dict_row) as cur:
        tabellen = _schema(cur)
    with conn.cursor(row_factory=tuple_row) as cur:
        for name, spalten in tabellen.items():
            namen = [s for s, _ in spalten]
            cur.execute(
                sql.SQL("SELECT {} FROM {} ORDER BY 1").format(
                    sql.SQL(", ").join(sql.Identifier(s) for s in namen), sql.Identifier(name)
                )
            )
            daten["tabellen"][name] = {
                "spalten": namen,
                "zeilen": [[_kodieren(w) for w in zeile] for zeile in cur.fetchall()],
            }
    roh = json.dumps(daten, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return gzip.compress(roh, compresslevel=6)


def lese_sicherung(roh):
    """Entpackt und prüft eine Sicherung. Gibt das Datenobjekt zurück oder wirft BackupError."""
    if not roh:
        raise BackupError("Die Datei ist leer.")
    if roh[:2] == b"\x1f\x8b":
        try:
            d = zlib.decompressobj(wbits=31)
            text = d.decompress(roh, MAX_ENTPACKT + 1)
        except zlib.error:
            raise BackupError("Die Datei ist keine gültige Sicherung (beschädigt oder abgeschnitten).")
        if len(text) > MAX_ENTPACKT or d.unconsumed_tail:
            raise BackupError("Die Sicherung ist unplausibel groß und wird abgelehnt.")
        if not d.eof:
            raise BackupError("Die Sicherung ist unvollständig (die Datei ist abgeschnitten).")
    else:
        text = roh  # unkomprimiertes JSON ist ebenfalls erlaubt
    try:
        daten = json.loads(text.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise BackupError("Die Datei ist keine Haushaltsbuch-Sicherung (Inhalt nicht lesbar).")
    if not isinstance(daten, dict) or daten.get("format") != FORMAT:
        raise BackupError("Die Datei ist keine Haushaltsbuch-Sicherung.")
    fv = daten.get("formatversion")
    if not isinstance(fv, int) or fv > FORMAT_VERSION:
        raise BackupError(
            "Die Sicherung wurde mit einem neueren Format erstellt. Bitte zuerst das Haushaltsbuch aktualisieren."
        )
    tab = daten.get("tabellen")
    if not isinstance(tab, dict):
        raise BackupError("Die Sicherung ist fehlerhaft (keine Tabellen).")
    for name, t in tab.items():
        if (
            not isinstance(t, dict)
            or not isinstance(t.get("spalten"), list)
            or not all(isinstance(s, str) for s in t["spalten"])
            or not isinstance(t.get("zeilen"), list)
        ):
            raise BackupError(f"Die Sicherung ist fehlerhaft (Tabelle „{name}“).")
        n = len(t["spalten"])
        if any(not isinstance(z, list) or len(z) != n for z in t["zeilen"]):
            raise BackupError(f"Die Sicherung ist fehlerhaft (Zeilen in Tabelle „{name}“).")
    return daten


def _version_tuple(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return ()


def zusammenfassung(conn, daten, app_version):
    """Was würde eingespielt? Ändert nichts."""
    with conn.cursor(row_factory=dict_row) as cur:
        vorhanden = _schema(cur)
    tabellen, ignoriert, hinweise = [], [], []
    gesamt = 0
    for name, t in daten["tabellen"].items():
        if name not in vorhanden:
            ignoriert.append(name)
            continue
        n = len(t["zeilen"])
        gesamt += n
        tabellen.append({"name": name, "zeilen": n})
        unbekannt = [s for s in t["spalten"] if s not in {c for c, _ in vorhanden[name]}]
        if unbekannt:
            hinweise.append(f"Tabelle „{name}“: unbekannte Spalten werden ignoriert ({', '.join(unbekannt)}).")
    if ignoriert:
        hinweise.append("Unbekannte Tabellen werden ignoriert: " + ", ".join(ignoriert) + ".")
    sv, av = _version_tuple(daten.get("app_version")), _version_tuple(app_version)
    if sv and av and sv > av:
        hinweise.append(
            f"Die Sicherung stammt aus Version {daten.get('app_version')}, installiert ist {app_version}. "
            "Neuere Daten werden nur soweit übernommen, wie die installierte Version sie kennt."
        )
    return {
        "erstellt": daten.get("erstellt"),
        "app_version": daten.get("app_version"),
        "tabellen": [t for t in tabellen if t["zeilen"]],
        "tabellen_gesamt": len(tabellen),
        "zeilen_gesamt": gesamt,
        "hinweise": hinweise,
    }


def _umwandeln(wert, typ):
    if wert is None:
        return None
    if typ in ("json", "jsonb"):
        return Jsonb(wert)
    if isinstance(wert, (dict, list)):
        raise BackupError("Die Sicherung enthält unerwartet verschachtelte Werte.")
    return wert


def _fremdschluessel_pruefen(cur):
    """Weil beim Einspielen die Fremdschlüssel-Prüfung abgeschaltet ist, wird sie hier nachgeholt."""
    cur.execute(
        """SELECT cl.relname AS kind, pl.relname AS eltern, c.conname,
                  (SELECT array_agg(a.attname ORDER BY k.ord)
                     FROM unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
                     JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) AS kind_spalten,
                  (SELECT array_agg(a.attname ORDER BY k.ord)
                     FROM unnest(c.confkey) WITH ORDINALITY k(attnum, ord)
                     JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum) AS eltern_spalten
             FROM pg_constraint c
             JOIN pg_class cl ON cl.oid = c.conrelid
             JOIN pg_class pl ON pl.oid = c.confrelid
            WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace"""
    )
    for fk in cur.fetchall():
        kind = [sql.Identifier("ch", s) for s in fk["kind_spalten"]]
        eltern = [sql.Identifier("p", s) for s in fk["eltern_spalten"]]
        nicht_null = sql.SQL(" AND ").join(sql.SQL("{} IS NOT NULL").format(k) for k in kind)
        gleich = sql.SQL(" AND ").join(sql.SQL("{} = {}").format(e, k) for e, k in zip(eltern, kind))
        abfrage = sql.SQL(
            "SELECT 1 FROM {child} ch WHERE {nn} AND NOT EXISTS (SELECT 1 FROM {parent} p WHERE {eq}) LIMIT 1"
        ).format(child=sql.Identifier(fk["kind"]), nn=nicht_null, parent=sql.Identifier(fk["eltern"]), eq=gleich)
        with cur.connection.cursor(row_factory=tuple_row) as c2:
            if c2.execute(abfrage).fetchone():
                raise BackupError(
                    "Die Sicherung ist in sich nicht stimmig: Tabelle „%s“ verweist auf nicht vorhandene Einträge in „%s“. "
                    "Es wurde nichts verändert." % (fk["kind"], fk["eltern"])
                )


def stelle_wieder_her(conn, daten):
    """Ersetzt alle Daten durch die der Sicherung. Der Aufrufer committet bei Erfolg."""
    ergebnis = {"zeilen": 0, "tabellen": 0, "ignoriert": []}
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK_ID,))
        vorhanden = _schema(cur)
        try:
            # Trigger und Fremdschlüssel-Prüfungen aus, bis alles geladen ist. Die Stimmigkeit wird danach geprüft.
            cur.execute("SET LOCAL session_replication_role = replica")
        except psycopg.errors.InsufficientPrivilege:
            raise BackupError(
                "Der Datenbankbenutzer darf Prüfungen nicht vorübergehend abschalten (Superuser nötig). "
                "Es wurde nichts verändert."
            )
        cur.execute(
            sql.SQL("TRUNCATE {}").format(sql.SQL(", ").join(sql.Identifier(t) for t in vorhanden))
        )
        for name, t in daten["tabellen"].items():
            if name not in vorhanden:
                ergebnis["ignoriert"].append(name)
                continue
            typen = dict(vorhanden[name])
            verwendet = [(i, s) for i, s in enumerate(t["spalten"]) if s in typen]
            if not verwendet or not t["zeilen"]:
                continue
            stmt = sql.SQL("INSERT INTO {} ({}) VALUES ({})").format(
                sql.Identifier(name),
                sql.SQL(", ").join(sql.Identifier(s) for _, s in verwendet),
                sql.SQL(", ").join(sql.Placeholder() for _ in verwendet),
            )
            cur.executemany(
                stmt, [tuple(_umwandeln(z[i], typen[s]) for i, s in verwendet) for z in t["zeilen"]]
            )
            ergebnis["zeilen"] += len(t["zeilen"])
            ergebnis["tabellen"] += 1
        # Zähler (BIGSERIAL) hinter den höchsten eingespielten Wert setzen.
        cur.execute(
            """SELECT table_name, column_name FROM information_schema.columns
                WHERE table_schema = 'public' AND column_default LIKE 'nextval(%'"""
        )
        for r in cur.fetchall():
            if r["table_name"] in AUSGENOMMEN:
                continue
            with conn.cursor(row_factory=tuple_row) as c2:
                c2.execute(
                    sql.SQL("SELECT setval(pg_get_serial_sequence({t}, {c}), COALESCE(MAX({col}), 0) + 1, false) FROM {tab}").format(
                        t=sql.Literal(r["table_name"]),
                        c=sql.Literal(r["column_name"]),
                        col=sql.Identifier(r["column_name"]),
                        tab=sql.Identifier(r["table_name"]),
                    )
                )
        _fremdschluessel_pruefen(cur)
        cur.execute("SET LOCAL session_replication_role = origin")
        for stmt in NACHARBEIT:
            cur.execute(stmt)
    return ergebnis


def _cli(argv):
    url = os.environ.get("DATABASE_URL")
    if not url or len(argv) < 2 or argv[1] not in ("export", "import"):
        sys.stderr.write(__doc__.split("Aufruf auf der Kommandozeile")[1] if __doc__ else "")
        return 2
    try:
        if argv[1] == "export":
            with psycopg.connect(url, row_factory=dict_row) as conn:
                sys.stdout.buffer.write(export_backup(conn, os.environ.get("APP_VERSION", "unbekannt")))
            return 0
        daten = lese_sicherung(sys.stdin.buffer.read())
        with psycopg.connect(url, row_factory=dict_row) as conn:
            erg = stelle_wieder_her(conn, daten)
        sys.stderr.write(f"Wiederhergestellt: {erg['zeilen']} Zeilen in {erg['tabellen']} Tabellen.\n")
        return 0
    except BackupError as e:
        sys.stderr.write(f"Fehler: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(_cli(sys.argv))
