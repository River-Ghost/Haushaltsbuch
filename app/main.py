import os
from datetime import date
from decimal import Decimal
from typing import Literal
from pathlib import Path
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

DB = os.environ["DATABASE_URL"]
BASE = Path(__file__).parent
# Die Version steht bewusst im Code und nicht in der .env, damit sie nach einem
# Update nie veraltet angezeigt wird.
VERSION = "0.5.8"
app = FastAPI(title=os.getenv("APP_NAME", "Haushaltsbuch"), version=VERSION)
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")

# ---------------------------------------------------------------------------
# Gruppen (entsprechen den Blöcken der Excel-Tabelle "GESAMT")
# ---------------------------------------------------------------------------
GRUPPE_FLEX = "Flexible Ausgaben"
# Posten dieser Gruppen werden pro Monat direkt eingetragen (Datum = 1. des Monats).
FESTE_GRUPPEN = {
    "Einnahmen": "EINNAHME",
    "Fixe Ausgaben": "AUSGABE",
    "Sparen/Vermögen": "SPAREN",
}
ALLE_GRUPPEN = ["Einnahmen", "Fixe Ausgaben", "Sparen/Vermögen", GRUPPE_FLEX]
TITEL = {
    "Einnahmen": "Einnahmen",
    "Fixe Ausgaben": "Feste Ausgaben",
    "Sparen/Vermögen": "Sparen / Vermögen",
    GRUPPE_FLEX: "Flexible Ausgaben",
}

# Die Reihenfolge entspricht der Excel-Logik für flexible Ausgaben.
FLEXIBLE_KATEGORIEN = [
    "Lebensmittel",
    "Genussmittel",
    "Kultur",
    "Freizeit",
    "KP/Gesundheit",
    "HW/Möbel",
    "BK/Schuhe",
    "Beh./Gast.",
    "Verkehr",
    "Sonstiges",
]

# Startliste, abgeleitet aus der Excel-Vorlage. Wird nur angelegt, solange es noch
# gar keine Posten in den drei Gruppen gibt. Alles ist in der App änderbar.
START_POSTEN = {
    # Dividenden, Zinsen und Sonstiges kommen aus der Ansicht "Sonstige Einnahmen".
    "Einnahmen": ["Gehalt 1", "Gehalt 2", "Kindergeld"],
    "Fixe Ausgaben": [
        "Miete",
        "Nebenkosten",
        "Strom (Grundpreis)",
        "Wasser",
        "Telefon & Internet",
        "Rundfunkgebühren",
        "Haftpflicht",
        "Fahrradversicherung",
        "Zahnzusatzversicherung",
        "Reisekrankenversicherung",
        "Kfz-Steuer",
        "Kfz-Versicherung",
        "Lebensversicherung",
        "Steuer-Rücklage",
    ],
    "Sparen/Vermögen": ["ETF-Sparplan", "Aktienkauf", "Bitcoin"],
}


def db():
    return psycopg.connect(DB, row_factory=dict_row)


def household(c):
    row = c.execute("SELECT id, name FROM haushalte ORDER BY erstellt_am LIMIT 1").fetchone()
    if row:
        return row
    return c.execute(
        "INSERT INTO haushalte(name) VALUES(%s) RETURNING id, name",
        ("Mein Haushalt",),
    ).fetchone()


def month_range(year: int, month: int):
    first = date(year, month, 1)
    last = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    return first, last


def set_value(c, haushalt_id, datum: date, kategorie_id, betrag: Decimal):
    """Schreibt eine Zelle. Betrag 0 löscht sie (leere Zelle)."""
    if betrag == 0:
        c.execute(
            "DELETE FROM monatswerte WHERE haushalt_id=%s AND datum=%s AND kategorie_id=%s",
            (haushalt_id, datum, kategorie_id),
        )
    else:
        c.execute(
            """INSERT INTO monatswerte(haushalt_id,datum,kategorie_id,betrag)
               VALUES(%s,%s,%s,%s)
               ON CONFLICT(haushalt_id,datum,kategorie_id)
               DO UPDATE SET betrag=EXCLUDED.betrag, aktualisiert_am=NOW()""",
            (haushalt_id, datum, kategorie_id, betrag),
        )


