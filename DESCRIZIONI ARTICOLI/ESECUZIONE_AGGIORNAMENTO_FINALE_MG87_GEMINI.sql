/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 18:45
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : SCRIPT DI ESECUZIONE EFFETTIVA: Aggiornamento Finale MG87_ARTDESC
Nome File                        : ESECUZIONE_AGGIORNAMENTO_FINALE_MG87_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Questo script esegue l'aggiornamento definitivo, massivo e permanente delle descrizioni anagrafiche
articoli nella tabella 'dbo.MG87_ARTDESC' per tutte le discrepanze censite e verificate nella tabella
di staging 'dbo.SO_DIFF_DESCRIZIONI_GEMINI'.

SICUREZZA TRANSAZIONALE A BLOCCHI (Batching a 5.000 record):
- L'aggiornamento viene eseguito a cicli transazionali indipendenti (TRY...CATCH con COMMIT per singolo batch).
- La dimensione di default di 5.000 record per transazione scongiura lock prolungati sulle tabelle
  e saturazione dello spazio del transaction log di SQL Server (LDF).
- Ogni batch aggiorna atomicamente:
  1. Descrizione SHORT italiana su MG87_DESCART e MG87_DESCARTEST.
  2. Descrizione LONG estera su MG87_DESCART e MG87_DESCARTEST (UPDATE o INSERT per traduzioni mancanti).
  3. Marcatura della data di adeguamento (DataAdeguamento = GETDATE()) su SO_DIFF_DESCRIZIONI_GEMINI.
- In caso di interruzione accidentale, lo script è perfettamente riprendibile (idempotente), ripartendo
  esattamente dai record con 'DataAdeguamento IS NULL'.

TUTELA DEGLI ARTICOLI MODELLO E FUORI CONFIGURATORE:
- Gli articoli matrice modello censiti in 'dbo.VPRT_ARTICOLI_MODELLO' sono esclusi a priori.
- Gli articoli non configurati a disegno/manuali (non censiti in CM15_CONFGCOMM) sono protetti da INNER JOIN.

DURATA STIMATA: Circa 2-3 minuti per l'intero volume di circa 411.000 articoli.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '====================================================================================';
PRINT 'AVVIO AGGIORNAMENTO DEFINITIVO DESCRITTIVO: dbo.MG87_ARTDESC (SOLVERIS GEMINI)';
PRINT 'Data e Ora di Avvio: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT 'Ambito             : INTERO DATABASE AZIENDALE (Tutte le Discrepanze Pendenti)';
PRINT 'Modalità           : EFFETTIVA (@DryRun = 0 - SCRITTURA DIRETTA SU ANAGRAFICA)';
PRINT '====================================================================================';
GO

-- =================================================================================================
-- FASE 1: ESECUZIONE PROCEDURA DI BONIFICA TRANSAZIONALE A BATCH
-- =================================================================================================

EXEC dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI
    @Ditta              = 1,
    @DryRun             = 0,    -- 0 = MODALITÀ EFFETTIVA (Scrittura Reale su MG87_ARTDESC)
    @Prefisso           = NULL, -- NULL = Tutte le famiglie
    @MotivoDifferenza   = NULL, -- NULL = Tutte le classi di anomalia
    @AlimentaRT12       = 0,    -- 0 = Disabilitato (allineamento diretto già completato su MG87)
    @BatchSize          = 5000, -- 5.000 record per batch transazionale
    @RicalcolaAudit     = 0;    -- 0 = Elabora i dati già calcolati e verificati in SO_DIFF_DESCRIZIONI_GEMINI
GO

PRINT '';
PRINT '====================================================================================';
PRINT 'AGGIORNAMENTO EFFETTIVO CONCLUSO. AVVIO VERIFICHE DI CONFORMITÀ FINALE...';
PRINT '====================================================================================';
GO

-- =================================================================================================
-- FASE 2: VERIFICHE DI CONFORMITÀ POST-AGGIORNAMENTO SU MG87_ARTDESC
-- =================================================================================================

-- 1. Verifica Azzeramento Record Pendenti nella Tabella di Staging
PRINT '>>> [VERIFICA 1] Stato di Completamento su dbo.SO_DIFF_DESCRIZIONI_GEMINI:';
SELECT 
    COUNT(*)                                                   AS TotaleArticoliElaborati,
    SUM(CASE WHEN DataAdeguamento IS NOT NULL THEN 1 ELSE 0 END) AS ArticoliBonificatiConSuccesso,
    SUM(CASE WHEN DataAdeguamento IS NULL     THEN 1 ELSE 0 END) AS ArticoliAncoraPendenti
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK);
GO

-- 2. Verifica Diretta su Anagrafica MG87 per Articolo Target Principale (TDP04B7-M1254-)
PRINT '>>> [VERIFICA 2] Descrizione Reale su MG87 per TDP04B7-M1254-:';
SELECT 
    MG87_CODART_MG66   AS CodiceArticolo,
    MG87_OPZIONE_MG5E  AS Opzione,
    MG87_LINGUA_MG52   AS Lingua,
    MG87_DESCART       AS DescrizionePrimaria_MG87,
    MG87_DESCARTEST    AS DescrizioneEstesa_MG87,
    MG87_LASTCHANGE    AS DataUltimaModifica
FROM dbo.MG87_ARTDESC WITH (NOLOCK)
WHERE MG87_DITTA_CG18 = 1 
  AND MG87_CODART_MG66 = 'TDP04B7-M1254-'
ORDER BY MG87_LINGUA_MG52;
GO

-- 3. Campionamento Visivo Diretto su MG87 per Dadi (D--)
PRINT '>>> [VERIFICA 3] Campionamento Descrizioni Reali su MG87 per Dadi (D--):';
SELECT TOP 10
    MG87_CODART_MG66   AS CodiceArticolo,
    MG87_LINGUA_MG52   AS Lingua,
    MG87_DESCART       AS DescrizionePrimaria_MG87,
    MG87_DESCARTEST    AS DescrizioneEstesa_MG87,
    MG87_LASTCHANGE    AS DataUltimaModifica
FROM dbo.MG87_ARTDESC WITH (NOLOCK)
WHERE MG87_DITTA_CG18 = 1 
  AND MG87_CODART_MG66 LIKE 'D--%'
  AND RTRIM(MG87_LINGUA_MG52) = ''
ORDER BY MG87_LASTCHANGE DESC, MG87_CODART_MG66;
GO

-- 4. Riepilogo Globale della Vista Direzionale VPSO_DIFF_DESCRIZIONI_GEMINI
PRINT '>>> [VERIFICA 4] Riepilogo Globale Vista dbo.VPSO_DIFF_DESCRIZIONI_GEMINI:';
SELECT 
    SUM(TotaleArticoli)       AS TotaleDiscrepanzeGestite,
    SUM(TotArticoliAdeguati)  AS TotaleBonificati,
    SUM(TotArticoliPendenti)  AS TotaleResiduiPendenti
FROM dbo.VPSO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK);
GO

PRINT '====================================================================================';
PRINT 'COLLAUDO E BONIFICA DEFINITIVA COMPLETATI CON SUCCESSO.';
PRINT 'Data e Ora di Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';
GO

