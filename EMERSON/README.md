# Modulo EMERSON - Tracciabilità, ODL e Reportistica di Fabbricazione

```text
========================================================================================
SISTEMA / AMBIENTE:  MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
AZIENDA:             Torneria Molinari Vincenzo (TMV)
AUTORE / SVILUPPO:   SOLVERIS - Bandera Marco
ULTIMO ALLINEAMENTO: 2026-09-23
========================================================================================
```

---

## 1. Panoramica del Modulo

Questa directory raggruppa tutti i componenti database (viste, funzioni scalari e documentazione analitica) sviluppati per la gestione degli ordini di produzione, tracciabilità lotti e cartellini di reparto per il cliente **EMERSON PROCESS MANAGEMENT** e per le commesse ad alta criticità metallurgica (settore Oil&Gas / Energy).

---

## 2. Componenti SQL Attivi in Produzione

| File SQL | Oggetto Database | Tipo | Ruolo Funzionale |
| :--- | :--- | :---: | :--- |
| [`VPRT_ODL_REPORT.sql`](./VPRT_ODL_REPORT.sql) | `[dbo].[VPRT_ODL_REPORT]` | Vista | **Vista master di reportistica e fabbricazione.** Normalizza i dati per i cartellini ODL, estrae quote geometriche di rullatura (`DIAMETRO_MEDIO`), testi di marcatura laser/percussione (`MARKING`), riferimenti PO cliente Emerson e gestisce la tracciabilità delle colate. |
| [`SPRT_LTT_FAKE.sql`](./SPRT_LTT_FAKE.sql) | `[dbo].[SPRT_LTT_FAKE]` | Funzione Scalare | **Motore generale di recupero lotto/colata.** Opera a due stadi: priorità consuntiva tramite risalita allo scarico reale (`INT-SCARPROD` via `DO33`/`DO52`), con fallback automatico su distinta master e disponibilità di magazzino. |
| [`SPRT_LTT_FAKE_EMERSON.sql`](./SPRT_LTT_FAKE_EMERSON.sql) | `[dbo].[SPRT_LTT_FAKE_EMERSON]` | Funzione Scalare | **Risolutore specializzato per colata forzata.** Recupera l'ultimo lotto fornitore registrato in anagrafica lotti (`MG4G`) a partire dalla specifica colata pattuita sull'Ordine Cliente (`DO36_ALFST1` / Color Code). |
| [`SPSO_STATISTICHE_IMPORTAZIONI_NICIM_GEMINI.sql`](./SPSO_STATISTICHE_IMPORTAZIONI_NICIM_GEMINI.sql) | `[dbo].[SPSO_STATISTICHE_IMPORTAZIONI_NICIM_GEMINI]` | Stored Procedure | **Analisi statistica mensile dei trattamenti di fallback Alyante.** Confronta le rilevazioni canoniche da MES Overone (`RT15`/`RT16`) con i meccanismi di forzatura storici (`TMV-NICIM-AVAN2` con risorsa `XXXX` e `TMV-NICIM-CONS2` con lotto fittizio `LT-2403-999` e sostituzione dadi stock). Supporta filtri temporali e modalità Dry-Run. |

---

## 3. Logica Chiave: Risoluzione della Colata nei Report Crystal

Nei layout di stampa dei cartellini di produzione (Crystal Report) viene applicata la formula:

```crystal
iif(trim({VPRT_ODL_REPORT.COLATA_TIMBRARE}) <> '', trim({VPRT_ODL_REPORT.COLATA_TIMBRARE}), {VPRT_ODL_REPORT.COLATA})
```

- **Priorità 1 (`COLATA_TIMBRARE`):** Se valorizzato in `DO36_ALFST1` sulla riga dell'Ordine Cliente, viene stampato questo valore (colata contrattuale concordata con Emerson).
- **Priorità 2 (`COLATA`):** Se `COLATA_TIMBRARE` è vuoto, interviene `SPRT_LTT_FAKE`, che preleva la colata effettiva scaricata allo scarico di officina oppure l'ultimo lotto disponibile in distinta.

---

## 4. Documentazione, Verbali e Report Excel

- [`VERBALE_ANALISI_PREDDT_5289_COLATE.md`](./VERBALE_ANALISI_PREDDT_5289_COLATE.md): Verbale tecnico dell'indagine e quadratura dati condotta sul documento `DC-PREDDT` N. 5289 del 31/08/2026 (6 righe con quantità $\ge 10$), con risalita a Ordini Cliente, ODL e movimenti di scarico.
- [`STATISTICHE_IMPORTAZIONI_NICIM_AVANZ2_CONS2.xlsx`](./STATISTICHE_IMPORTAZIONI_NICIM_AVANZ2_CONS2.xlsx): Cartella di lavoro Excel con i risultati statistici a base mese (Avanzamenti, Consumi, Sinottico Tipologie e Dashboard KPI con evidenza della Data Massima Documenti: 14/09/2026).

---

## 5. Versioni Storiche e Archivio

- [`archive/`](./archive/): Contiene le versioni storiche dismesse (`SPRT_LTT_FAKE_OLD.sql` e `SPRT_LTT_FAKE_OLD_2026_03_04.sql`), ritirate dal database il 23/09/2026 per azzeramento del debito tecnico e conservate unicamente a fini di consultazione e audit.