def require_fester_posten(c, haushalt_id, kategorie_id):
    row = c.execute(
        "SELECT id, gruppe, aktiv FROM kategorien WHERE id=%s AND haushalt_id=%s AND gruppe = ANY(%s)",
        (kategorie_id, haushalt_id, list(FESTE_GRUPPEN)),
    ).fetchone()
    if not row:
        raise HTTPException(404, "Posten nicht gefunden.")
    return row


def seed_posten(c, haushalt_id):
    n = c.execute(
        "SELECT count(*) AS n FROM kategorien WHERE haushalt_id=%s AND gruppe = ANY(%s)",
        (haushalt_id, list(FESTE_GRUPPEN)),
    ).fetchone()["n"]
    if n:
        return
    for gruppe, namen in START_POSTEN.items():
        for i, name in enumerate(namen, 1):
            c.execute(
                """INSERT INTO kategorien(haushalt_id,bezeichnung,art,gruppe,sortierung)
                   VALUES(%s,%s,%s::kategorienart,%s,%s)
                   ON CONFLICT (haushalt_id,bezeichnung) DO NOTHING""",
                (haushalt_id, name, FESTE_GRUPPEN[gruppe], gruppe, i * 10),
            )


class CellValue(BaseModel):
    betrag: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)


class SEBody(BaseModel):
    bezeichnung: str = Field(min_length=1, max_length=120)
    # 0 = Betrag noch offen (z. B. nach "Wiederholen")
    betrag: Decimal = Field(ge=0, max_digits=14, decimal_places=2)


class SENew(SEBody):
    monat: str = Field(pattern=r"^\d{4}-\d{2}$")
    # Ein neuer Eintrag per Eingabezeile braucht einen Betrag.
    betrag: Decimal = Field(gt=0, max_digits=14, decimal_places=2)


RHYTHMEN = {"monatlich": 1, "vierteljaehrlich": 3, "halbjaehrlich": 6, "jaehrlich": 12}


class RepeatBody(BaseModel):
    rhythmus: Literal["monatlich", "vierteljaehrlich", "halbjaehrlich", "jaehrlich"]
    bis_jahr: int = Field(ge=2000, le=2100)


def add_months(d: date, n: int) -> date:
    jahr, monat = divmod(d.year * 12 + d.month - 1 + n, 12)
    return date(jahr, monat + 1, 1)


def se_art(bezeichnung: str) -> str:
    """Wie das Excel-Blatt SE: Bezeichnung entscheidet über Dividende / Zinsen / Sonstiges."""
    b = bezeichnung.strip().lower()
    if b.startswith(("div.", "dividende")):
        return "Dividende"
    if b.startswith("zins"):
        return "Zinsen"
    return "Sonstiges"


def parse_monat(monat: str):
    year, month = map(int, monat.split("-"))
    if not (2000 <= year <= 2100 and 1 <= month <= 12):
        raise HTTPException(400, "Ungültiger Monat.")
    return year, month


class NoteBody(BaseModel):
    notiz: str = Field(default="", max_length=300)


class CellNoteBody(BaseModel):
    notiz: str = Field(default="", max_length=500)


class FillBody(BaseModel):
    ab_monat: int = Field(ge=1, le=12)
    bis_monat: int = Field(default=12, ge=1, le=12)
    betrag: Decimal = Field(ge=0, max_digits=14, decimal_places=2)


class NewPost(BaseModel):
    gruppe: str
    bezeichnung: str = Field(min_length=1, max_length=60)


class PostPatch(BaseModel):
    bezeichnung: str | None = Field(default=None, min_length=1, max_length=60)
    aktiv: bool | None = None


