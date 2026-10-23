-- =================================================================================================================================
-- Cartiglio Narrativo Obbligatorio (Standard di Codifica SOLVERIS - Progetto TMV)
-- =================================================================================================================================
-- Data e Ora Creazione : 2026-10-23 13:48
-- Autore               : SOLVERIS - Bandera Marco
-- Oggetto SQL          : [dbo].[RT13_NKE_DOCS_GEMINI] & [dbo].[RT13_NKE_LOG_DETAIL_GEMINI]
-- Tipologia Oggetto    : Tabelle DDL (Strutture Dati di Tracciabilità ed Audit Log)
-- Versione Compatibile : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1)
-- Ambiente Target      : DBTMV (Produzione / Staging)
--
-- STORIA E CONTESTO DI BUSINESS:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Nell'ambito del risanamento del processo di integrazione tra l'ERP Gamma Enterprise e il generatore CAD robotizzato NKE,
-- sorge la necessità di tracciare in modo bidirezionale la relazione tra le richieste fisiche inviate al robot e gli ordini di vendita
-- che ne hanno determinato il fabbisogno.
--
-- PROBLEMA RISOLTO:
-- Per evitare il sovraccarico del motore Autodesk Inventor (Anti-Goal AG3), la coda operativa RT13_NKE deve continuare a
-- deduplicare le richieste per variante tecnica (MG87_GUID). Tuttavia, l'Ufficio Tecnico e i disegnatori necessitano di visualizzare
-- all'interno del Monitor Intranet a quale specifico Ordine Cliente (es. CO 5519) e a quale committente (es. TUXOR S.P.A.)
-- appartenga ciascun disegno in elaborazione o storicizzato.
--
-- Le due tabelle create dal presente script rispondono a questo duplice obiettivo:
-- 1. [dbo].[RT13_NKE_DOCS_GEMINI]: Modella la relazione 1-a-Molti tra la singola richiesta deduplicata (MG87_GUID) e le molteplici
--    righe di documenti Gamma (DO11/DO30) da cui è scaturita, conservando NumDoc, Riga, Data Ordine e Ragione Sociale.
-- 2. [dbo].[RT13_NKE_LOG_DETAIL_GEMINI]: Fornisce un audit trail completo di ogni singola chiamata HTTP effettuata dal Servizio
--    Windows verso le WebAPI NKE, memorizzando i tempi di risposta (latenza in ms), il payload JSON inviato, la risposta ricevuta,
--    il codice HTTP e, in caso di forzatura manuale, l'identificativo dell'operatore e l'indirizzo IP della postazione richiedente.
-- =================================================================================================================================

USE [DBTMV];
GO

-- =================================================================================================================================
-- TABELLA 1: [dbo].[RT13_NKE_DOCS_GEMINI] (Tracciabilità Documentale 1-a-Molti)
-- =================================================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'RT13_NKE_DOCS_GEMINI' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.RT13_NKE_DOCS_GEMINI (
        ID_DOC_NKE             BIGINT IDENTITY(1,1) NOT NULL,
        MG87_GUID              UNIQUEIDENTIFIER NOT NULL,
        DO11_DITTA_CG18        DECIMAL(18,0) NOT NULL,
        DO11_DOCUM_MG36        VARCHAR(20) NOT NULL,
        DO11_NUMDOC            INT NOT NULL,
        DO11_SEZDOC            VARCHAR(3) NOT NULL,
        DO11_ANNODOC           SMALLINT NOT NULL,
        DO11_DATADOC           DATETIME NOT NULL,
        DO30_PROGRIGA          INT NOT NULL,
        DO30_CODART_MG66       CHAR(25) NOT NULL,
        DO30_OPZIONE_MG5E      CHAR(20) NOT NULL,
        RAGIONE_SOCIALE        VARCHAR(100) NULL,
        DATA_INSERIMENTO       DATETIME NOT NULL CONSTRAINT DF_RT13_DOCS_DATA DEFAULT (GETDATE()),
        CONSTRAINT PK_RT13_NKE_DOCS_GEMINI PRIMARY KEY CLUSTERED (ID_DOC_NKE ASC)
    );

    -- Indice non clusterizzato su MG87_GUID per consentire join veloci dal Dispatcher e dal Monitor
    CREATE NONCLUSTERED INDEX IX_RT13_DOCS_MG87_GUID 
    ON dbo.RT13_NKE_DOCS_GEMINI (MG87_GUID) 
    INCLUDE (DO11_NUMDOC, DO11_SEZDOC, DO11_ANNODOC, DO30_PROGRIGA, RAGIONE_SOCIALE);

    -- Indice su Numero Ordine per ricerche rapide da pannello web
    CREATE NONCLUSTERED INDEX IX_RT13_DOCS_NUMDOC 
    ON dbo.RT13_NKE_DOCS_GEMINI (DO11_NUMDOC, DO11_ANNODOC) 
    INCLUDE (MG87_GUID, DO30_PROGRIGA, DO30_CODART_MG66);

    PRINT 'Tabella [dbo].[RT13_NKE_DOCS_GEMINI] creata con successo con relativi indici.';
