/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 18:20
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : SCRIPT DI LANCIO: Ricalcolo Globale Diagnostico in Modalità TEST
Nome File                        : LANCIO_TEST_FULL_RUN_DIAGNOSTICA_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Questo script è stato predisposto per eseguire il ricalcolo e la ripopolazione integrale da zero
della tabella di audit e staging 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' su TUTTA la base dati aziendale
(oltre 652.000 combinazioni articolo/opzione censite in MG87_ARTDESC per articoli configurati CM15).

MODALITÀ DI ESECUZIONE: TEST / DRY-RUN (SICUREZZA TOTALE)
- Lo script opera in modalità di SOLA LETTURA sulle tabelle anagrafiche e di produzione Gamma Enterprise.
- Nessuna istruzione di modifica (UPDATE, INSERT, DELETE) viene inviata alla tabella anagrafica 'dbo.MG87_ARTDESC'.
- L'unica tabella modificata è 'dbo.SO_DIFF_DESCRIZIONI_GEMINI', che viene preliminarmente svuotata (TRUNCATE)
  e ripopolata esclusivamente con le discrepanze reali calcolate tramite i nuovi algoritmi corretti:
  1. Preservazione integrale dei ritorni a capo CR+LF (CHAR(13)+CHAR(10)) interni nativi di Gamma Enterprise.
  2. Protezione del simbolo diametro 'Ø' da spezzamenti anomali.
  3. Confronto semantico normalizzato che ignora gli spazi residui di fine riga, azzerando i 350.000 falsi positivi.

DURATA STIMATA: Circa 15-20 minuti.
Lo stato di avanzamento viene notificato prefisso per prefisso nel pannello Messaggi di SSMS.
Al termine dell'elaborazione, vengono automaticamente eseguiti i CHECK diagnostici di controllo.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '====================================================================================';
PRINT 'AVVIO RICALCOLO GLOBALE DIAGNOSTICO IN MODALITÀ TEST (SOLVERIS GEMINI)';
PRINT 'Data e Ora di Avvio: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT 'Ambito             : INTERO DATABASE AZIENDALE (Tutte le Famiglie CM15)';
PRINT 'Modalità           : TEST / DRY-RUN (Zero scritture su anagrafica MG87_ARTDESC)';
PRINT '====================================================================================';
GO

-- =================================================================================================
-- FASE 1: ESECUZIONE RICALCOLO COMPLETO CON RIPOPOLAZIONE TOTALE DI SO_DIFF_DESCRIZIONI_GEMINI
-- =================================================================================================
-- Opzione 1: Chiamata alla SP di Adeguamento in modalità Dry-Run (@DryRun = 1) con ricalcolo forzato (@RicalcolaAudit = 1)
-- Questa procedura lancia preliminarmente il TRUNCATE e la ripopolazione totale di SO_DIFF_DESCRIZIONI_GEMINI
-- tramite SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI e successivamente stampa il report riassuntivo a video.

EXEC dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI
    @Ditta              = 1,
    @DryRun             = 1,    -- 1 = TEST / DRY-RUN (nessuna alterazione a MG87)
    @Prefisso           = NULL, -- NULL = Intero database (tutti i prefissi a 3 caratteri)
    @MotivoDifferenza   = NULL, -- NULL = Tutte le tipologie di anomalia
    @AlimentaRT12       = 0,    -- 0 = Nessuna scrittura in tabella frontiera RT12
    @BatchSize          = 5000,
    @RicalcolaAudit     = 1;    -- 1 = Esegue TRUNCATE TABLE dbo.SO_DIFF_DESCRIZIONI_GEMINI e ripopola da zero
GO

PRINT '';
PRINT '====================================================================================';
PRINT 'ELABORAZIONE TEST COMPLETATA. AVVIO REPORTISTICA E CONTROLLI DI QUALITÀ...';
PRINT '====================================================================================';
GO

-- =================================================================================================
-- FASE 2: SUITE DI CONTROLLI AUTOMATICI POST-ELABORAZIONE
-- =================================================================================================

-- CHECK 1: Sintesi Generale per Tipologia di Intervento
PRINT '>>> [CHECK 1] Sintesi per Tipologia di Discrepanza Riscontrata:';
SELECT 
    MotivoDifferenza,
    SUM(TotaleArticoli)       AS TotaleArticoli,
    SUM(TotShortDaAggiornare) AS ShortDaAggiornare,
    SUM(TotLongDaAggiornare)  AS LongDaAggiornare,
    SUM(TotLongDaInserire)    AS LongDaInserire
FROM dbo.VPSO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY MotivoDifferenza
ORDER BY TotaleArticoli DESC;
GO

-- CHECK 1-BIS: Prime 15 Famiglie con Maggior Numero di Discrepanze
PRINT '>>> [CHECK 1-BIS] Top 15 Famiglie per Volume di Discrepanze:';
SELECT TOP 15
    Prefisso,
    SUM(TotaleArticoli)       AS TotaleDiscrepanze,
    SUM(TotShortDaAggiornare) AS ShortDaAggiornare,
    SUM(TotLongDaAggiornare)  AS LongDaAggiornare,
    SUM(TotLongDaInserire)    AS LongDaInserire
FROM dbo.VPSO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY Prefisso
ORDER BY SUM(TotaleArticoli) DESC;
GO

-- CHECK 2: Controllo Articolo Target Principale TDP04B7-M1254-
PRINT '>>> [CHECK 2] Verifica Articolo Target Principale (TDP04B7-M1254-):';
SELECT 
    CodiceArticolo,
    Prefisso,
    ShortAttuale,
    ShortNuovo,
    LongAttuale,
    LongNuovo,
    MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE CodiceArticolo = 'TDP04B7-M1254-';
GO

-- CHECK 3: Verifica Refusi Storici UNS (UNS S020910)
PRINT '>>> [CHECK 3] Conteggio Articoli con Refuso Storico UNS:';
SELECT 
    COUNT(*) AS TotaleArticoliConRefusoUNS
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE MotivoDifferenza = 'BONIFICA_REFUSO_UNS';
GO

-- CHECK 4: Campionamento Formattazione Famiglia Dadi (D--)
PRINT '>>> [CHECK 4] Campionamento Formattazione Dadi (D--):';
SELECT TOP 15
    CodiceArticolo,
    Prefisso,
    ShortAttuale,
    ShortNuovo,
    MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE Prefisso = 'D--'
ORDER BY CodiceArticolo;
GO

-- CHECK 5: Verifica Residui Descrittivi di Sistema (Modello o Min.0)
PRINT '>>> [CHECK 5] Conteggio Articoli con Residuo Descrittivo Modello/Min.0:';
SELECT 
    COUNT(*) AS TotaleArticoliConTestoModello
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE MotivoDifferenza = 'BONIFICA_TESTO_MODELLO';
GO

PRINT '====================================================================================';
PRINT 'REPORTISTICA CONCLUSIVA TERMINATA CON SUCCESSO.';
PRINT 'Data e Ora di Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';
GO