@app.get("/", response_class=HTMLResponse)
def home():
    return (BASE / "index.html").read_text(encoding="utf-8")


@app.get("/manifest.webmanifest")
def manifest():
    return FileResponse(BASE / "static" / "manifest.webmanifest", media_type="application/manifest+json")


@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    return FileResponse(BASE / "static" / "favicon-32.png", media_type="image/png")


@app.get("/api/version")
def version():
    return {"version": VERSION}


@app.post("/api/setup-demo")
def setup_demo():
    with db() as c:
        h = household(c)
        with c.transaction():
            if c.execute("SELECT count(*) AS n FROM konten WHERE haushalt_id=%s", (h["id"],)).fetchone()["n"] == 0:
                c.execute(
                    "INSERT INTO konten(haushalt_id,bezeichnung,art,anfangsbestand) VALUES(%s,%s,%s,%s)",
                    (h["id"], "Girokonto", "GIROKONTO", 0),
                )
                c.execute(
                    "INSERT INTO konten(haushalt_id,bezeichnung,art,anfangsbestand) VALUES(%s,%s,%s,%s)",
                    (h["id"], "Bargeld", "BARGELD", 0),
                )
            existing = {
                r["bezeichnung"]
                for r in c.execute(
                    "SELECT bezeichnung FROM kategorien WHERE haushalt_id=%s", (h["id"],)
                ).fetchall()
            }
            for name in FLEXIBLE_KATEGORIEN:
                if name not in existing:
                    c.execute(
                        "INSERT INTO kategorien(haushalt_id,bezeichnung,art,gruppe,sortierung) VALUES(%s,%s,'AUSGABE',%s,%s)",
                        (h["id"], name, GRUPPE_FLEX, FLEXIBLE_KATEGORIEN.index(name) + 1),
                    )
            seed_posten(c, h["id"])
    return {"ok": True}


# ---------------------------------------------------------------------------
# Monatsansicht (flexible Ausgaben pro Tag)
# ---------------------------------------------------------------------------
@app.get("/api/monat")
def month_view(monat: str = Query(..., pattern=r"^\d{4}-\d{2}$")):
    year, month = map(int, monat.split("-"))
    if not (2000 <= year <= 2100 and 1 <= month <= 12):
        raise HTTPException(400, "Ungültiger Monat.")
    first, last = month_range(year, month)
    with db() as c:
        h = household(c)
        cats = c.execute(
            """SELECT id, bezeichnung, sortierung FROM kategorien
               WHERE haushalt_id=%s AND art='AUSGABE' AND gruppe=%s AND aktiv
               ORDER BY sortierung, bezeichnung""",
            (h["id"], GRUPPE_FLEX),
        ).fetchall()
        # Nur flexible Ausgaben: Einnahmen und feste Posten liegen ebenfalls in
        # monatswerte (am Monatsersten) und dürfen hier nicht mitgezählt werden.
        values = c.execute(
            """SELECT m.datum, m.kategorie_id, m.betrag
               FROM monatswerte m JOIN kategorien k ON k.id = m.kategorie_id
               WHERE m.haushalt_id=%s AND k.gruppe=%s AND m.datum >= %s AND m.datum < %s""",
            (h["id"], GRUPPE_FLEX, first, last),
        ).fetchall()
        notizen = {
            r["datum"].isoformat(): r["notiz"]
            for r in c.execute(
                "SELECT datum, notiz FROM tagesnotizen WHERE haushalt_id=%s AND datum >= %s AND datum < %s",
                (h["id"], first, last),
            ).fetchall()
        }
        by_day = {}
        totals = {}
        for row in values:
            by_day.setdefault(row["datum"].isoformat(), {})[str(row["kategorie_id"])] = float(row["betrag"])
            key = str(row["kategorie_id"])
            totals[key] = totals.get(key, 0) + float(row["betrag"])

        return {
            "monat": monat,
            "kategorien": [{"id": str(k["id"]), "bezeichnung": k["bezeichnung"]} for k in cats],
            "tage": by_day,
            "notizen": notizen,
            "summen": totals,
            "gesamt": round(sum(float(r["betrag"]) for r in values), 2),
        }


