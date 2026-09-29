-- =========================================================================
-- PROYECTO 1 DAP: Optimización Operativa & Análisis de Tiempos de Servicio
-- FASE 3 - DDL: Modelo Dimensional Kimball (Esquema Estrella)
-- Dataset origen: DS_DAP_P1_clean.csv (2.000 tickets, 2024-01-01 a 2025-06-30)
-- Motor: SQLite (compatible PostgreSQL/DuckDB cambiando AUTOINCREMENT)
-- =========================================================================

DROP TABLE IF EXISTS Fact_ServiceEvents;
DROP TABLE IF EXISTS Dim_Calendar;
DROP TABLE IF EXISTS Dim_Agent;
DROP TABLE IF EXISTS Dim_IssueCategory;

-- -------------------------------------------------------------------------
-- 1. Dim_Calendar
-- Calendario CONTINUO (todas las fechas del rango, con o sin tickets).
-- Requisito para el Promedio Móvil de 7 días en DAX: sin fechas huecas
-- la time intelligence de Power BI produce resultados incorrectos.
-- -------------------------------------------------------------------------
CREATE TABLE Dim_Calendar (
    calendar_sk   INTEGER PRIMARY KEY AUTOINCREMENT,
    date_key      TEXT    UNIQUE NOT NULL,   -- 'YYYY-MM-DD'
    year          INTEGER NOT NULL,
    quarter       INTEGER NOT NULL,
    month         INTEGER NOT NULL,
    month_name    TEXT,
    day           INTEGER NOT NULL,
    day_of_week   TEXT,
    dow_number    INTEGER,                   -- 1=Lunes ... 7=Domingo (orden en Power BI)
    week_of_year  INTEGER,
    is_weekend    INTEGER NOT NULL           -- 0 / 1
);

-- -------------------------------------------------------------------------
-- 2. Dim_Agent
-- El CSV trae 'assigned_agent' con formato "Agent_001 (Priya S)";
-- el ETL separa el código del nombre. 10 agentes únicos.
-- -------------------------------------------------------------------------
CREATE TABLE Dim_Agent (
    agent_sk    INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id    TEXT UNIQUE NOT NULL,        -- 'Agent_001'
    agent_name  TEXT,                        -- 'Priya S'
    team        TEXT
);

-- -------------------------------------------------------------------------
-- 3. Dim_IssueCategory
-- Grano: category + subcategory + priority_level (155 combinaciones reales).
-- La restricción UNIQUE evita duplicados si el ETL se reejecuta.
-- -------------------------------------------------------------------------
CREATE TABLE Dim_IssueCategory (
    issue_sk        INTEGER PRIMARY KEY AUTOINCREMENT,
    category        TEXT NOT NULL,
    subcategory     TEXT,
    priority_level  TEXT,
    UNIQUE (category, subcategory, priority_level)
);

-- -------------------------------------------------------------------------
-- 4. Fact_ServiceEvents
-- Grano: 1 fila = 1 ticket de servicio.
-- Incluye tickets abiertos/en progreso (métricas de cierre en NULL) para
-- poder medir backlog; sla_compliant sólo aplica a tickets resueltos.
-- -------------------------------------------------------------------------
CREATE TABLE Fact_ServiceEvents (
    ticket_id             TEXT PRIMARY KEY,
    calendar_sk           INTEGER,
    agent_sk              INTEGER,
    issue_sk              INTEGER,

    -- Atributos degenerados / contexto operativo
    channel               TEXT,
    status                TEXT,
    region                TEXT,
    sentiment             TEXT,
    product               TEXT,
    customer_plan         TEXT,
    language              TEXT,

    -- Contexto temporal fino (necesario para el Heatmap hora x día)
    created_hour          INTEGER,           -- 0-23
    time_bucket           TEXT,              -- Madrugada / Mañana / Tarde / Noche

    -- Métricas de tiempo (horas)
    wait_time_hrs         REAL,              -- T2 - T1
    handling_time_hrs     REAL,              -- T3 - T2
    resolution_time_hrs   REAL,
    total_cycle_time_hrs  REAL,              -- T3 - T1
    delay_hrs             REAL,              -- exceso sobre el SLA objetivo
    sla_target_hrs        INTEGER,

    -- KPIs de calidad y negocio
    sla_compliant         INTEGER,           -- 1 cumple / 0 incumple / NULL sin cerrar
    fcr_flag              INTEGER,           -- 1 First Contact Resolution / 0 no
    csat_score            INTEGER,           -- 1 a 5
    num_interactions      INTEGER,
    reopened              INTEGER,
    escalated             INTEGER,
    is_inconsistent_time  INTEGER,           -- bandera de calidad de datos

    FOREIGN KEY (calendar_sk) REFERENCES Dim_Calendar(calendar_sk),
    FOREIGN KEY (agent_sk)    REFERENCES Dim_Agent(agent_sk),
    FOREIGN KEY (issue_sk)    REFERENCES Dim_IssueCategory(issue_sk)
);

-- Índices de apoyo para las consultas analíticas
CREATE INDEX IF NOT EXISTS idx_fact_calendar ON Fact_ServiceEvents(calendar_sk);
CREATE INDEX IF NOT EXISTS idx_fact_agent    ON Fact_ServiceEvents(agent_sk);
CREATE INDEX IF NOT EXISTS idx_fact_issue    ON Fact_ServiceEvents(issue_sk);
