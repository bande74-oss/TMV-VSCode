/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Vista dbo.VPSO_TMV_AGG_DESCR_ART_GEMINI (Standard SOLVERIS GEMINI)
Nome File                        : VPSO_TMV_AGG_DESCR_ART_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La vista 'VPSO_TMV_AGG_DESCR_ART_GEMINI' rappresenta l'evoluzione conforme agli standard SOLVERIS
della vista di estrazione articoli per il tracciato batch 'TMV_AGG_DESART1' (Insieme 'TMV_AGG_DESCR_ART').

SCOPO AZIENDALE:
Garantire un'individuazione deterministica, sicura e senza lock di tutti gli articoli configurati
che richiedono la scrittura o riscrittura delle descrizioni standard e internazionali su Gamma Enterprise.

CARATTERISTICHE DELLA REVISIONE GEMINI:
1. Prefisso obbligatorio 'VPSO_' (Vista Personalizzata SOlveris) e suffisso obbligatorio '_GEMINI'.
2. Utilizzo pervasivo ed esplicito di clausole WITH (NOLOCK) per garantire che l'esecuzione del batch
   (anche ad alta frequenza tramite schedulatore) non collida mai con l'attività degli utenti
   interattivi di Gamma Enterprise (ordini, carichi di magazzino, anagrafiche aperte in modifica).
3. Incapsulamento delle sottoquery in Common Table Expressions (CTE) chiaramente etichettate per
   semplificare il piano di esecuzione di SQL Server 2017 e facilitare la leggibilità del codice.
4. Gestione uniforme e protetta dei valori NULL sulle opzioni/varianti tramite ISNULL() con stringa vuota,
   prevenendo anomalie di join dovute a collation o spazi trailing.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Vista iniziale dbo.VPRT_TMV_AGG_DESCR_ART.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Riformulazione integrale della logica secondo la convenzione SOLVERIS GEMINI (VPSO_..._GEMINI).
  Implementazione di CTE modulari, normalizzazione del filtro ditta parametrico su Ditta 1,
  protezione integrale contro i blocchi concorrenti con WITH (NOLOCK) e compatibilità certificata MSSQL 14.0.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[VPSO_TMV_AGG_DESCR_ART_GEMINI]', 'V') IS NOT NULL
    DROP VIEW [dbo].[VPSO_TMV_AGG_DESCR_ART_GEMINI];
GO

CREATE VIEW [dbo].[VPSO_TMV_AGG_DESCR_ART_GEMINI]
AS
WITH WatermarkUltimaEsecuzione AS (
    -- Lettura del timestamp dell'ultimo passaggio batch completato con successo
    SELECT 
        RT14_DITTA_CG18, 
        RT14_DATE_VALUE
    FROM dbo.RT14_VARIABILI_READYTEC WITH (NOLOCK)
    WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'
),
LogVariazioniRecenti AS (
    -- Raggruppamento dell'ultimo evento di log per ciascuna combinazione articolo/opzione
    SELECT 
        MO13.MO13_DITTA_CG18,
        MO13.MO13_CODART_MG66,
        ISNULL(MO13.MO13_OPZIONE_MG5E, '') AS MO13_OPZIONE_MG5E,
        MAX(MO13.MO13_DATALOG)             AS MO13_ULTIMO_LOG
    FROM dbo.MO13_LOGARTICOLI AS MO13 WITH (NOLOCK)
    WHERE (MO13.MO13_FIELDNAME = 'MG87_DESCART' OR MO13.MO13_FIELDNAME = 'MG66_DTCREAZ') 
      AND (MO13.MO13_INDTIPOOP = 0)
    GROUP BY 
        MO13.MO13_DITTA_CG18,
        MO13.MO13_CODART_MG66,
        ISNULL(MO13.MO13_OPZIONE_MG5E, '')
),
ArticoliModelloConfiguratore AS (
    -- Elenco univoco degli articoli modello formalmente configurati in CM15
    SELECT DISTINCT 
        CM15_DITTA_CG18, 
        CM15_CODARTMOD_MG66
    FROM dbo.CM15_CONFGCOMM WITH (NOLOCK)
)
-- =================================================================================================
-- CORPO PRINCIPALE: UNIONE DEGLI ARTICOLI VARIATI (DELTA) E DELLE BONIFICHE ARTICOLO MODELLO
-- =================================================================================================
SELECT 
    MG87.MG87_DITTA_CG18,
    MG87.MG87_CODART_MG66,
    MG87.MG87_OPZIONE_MG5E,
    MG87.MG87_DESCART,
    MG87.MG87_DESCARTEST
FROM dbo.MG66_ANAGRART AS MG66 WITH (NOLOCK)
INNER JOIN dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
    ON  MG66.MG66_DITTA_CG18 = MG87.MG87_DITTA_CG18 
    AND MG66.MG66_CODART     = MG87.MG87_CODART_MG66 
INNER JOIN WatermarkUltimaEsecuzione AS WM
    ON MG66.MG66_DITTA_CG18 = WM.RT14_DITTA_CG18 
INNER JOIN LogVariazioniRecenti AS LOGS
    ON  MG87.MG87_DITTA_CG18                  = LOGS.MO13_DITTA_CG18 
    AND MG87.MG87_CODART_MG66                 = LOGS.MO13_CODART_MG66 
    AND ISNULL(MG87.MG87_OPZIONE_MG5E, '')    = LOGS.MO13_OPZIONE_MG5E 
    AND LOGS.MO13_ULTIMO_LOG                 >= WM.RT14_DATE_VALUE 
INNER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK)
    ON  MG87.MG87_DITTA_CG18  = CM15.CM15_DITTA_CG18 
    AND MG87.MG87_CODART_MG66 = CM15.CM15_CODART_MG66
WHERE MG66.MG66_DITTA_CG18 = 1 
  AND MG87.MG87_LINGUA_MG52 = ''

UNION 

SELECT 
    MG87.MG87_DITTA_CG18,
    MG87.MG87_CODART_MG66,
    MG87.MG87_OPZIONE_MG5E,
    MG87.MG87_DESCART,
    MG87.MG87_DESCARTEST
FROM dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
INNER JOIN dbo.MG66_ANAGRART AS MG66 WITH (NOLOCK)
    ON  MG87.MG87_DITTA_CG18 = MG66.MG66_DITTA_CG18
    AND MG87.MG87_CODART_MG66 = MG66.MG66_CODART
LEFT JOIN ArticoliModelloConfiguratore AS MODELLO
    ON  MG87.MG87_DITTA_CG18  = MODELLO.CM15_DITTA_CG18
    AND MG87.MG87_CODART_MG66 = MODELLO.CM15_CODARTMOD_MG66
WHERE MG87.MG87_DESCART LIKE '%ARTICOLO MODELLO%' 
  AND MODELLO.CM15_CODARTMOD_MG66 IS NULL
  AND MG87.MG87_DITTA_CG18 = 1
  AND MG87.MG87_LINGUA_MG52 = '';
GO