@app.put("/api/monat/{monat}/{datum}/{kategorie_id}")
def save_cell(monat: str, datum: date, kategorie_id: UUID, x: CellValue):
    if datum.strftime("%Y-%m") != monat:
        raise HTTPException(400, "Datum und Monat passen nicht zusammen.")
    with db() as c:
        h = household(c)
        category = c.execute(
            "SELECT id FROM kategorien WHERE id=%s AND haushalt_id=%s AND gruppe=%s AND aktiv",
            (kategorie_id, h["id"], GRUPPE_FLEX),
        ).fetchone()
        if not category:
            raise HTTPException(404, "Kategorie nicht gefunden.")
        with c.transaction():
            set_value(c, h["id"], datum, kategorie_id, x.betrag)
    return {"ok": True, "betrag": float(x.betrag)}


@app.put("/api/notiz/{datum}")
def save_note(datum: date, x: NoteBody):
    """Freier Text pro Tag ("Die teuersten Einkaufsposten"). Leerer Text löscht die Notiz."""
    if not (2000 <= datum.year <= 2100):
        raise HTTPException(400, "Ungültiges Datum.")
    text = x.notiz.strip()
    with db() as c:
        h = household(c)
        with c.transaction():
            if not text:
                c.execute("DELETE FROM tagesnotizen WHERE haushalt_id=%s AND datum=%s", (h["id"], datum))
            else:
                c.execute(
                    """INSERT INTO tagesnotizen(haushalt_id,datum,notiz) VALUES(%s,%s,%s)
                       ON CONFLICT(haushalt_id,datum) DO UPDATE SET notiz=EXCLUDED.notiz, aktualisiert_am=NOW()""",
                    (h["id"], datum, text),
                )
    return {"ok": True, "notiz": text}


@app.get("/api/uebersicht")
def overview(monat: str = Query(..., pattern=r"^\d{4}-\d{2}$")):
    year, month = map(int, monat.split("-"))
    if not (2000 <= year <= 2100 and 1 <= month <= 12):
        raise HTTPException(400, "Ungültiger Monat.")
    first, last = month_range(year, month)
    with db() as c:
        h = household(c)
        rows = c.execute(
            """SELECT k.gruppe, COALESCE(SUM(m.betrag),0) AS wert
               FROM monatswerte m JOIN kategorien k ON k.id = m.kategorie_id
               WHERE m.haushalt_id=%s AND m.datum >= %s AND m.datum < %s
               GROUP BY k.gruppe""",
            (h["id"], first, last),
        ).fetchall()
        s = {r["gruppe"]: r["wert"] for r in rows}
        se = c.execute(
            "SELECT COALESCE(SUM(betrag),0) AS wert FROM sonstige_einnahmen WHERE haushalt_id=%s AND monat=%s",
            (h["id"], first),
        ).fetchone()["wert"]
        einnahmen = s.get("Einnahmen", Decimal(0)) + se
        fix = s.get("Fixe Ausgaben", Decimal(0))
        sparen = s.get("Sparen/Vermögen", Decimal(0))
        flex = s.get(GRUPPE_FLEX, Decimal(0))
        return {
            "einnahmen": float(einnahmen),
            "fixkosten": float(fix),
            "sparen": float(sparen),
            "flexibel": float(flex),
            "saldo": float(einnahmen - fix - sparen - flex),
        }


