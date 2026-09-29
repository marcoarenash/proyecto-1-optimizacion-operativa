-- =========================================================================
-- PROYECTO 1 DAP - CONSULTAS ANALÍTICAS SOBRE EL MODELO ESTRELLA
-- KPIs: % SLA Compliance, % FCR, AHT, CSAT, Pareto 80/20, Heatmap, MA7
-- Nota: sla_compliant es NULL en tickets no cerrados, por lo que todas las métricas
--       de cumplimiento se calculan sólo sobre tickets con SLA evaluable.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Consulta 0: Tarjetas de la Vista Ejecutiva (KPIs globales)
-- -------------------------------------------------------------------------
SELECT
    COUNT(*)                                                        AS volumen_total,
    ROUND(AVG(wait_time_hrs), 2)                                    AS avg_wait_hrs,
    ROUND(AVG(handling_time_hrs), 2)                                AS aht_hrs,
    ROUND(AVG(total_cycle_time_hrs), 2)                             AS avg_cycle_hrs,
    ROUND(AVG(csat_score), 2)                                       AS csat_promedio,
    ROUND(AVG(sla_compliant) * 100.0, 2)                            AS pct_sla_compliance,
    ROUND(AVG(fcr_flag) * 100.0, 2)                                 AS pct_fcr,
    SUM(CASE WHEN sla_compliant IS NULL THEN 1 ELSE 0 END)          AS tickets_abiertos
FROM Fact_ServiceEvents;

-- -------------------------------------------------------------------------
-- Consulta 1: PARETO 80/20 - categorías que concentran las horas de retraso
-- Ordena por retraso total acumulado y marca el corte del 80%.
-- -------------------------------------------------------------------------
WITH base AS (
    SELECT
        i.category,
        COUNT(f.ticket_id)                                  AS total_tickets,
        ROUND(SUM(COALESCE(f.delay_hrs, 0)), 2)             AS horas_retraso,
        ROUND(AVG(f.resolution_time_hrs), 2)                AS avg_resolution_hrs,
        ROUND((1 - AVG(f.sla_compliant)) * 100.0, 2)        AS pct_sla_breach
    FROM Fact_ServiceEvents f
    JOIN Dim_IssueCategory i ON f.issue_sk = i.issue_sk
    GROUP BY i.category
),
acumulado AS (
    SELECT
        base.*,
        SUM(horas_retraso) OVER (ORDER BY horas_retraso DESC
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS retraso_acumulado,
        SUM(horas_retraso) OVER ()                          AS retraso_total
    FROM base
)
SELECT
    category,
    total_tickets,
    horas_retraso,
    avg_resolution_hrs,
    pct_sla_breach,
    ROUND(retraso_acumulado * 100.0 / retraso_total, 2)     AS pct_acumulado,
    CASE WHEN retraso_acumulado * 100.0 / retraso_total <= 80.0
         THEN 'POCOS VITALES (20%)' ELSE 'Muchos triviales' END AS clase_pareto
FROM acumulado
ORDER BY horas_retraso DESC;

-- -------------------------------------------------------------------------
-- Consulta 2: Rendimiento por agente (AHT, CSAT, %SLA, %FCR)
-- -------------------------------------------------------------------------
SELECT
    a.agent_id,
    a.agent_name,
    COUNT(f.ticket_id)                          AS tickets_atendidos,
    ROUND(AVG(f.handling_time_hrs), 2)          AS aht_hrs,
    ROUND(AVG(f.wait_time_hrs), 2)              AS avg_wait_hrs,
    ROUND(AVG(f.csat_score), 2)                 AS csat_promedio,
    ROUND(AVG(f.sla_compliant) * 100.0, 2)      AS pct_sla_compliance,
    ROUND(AVG(f.fcr_flag) * 100.0, 2)           AS pct_fcr
FROM Fact_ServiceEvents f
JOIN Dim_Agent a ON f.agent_sk = a.agent_sk
GROUP BY a.agent_id, a.agent_name
ORDER BY pct_sla_compliance DESC;

-- -------------------------------------------------------------------------
-- Consulta 3: Cuellos de botella por canal y prioridad
-- -------------------------------------------------------------------------
WITH BottleneckSummary AS (
    SELECT
        f.channel,
        i.priority_level,
        COUNT(f.ticket_id)                      AS volumen,
        ROUND(AVG(f.wait_time_hrs), 2)          AS avg_wait,
        ROUND(AVG(f.handling_time_hrs), 2)      AS avg_handling,
        ROUND(AVG(f.total_cycle_time_hrs), 2)   AS avg_cycle_time,
        ROUND(AVG(f.sla_compliant) * 100.0, 2)  AS pct_sla_compliance
    FROM Fact_ServiceEvents f
    JOIN Dim_IssueCategory i ON f.issue_sk = i.issue_sk
    GROUP BY f.channel, i.priority_level
)
SELECT * FROM BottleneckSummary
ORDER BY avg_cycle_time DESC;

-- -------------------------------------------------------------------------
-- Consulta 4: HEATMAP de volumen por día de la semana x hora de creación
-- Insumo directo para la propuesta de redistribución de personal.
-- -------------------------------------------------------------------------
SELECT
    c.dow_number,
    c.day_of_week,
    f.created_hour,
    COUNT(f.ticket_id)                          AS volumen,
    ROUND(AVG(f.wait_time_hrs), 2)              AS avg_wait_hrs
FROM Fact_ServiceEvents f
JOIN Dim_Calendar c ON f.calendar_sk = c.calendar_sk
GROUP BY c.dow_number, c.day_of_week, f.created_hour
ORDER BY c.dow_number, f.created_hour;

-- -------------------------------------------------------------------------
-- Consulta 5: Serie diaria con PROMEDIO MÓVIL DE 7 DÍAS
-- Usa el calendario continuo, por lo que los días sin tickets cuentan como 0.
-- -------------------------------------------------------------------------
WITH serie AS (
    SELECT
        c.date_key,
        COUNT(f.ticket_id)                      AS tickets,
        AVG(f.total_cycle_time_hrs)             AS avg_cycle
    FROM Dim_Calendar c
    LEFT JOIN Fact_ServiceEvents f ON f.calendar_sk = c.calendar_sk
    GROUP BY c.date_key
)
SELECT
    date_key,
    tickets,
    ROUND(avg_cycle, 2)                         AS avg_cycle_hrs,
    ROUND(AVG(tickets) OVER (ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)
        AS ma7_tickets,
    ROUND(AVG(avg_cycle) OVER (ORDER BY date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)
        AS ma7_cycle_hrs
FROM serie
ORDER BY date_key;

-- -------------------------------------------------------------------------
-- Consulta 6: Control de calidad de datos (auditoría del ETL)
-- -------------------------------------------------------------------------
SELECT
    SUM(is_inconsistent_time)                                   AS tickets_con_tiempos_inconsistentes,
    SUM(CASE WHEN sla_compliant IS NULL THEN 1 ELSE 0 END)      AS sin_sla_evaluable,
    SUM(CASE WHEN csat_score IS NULL THEN 1 ELSE 0 END)         AS sin_csat,
    SUM(reopened)                                               AS reabiertos,
    SUM(escalated)                                              AS escalados
FROM Fact_ServiceEvents;
