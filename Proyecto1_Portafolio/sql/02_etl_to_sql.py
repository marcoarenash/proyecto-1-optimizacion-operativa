"""
=============================================================================
PROYECTO 1 DAP - FASE 3: ETL de CSV limpio -> SQLite (Modelo Estrella Kimball)
=============================================================================
Entrada : DS_DAP_P1_clean.csv  (2.000 tickets)
Salida  : proyecto1_kimball.db (Dim_Calendar, Dim_Agent, Dim_IssueCategory,
                                Fact_ServiceEvents)
Uso     : python 02_etl_to_sql.py
=============================================================================
"""

import re
import sqlite3
import pandas as pd

CSV_FILE = "DS_DAP_P1_clean.csv"
DDL_FILE = "01_DDL_kimball.sql"
DB_FILE = "proyecto1_kimball.db"

DIAS_ES = {
    "Monday": "Lunes", "Tuesday": "Martes", "Wednesday": "Miércoles",
    "Thursday": "Jueves", "Friday": "Viernes", "Saturday": "Sábado",
    "Sunday": "Domingo",
}

# ---------------------------------------------------------------------------
# 1. EXTRACT
# ---------------------------------------------------------------------------
df = pd.read_csv(CSV_FILE)
print(f"[1/6] CSV cargado: {len(df)} filas, {len(df.columns)} columnas")

df["created_at"] = pd.to_datetime(df["created_at"], errors="coerce")
df["date_key"] = df["created_at"].dt.date.astype(str)

# ---------------------------------------------------------------------------
# 2. Crear la base y ejecutar el DDL
# ---------------------------------------------------------------------------
conn = sqlite3.connect(DB_FILE)
conn.execute("PRAGMA foreign_keys = ON;")
with open(DDL_FILE, "r", encoding="utf-8") as f:
    conn.executescript(f.read())
conn.commit()
print("[2/6] Esquema Kimball creado")

# ---------------------------------------------------------------------------
# 3. Dim_Calendar: calendario CONTINUO (sin huecos) sobre el rango del dataset
# ---------------------------------------------------------------------------
rango = pd.date_range(df["created_at"].min().normalize(),
                      df["created_at"].max().normalize(), freq="D")
cal = pd.DataFrame({"date_key": rango.date.astype(str)})
fechas = pd.to_datetime(cal["date_key"])
cal["year"] = fechas.dt.year
cal["quarter"] = fechas.dt.quarter
cal["month"] = fechas.dt.month
cal["month_name"] = fechas.dt.month_name()
cal["day"] = fechas.dt.day
cal["day_of_week"] = fechas.dt.day_name().map(DIAS_ES)
cal["dow_number"] = fechas.dt.dayofweek + 1          # 1=Lunes ... 7=Domingo
cal["week_of_year"] = fechas.dt.isocalendar().week.astype(int)
cal["is_weekend"] = (fechas.dt.dayofweek >= 5).astype(int)
cal.to_sql("Dim_Calendar", conn, if_exists="append", index=False)

# ---------------------------------------------------------------------------
# 4. Dim_Agent: separar "Agent_001 (Priya S)" en código y nombre
# ---------------------------------------------------------------------------
def split_agente(valor):
    if pd.isna(valor):
        return pd.Series([None, None])
    m = re.match(r"\s*([^\s(]+)\s*(?:\((.*)\))?", str(valor))
    return pd.Series([m.group(1), (m.group(2) or "").strip() or None])

df[["agent_id", "agent_name"]] = df["assigned_agent"].apply(split_agente)

agents = (df[["agent_id", "agent_name"]]
          .dropna(subset=["agent_id"])
          .drop_duplicates(subset=["agent_id"])
          .reset_index(drop=True))
agents["team"] = "Support Tier 1"
agents.to_sql("Dim_Agent", conn, if_exists="append", index=False)

# ---------------------------------------------------------------------------
# 5. Dim_IssueCategory: grano categoría + subcategoría + prioridad
# ---------------------------------------------------------------------------
df["subcategory"] = df["subcategory"].fillna("Sin subcategoría")
df["priority"] = df["priority"].fillna("Sin prioridad")

issues = (df[["category", "subcategory", "priority"]]
          .dropna(subset=["category"])
          .drop_duplicates()
          .reset_index(drop=True)
          .rename(columns={"priority": "priority_level"}))