# ---------------------------------------------------------------------------
# Jahresübersicht (entspricht dem Excel-Blatt "GESAMT")
# ---------------------------------------------------------------------------
@app.get("/api/jahr")
def year_view(jahr: int = Query(..., ge=2000, le=2100)):
    first, last = date(jahr, 1, 1), date(jahr + 1, 1, 1)
    with db() as c:
        h = household(c)
        rows = c.execute(
            """SELECT k.id, k.bezeichnung, k.gruppe, k.aktiv,
                      EXTRACT(MONTH FROM m.datum)::int AS monat,
                      m.betrag
               FROM kategorien k
               LEFT JOIN monatswerte m
                      ON m.kategorie_id = k.id AND m.haushalt_id = k.haushalt_id
                     AND m.datum >= %s AND m.datum < %s
               WHERE k.haushalt_id=%s AND k.gruppe = ANY(%s)
               ORDER BY k.sortierung, k.bezeichnung, m.datum""",
            (first, last, h["id"], ALLE_GRUPPEN),
        ).fetchall()
        note_rows = c.execute(
            """SELECT kategorie_id, EXTRACT(MONTH FROM datum)::int AS monat, notiz
               FROM zellnotizen WHERE haushalt_id=%s AND datum >= %s AND datum < %s""",
            (h["id"], first, last),
        ).fetchall()
        se_rows = c.execute(
            """SELECT EXTRACT(MONTH FROM monat)::int AS monat, SUM(betrag) AS betrag
               FROM sonstige_einnahmen
               WHERE haushalt_id=%s AND monat >= %s AND monat < %s GROUP BY 1""",
            (h["id"], first, last),
        ).fetchall()

    posten, order = {}, []
    for r in rows:
        p = posten.get(r["id"])
        if p is None:
            p = {
                "id": str(r["id"]),
                "bezeichnung": r["bezeichnung"],
                "gruppe": r["gruppe"],
                "aktiv": r["aktiv"],
                "monate": [Decimal(0)] * 12,
            }
            posten[r["id"]] = p
            order.append(p)
        if r["monat"]:
            p["monate"][r["monat"] - 1] += r["betrag"]

    notizen = {}
    for r in note_rows:
        notizen.setdefault(str(r["kategorie_id"]), {})[str(r["monat"])] = r["notiz"]

    bloecke = []
    for gruppe in ALLE_GRUPPEN:
        # Ausgeblendete Posten bleiben sichtbar, solange sie in diesem Jahr Beträge
        # haben. Sonst würden die Summen stillschweigend abweichen.
        ps = [p for p in order if p["gruppe"] == gruppe and (p["aktiv"] or any(p["monate"]))]
        bloecke.append(
            {
                "gruppe": gruppe,
                "titel": TITEL[gruppe],
                "editierbar": gruppe in FESTE_GRUPPEN,
                # Ausgeblendete Posten ohne Beträge in diesem Jahr: nicht in der Tabelle,
                # aber über "Ausgeblendet" wieder einblendbar.
                "ausgeblendet": [
                    {"id": p["id"], "bezeichnung": p["bezeichnung"]}
                    for p in order
                    if p["gruppe"] == gruppe and not p["aktiv"] and not any(p["monate"])
                ],
                "posten": [
                    {
                        "id": p["id"],
                        "bezeichnung": p["bezeichnung"],
                        "aktiv": p["aktiv"],
                        "monate": [float(x) for x in p["monate"]],
                        "notizen": notizen.get(p["id"], {}),
                    }
                    for p in ps
                ],
            }
        )
    # Entspricht der Excel-Zeile "Sonstiges (SE)": schreibgeschützt, Summen aus der SE-Ansicht.
    se_monate = [0.0] * 12
    for r in se_rows:
        se_monate[r["monat"] - 1] = float(r["betrag"])
    for b in bloecke:
        if b["gruppe"] == "Einnahmen":
            b["posten"].append(
                {
                    "id": "se",
                    "bezeichnung": "Nebeneinnahmen",
                    "aktiv": True,
                    "schreibgeschuetzt": True,
                    "monate": se_monate,
                    "notizen": {},
                }
            )
    return {"jahr": jahr, "bloecke": bloecke}