END
ELSE
BEGIN
    PRINT 'Tabella [dbo].[RT13_NKE_DOCS_GEMINI] già presente nel database DBTMV.';
END
GO

-- =================================================================================================================================
-- TABELLA 2: [dbo].[RT13_NKE_LOG_DETAIL_GEMINI] (Audit Trail Dettagliato & Diagnostica API)
-- =================================================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'RT13_NKE_LOG_DETAIL_GEMINI' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.RT13_NKE_LOG_DETAIL_GEMINI (
        ID_LOG                 BIGINT IDENTITY(1,1) NOT NULL,
        MG87_GUID              UNIQUEIDENTIFIER NOT NULL,
        MOMENTO_CHIAMATA       DATETIME NOT NULL CONSTRAINT DF_RT13_LOG_DETAIL_MOMENTO DEFAULT (GETDATE()),
        LATENCY_MS             INT NOT NULL CONSTRAINT DF_RT13_LOG_DETAIL_LATENCY DEFAULT (0),
        HTTP_STATUS            INT NOT NULL CONSTRAINT DF_RT13_LOG_DETAIL_STATUS DEFAULT (0),
        RICHIESTA_JSON         NVARCHAR(MAX) NULL,
        RISPOSTA_JSON          NVARCHAR(MAX) NULL,
        ESITO_GENERATO         BIT NOT NULL CONSTRAINT DF_RT13_LOG_DETAIL_ESITO DEFAULT (0),
        MESSAGGIO_ERRORE       NVARCHAR(MAX) NULL,
        OPERATORE              VARCHAR(50) NULL CONSTRAINT DF_RT13_LOG_DETAIL_OPERATORE DEFAULT ('SYSTEM_AUTO'),
        IP_CLIENT              VARCHAR(45) NULL CONSTRAINT DF_RT13_LOG_DETAIL_IP DEFAULT ('127.0.0.1'),
        CONSTRAINT PK_RT13_NKE_LOG_DETAIL_GEMINI PRIMARY KEY CLUSTERED (ID_LOG ASC)
    );

    -- Indice temporale per query paginata dei log ordinata per momento chiamata decrescente
    CREATE NONCLUSTERED INDEX IX_RT13_LOG_DETAIL_MOMENTO 
    ON dbo.RT13_NKE_LOG_DETAIL_GEMINI (MOMENTO_CHIAMATA DESC) 
    INCLUDE (MG87_GUID, LATENCY_MS, HTTP_STATUS, ESITO_GENERATO, OPERATORE);

    -- Indice per correlazione veloce su MG87_GUID
    CREATE NONCLUSTERED INDEX IX_RT13_LOG_DETAIL_MG87 
    ON dbo.RT13_NKE_LOG_DETAIL_GEMINI (MG87_GUID, ESITO_GENERATO);

    PRINT 'Tabella [dbo].[RT13_NKE_LOG_DETAIL_GEMINI] creata con successo con relativi indici.';
END
ELSE
BEGIN
    PRINT 'Tabella [dbo].[RT13_NKE_LOG_DETAIL_GEMINI] già presente nel database DBTMV.';
END
GO

-- =================================================================================================================================
-- INDICE ESSENZIALE PER PERFORMANCE DELTA ENGINE SU [dbo].[RT13_NKE_LOG]
-- =================================================================================================================================
-- La tabella di log standard contiene oltre 1.1 milioni di righe storiche.
-- Per evitare costose scansioni tabellari (Table Scan) ad ogni esecuzione della procedura di alimentazione coda,
-- si crea l'indice coprente su MG87_GUID e flag RT13_FILE_GENERATO.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RT13_NKE_LOG_MG87_GENERATO' AND object_id = OBJECT_ID('dbo.RT13_NKE_LOG'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RT13_NKE_LOG_MG87_GENERATO 
    ON dbo.RT13_NKE_LOG (MG87_GUID, RT13_FILE_GENERATO);

    PRINT 'Indice [IX_RT13_NKE_LOG_MG87_GENERATO] creato con successo su RT13_NKE_LOG.';
END
GO