issues.to_sql("Dim_IssueCategory", conn, if_exists="append", index=False)
conn.commit()
print(f"[3/6] Dimensiones pobladas: {len(cal)} fechas, "
      f"{len(agents)} agentes, {len(issues)} categorías")

# ---------------------------------------------------------------------------
# 6. TRANSFORM: mapear claves subrogadas y renombrar métricas al modelo
# ---------------------------------------------------------------------------
dim_cal = pd.read_sql("SELECT calendar_sk, date_key FROM Dim_Calendar", conn)
dim_agt = pd.read_sql("SELECT agent_sk, agent_id FROM Dim_Agent", conn)
dim_iss = pd.read_sql(
    "SELECT issue_sk, category, subcategory, priority_level FROM Dim_IssueCategory", conn)

m = df.merge(dim_cal, on="date_key", how="left")
m = m.merge(dim_agt, on="agent_id", how="left")
m = m.merge(dim_iss,
            left_on=["category", "subcategory", "priority"],
            right_on=["category", "subcategory", "priority_level"],
            how="left")

# Mapeo de nombres del CSV -> nombres del modelo dimensional
m["handling_time_hrs"] = m["resolution_only_hrs"]   # T3 - T2
m["sla_compliant"] = m["sla_met"]                   # NULL en tickets sin cerrar
m["fcr_flag"] = m["fcr_proxy"].astype(int)
for col in ["reopened", "escalated", "is_inconsistent_time"]:
    m[col] = m[col].astype(int)

fact_cols = [
    "ticket_id", "calendar_sk", "agent_sk", "issue_sk",
    "channel", "status", "region", "sentiment", "product",
    "customer_plan", "language",
    "created_hour", "time_bucket",
    "wait_time_hrs", "handling_time_hrs", "resolution_time_hrs",
    "total_cycle_time_hrs", "delay_hrs", "sla_target_hrs",
    "sla_compliant", "fcr_flag", "csat_score", "num_interactions",
    "reopened", "escalated", "is_inconsistent_time",
]
fact = m[fact_cols]

# Control de integridad ANTES de cargar: ninguna FK puede quedar huérfana
huerfanas = fact[["calendar_sk", "issue_sk"]].isna().sum()
if huerfanas.sum() > 0:
    print(f"[!] Advertencia - FKs nulas: {huerfanas.to_dict()}")

fact.to_sql("Fact_ServiceEvents", conn, if_exists="append", index=False)
conn.commit()
print(f"[4/6] Fact_ServiceEvents cargada: {len(fact)} filas")

# ---------------------------------------------------------------------------
# 7. Verificación de integridad referencial
# ---------------------------------------------------------------------------
cur = conn.cursor()
print("\n--- VERIFICACIÓN DE INGESTA KIMBALL ---")
for t in ["Dim_Calendar", "Dim_Agent", "Dim_IssueCategory", "Fact_ServiceEvents"]:
    cur.execute(f"SELECT COUNT(*) FROM {t};")
    print(f"{t:<22}: {cur.fetchone()[0]:>6} filas")

cur.execute("""
    SELECT COUNT(*) FROM Fact_ServiceEvents f
    LEFT JOIN Dim_Calendar c ON f.calendar_sk = c.calendar_sk
    LEFT JOIN Dim_Agent    a ON f.agent_sk    = a.agent_sk
    LEFT JOIN Dim_IssueCategory i ON f.issue_sk = i.issue_sk
    WHERE c.calendar_sk IS NULL OR a.agent_sk IS NULL OR i.issue_sk IS NULL;
""")
print(f"Hechos con FK huérfana : {cur.fetchone()[0]} (debe ser 0)")

cur.execute("""
    SELECT i.category, COUNT(f.ticket_id) AS total,
           ROUND(AVG(f.resolution_time_hrs), 2) AS avg_res
    FROM Fact_ServiceEvents f
    JOIN Dim_IssueCategory i ON f.issue_sk = i.issue_sk
    GROUP BY i.category ORDER BY total DESC LIMIT 5;
""")
print("\nMuestra de cruce relacional (top 5 categorías):")
for row in cur.fetchall():
    print(" ", row)

conn.close()
print(f"\nFase 3 completada. Base generada: {DB_FILE}")