@app.put("/api/jahr/{jahr}/{monat}/{kategorie_id}")
def save_year_cell(jahr: int, monat: int, kategorie_id: UUID, x: CellValue):
    if not (2000 <= jahr <= 2100 and 1 <= monat <= 12):
        raise HTTPException(400, "Ungültiges Jahr oder ungültiger Monat.")
    with db() as c:
        h = household(c)
        require_fester_posten(c, h["id"], kategorie_id)
        with c.transaction():
            set_value(c, h["id"], date(jahr, monat, 1), kategorie_id, x.betrag)
    return {"ok": True, "betrag": float(x.betrag)}


@app.put("/api/jahr/{jahr}/{monat}/{kategorie_id}/notiz")
def save_cell_note(jahr: int, monat: int, kategorie_id: UUID, x: CellNoteBody):
    """Notiz an einer Zelle der Jahresübersicht (wie ein Excel-Kommentar). Leerer Text löscht sie."""
    if not (2000 <= jahr <= 2100 and 1 <= monat <= 12):
        raise HTTPException(400, "Ungültiges Jahr oder ungültiger Monat.")
    text = x.notiz.strip()
    with db() as c:
        h = household(c)
        require_fester_posten(c, h["id"], kategorie_id)
        datum = date(jahr, monat, 1)
        with c.transaction():
            if not text:
                c.execute(
                    "DELETE FROM zellnotizen WHERE haushalt_id=%s AND kategorie_id=%s AND datum=%s",
                    (h["id"], kategorie_id, datum),
                )
            else:
                c.execute(
                    """INSERT INTO zellnotizen(haushalt_id,kategorie_id,datum,notiz) VALUES(%s,%s,%s,%s)
                       ON CONFLICT(haushalt_id,kategorie_id,datum)
                       DO UPDATE SET notiz=EXCLUDED.notiz, aktualisiert_am=NOW()""",
                    (h["id"], kategorie_id, datum, text),
                )
    return {"ok": True, "notiz": text}


@app.post("/api/jahr/{jahr}/{kategorie_id}/fuellen")
def fill_row(jahr: int, kategorie_id: UUID, x: FillBody):
    """Entspricht dem Excel-Ausfüllen nach rechts: gleicher Betrag für ab..bis Monat."""
    if not (2000 <= jahr <= 2100):
        raise HTTPException(400, "Ungültiges Jahr.")
    if x.bis_monat < x.ab_monat:
        raise HTTPException(400, "Der Endmonat liegt vor dem Startmonat.")
    with db() as c:
        h = household(c)
        require_fester_posten(c, h["id"], kategorie_id)
        with c.transaction():
            for monat in range(x.ab_monat, x.bis_monat + 1):
                set_value(c, h["id"], date(jahr, monat, 1), kategorie_id, x.betrag)
    return {"ok": True, "ab_monat": x.ab_monat, "bis_monat": x.bis_monat, "betrag": float(x.betrag)}


# ---------------------------------------------------------------------------
# Sonstige Einnahmen (entspricht dem Excel-Blatt "SE")
# ---------------------------------------------------------------------------
@app.get("/api/se")
def se_view(monat: str = Query(..., pattern=r"^\d{4}-\d{2}$")):
    year, month = parse_monat(monat)
    first = date(year, month, 1)
    with db() as c:
        h = household(c)
        eintraege = c.execute(
            """SELECT id, bezeichnung, betrag FROM sonstige_einnahmen
               WHERE haushalt_id=%s AND monat=%s ORDER BY erstellt_am, id""",
            (h["id"], first),
        ).fetchall()
        jahr_rows = c.execute(
            """SELECT EXTRACT(MONTH FROM monat)::int AS monat, bezeichnung, betrag
               FROM sonstige_einnahmen
               WHERE haushalt_id=%s AND monat >= %s AND monat < %s""",
            (h["id"], date(year, 1, 1), date(year + 1, 1, 1)),
        ).fetchall()
    monate = [{"monat": i, "dividenden": 0.0, "zinsen": 0.0, "sonstiges": 0.0} for i in range(1, 13)]
    schluessel = {"Dividende": "dividenden", "Zinsen": "zinsen", "Sonstiges": "sonstiges"}
    for r in jahr_rows:
        monate[r["monat"] - 1][schluessel[se_art(r["bezeichnung"])]] += float(r["betrag"])
    return {
        "monat": monat,
        "eintraege": [
            {
                "id": str(e["id"]),
                "bezeichnung": e["bezeichnung"],
                "betrag": float(e["betrag"]),
                "art": se_art(e["bezeichnung"]),
            }
            for e in eintraege
        ],
        "summe": round(sum(float(e["betrag"]) for e in eintraege), 2),
        "jahr": {"jahr": year, "monate": monate},
    }


