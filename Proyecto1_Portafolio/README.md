# 📊 Proyecto 1: Optimización Operativa & Análisis de Tiempos de Servicio (SaaS Support)

> **Portafolio Data Analyst** | Auditoría, modelado dimensional (Kimball), análisis exploratorio y visualización ejecutiva de un sistema de soporte técnico para la optimización de SLAs, tiempos de atención y satisfacción del cliente (CSAT).

---

## 🚀 1. Resumen Ejecutivo
Este proyecto analiza un dataset transaccional simulado de producción de **2,000 tickets de soporte y 23 variables** correspondientes a una empresa de software multi-producto SaaS (*TaskBoard, DataDash, CloudSync Pro, InvoiceFlow, SecureVault*)[cite: 22]. El objetivo central fue auditar la calidad de los datos, identificar cuellos de botella operativos mediante análisis de Pareto, modelar la arquitectura dimensional y construir tableros de control ejecutivos y operativos[cite: 1, 2, 3].

* **Volumen Total:** 2,000 tickets analizados (66.8% resueltos o cerrados; 27.45% de backlog operativo activo)[cite: 15, 22].
* **CSAT Promedio:** 2.71 / 5.0 (con una fuerte correlación con la polaridad del sentimiento del cliente).
* **Cumplimiento Global de SLA:** 37.94% (evidenciando una brecha crítica en los tiempos de ciclo y la gestión de colas).
* **Tiempos Operativos:** Tiempo de espera medio (*Wait Time* T2-T1) de 11.66 h, AHT de resolución (T3-T2) de 51.81 h, y un ciclo total promedio de ~63.7 horas.

---
## 🗂️ 2. Estructura del Repositorio
El repositorio se encuentra organizado bajo un estándar de ingeniería de datos y analítica reproducible:

- **`data/`**
  - `DS_DAP_P1.csv` — Dataset transaccional original (SaaS Helpdesk).
  - `DS_DAP_P1_clean.csv` — Dataset limpio, transformado y con Feature Engineering (35 columnas).
- **`docs/`**
  - `reporte_ejecutivo_proyecto1.pdf` — Informe gerencial formal de 4 páginas orientado a la toma de decisiones.
- **`notebooks/`**
  - `Proyecto1_DAP_Analisis.ipynb` — Jupyter Notebook con ETL, Data Quality, EDA y Feature Engineering.
- **`powerbi/`**
  - `DS_DAP_P1.pbix` — Dashboard interactivo principal (Vistas Ejecutiva y Operativa).
  - Capturas y recursos visuales de soporte.
- **`sql/`**
  - `01_DDL_kimball.sql` — Scripts de creación del Esquema Estrella (Fact & Dimensions).
  - `02_eti_to_sql.py` — Automatización de carga e inserción de datos.
  - `03_DML_analitico.sql` — Consultas analíticas clave (Principio de Pareto y AHT por agente).
  - `04_validacion_kimball.ipynb` — Validación e inspección del modelo dimensional.


```python

```