@app.post("/api/se")
def se_add(x: SENew):
    year, month = parse_monat(x.monat)
    name = x.bezeichnung.strip()
    if not name:
        raise HTTPException(400, "Bitte eine Bezeichnung angeben.")
    with db() as c:
        h = household(c)
        with c.transaction():
            row = c.execute(
                """INSERT INTO sonstige_einnahmen(haushalt_id,monat,bezeichnung,betrag)
                   VALUES(%s,%s,%s,%s) RETURNING id""",
                (h["id"], date(year, month, 1), name, x.betrag),
            ).fetchone()
    return {"ok": True, "id": str(row["id"]), "art": se_art(name)}


@app.put("/api/se/{eintrag_id}")
def se_update(eintrag_id: UUID, x: SEBody):
    name = x.bezeichnung.strip()
    if not name:
        raise HTTPException(400, "Bitte eine Bezeichnung angeben.")
    with db() as c:
        h = household(c)
        with c.transaction():
            n = c.execute(
                """UPDATE sonstige_einnahmen SET bezeichnung=%s, betrag=%s, aktualisiert_am=NOW()
                   WHERE id=%s AND haushalt_id=%s""",
                (name, x.betrag, eintrag_id, h["id"]),
            ).rowcount
        if not n:
            raise HTTPException(404, "Eintrag nicht gefunden.")
    return {"ok": True, "art": se_art(name)}


@app.post("/api/se/{eintrag_id}/wiederholen")
def se_repeat(eintrag_id: UUID, x: RepeatBody):
    """Legt die Bezeichnung im gewählten Rhythmus bis Dezember von bis_jahr erneut an.

    Kopiert wird nur die Bezeichnung. Der Betrag bleibt leer (0) und wird später eingetragen.
    Existiert im Zielmonat bereits ein Eintrag mit gleicher Bezeichnung, wird dieser Monat
    übersprungen (keine Doppelten).
    """
    with db() as c:
        h = household(c)
        e = c.execute(
            "SELECT monat, bezeichnung FROM sonstige_einnahmen WHERE id=%s AND haushalt_id=%s",
            (eintrag_id, h["id"]),
        ).fetchone()
        if not e:
            raise HTTPException(404, "Eintrag nicht gefunden.")
        if not (e["monat"].year <= x.bis_jahr <= e["monat"].year + 5):
            raise HTTPException(400, "„Bis“ muss im Jahr des Eintrags oder in den fünf Folgejahren liegen.")
        ende = date(x.bis_jahr, 12, 1)
        schritt = RHYTHMEN[x.rhythmus]
        ziele, d = [], add_months(e["monat"], schritt)
        while d <= ende:
            ziele.append(d)
            d = add_months(d, schritt)
        angelegt, uebersprungen = [], []
        with c.transaction():
            for ziel in ziele:
                vorhanden = c.execute(
                    """SELECT 1 FROM sonstige_einnahmen
                       WHERE haushalt_id=%s AND monat=%s AND lower(trim(bezeichnung))=lower(trim(%s))""",
                    (h["id"], ziel, e["bezeichnung"]),
                ).fetchone()
                if vorhanden:
                    uebersprungen.append(ziel.strftime("%Y-%m"))
                    continue
                c.execute(
                    "INSERT INTO sonstige_einnahmen(haushalt_id,monat,bezeichnung,betrag) VALUES(%s,%s,%s,0)",
                    (h["id"], ziel, e["bezeichnung"]),
                )
                angelegt.append(ziel.strftime("%Y-%m"))
    return {"ok": True, "angelegt": angelegt, "uebersprungen": uebersprungen}


@app.delete("/api/se/{eintrag_id}")
def se_delete(eintrag_id: UUID):
    with db() as c:
        h = household(c)
        with c.transaction():
            n = c.execute(
                "DELETE FROM sonstige_einnahmen WHERE id=%s AND haushalt_id=%s",
                (eintrag_id, h["id"]),
            ).rowcount
        if not n:
            raise HTTPException(404, "Eintrag nicht gefunden.")
    return {"ok": True}


# ---------------------------------------------------------------------------
# Posten verwalten (hinzufügen, umbenennen, aus-/einblenden)
# ---------------------------------------------------------------------------
@app.post("/api/posten")
def add_post(x: NewPost):
    name = x.bezeichnung.strip()
    if not name:
        raise HTTPException(400, "Bitte einen Namen angeben.")
    if x.gruppe not in FESTE_GRUPPEN:
        raise HTTPException(400, "Unbekannte Gruppe.")
    with db() as c:
        h = household(c)
        existing = c.execute(
            "SELECT id, gruppe, aktiv FROM kategorien WHERE haushalt_id=%s AND bezeichnung=%s",
            (h["id"], name),
        ).fetchone()
        with c.transaction():
            if existing:
                if existing["gruppe"] != x.gruppe:
                    raise HTTPException(409, f"Der Name wird bereits in „{TITEL.get(existing['gruppe'], existing['gruppe'])}“ verwendet.")
                if existing["aktiv"]:
                    raise HTTPException(409, "Diesen Posten gibt es bereits.")
                c.execute("UPDATE kategorien SET aktiv=TRUE WHERE id=%s", (existing["id"],))
                return {"ok": True, "id": str(existing["id"]), "wieder_eingeblendet": True}
            nxt = c.execute(
                "SELECT COALESCE(MAX(sortierung),0)+10 AS n FROM kategorien WHERE haushalt_id=%s AND gruppe=%s",
                (h["id"], x.gruppe),
            ).fetchone()["n"]
            row = c.execute(
                """INSERT INTO kategorien(haushalt_id,bezeichnung,art,gruppe,sortierung)
                   VALUES(%s,%s,%s::kategorienart,%s,%s) RETURNING id""",
                (h["id"], name, FESTE_GRUPPEN[x.gruppe], x.gruppe, nxt),
            ).fetchone()
    return {"ok": True, "id": str(row["id"])}


@app.patch("/api/posten/{kategorie_id}")
def patch_post(kategorie_id: UUID, x: PostPatch):
    name = x.bezeichnung.strip() if x.bezeichnung is not None else None
    if x.bezeichnung is not None and not name:
        raise HTTPException(400, "Bitte einen Namen angeben.")
    if name is None and x.aktiv is None:
        raise HTTPException(400, "Nichts zu ändern.")
    with db() as c:
        h = household(c)
        require_fester_posten(c, h["id"], kategorie_id)
        try:
            with c.transaction():
                if name is not None:
                    c.execute("UPDATE kategorien SET bezeichnung=%s WHERE id=%s", (name, kategorie_id))
                if x.aktiv is not None:
                    c.execute("UPDATE kategorien SET aktiv=%s WHERE id=%s", (x.aktiv, kategorie_id))
        except psycopg.errors.UniqueViolation:
            raise HTTPException(409, "Diesen Namen gibt es bereits.")
    return {"ok": True}


@app.get("/api/health")
def health():
    with db() as c:
        c.execute("SELECT 1")
    return {"status": "ok", "version": VERSION}
