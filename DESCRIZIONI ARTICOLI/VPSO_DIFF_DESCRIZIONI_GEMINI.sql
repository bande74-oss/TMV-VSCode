/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 09:50
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Vista dbo.VPSO_DIFF_DESCRIZIONI_GEMINI
Nome File                        : VPSO_DIFF_DESCRIZIONI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La vista 'dbo.VPSO_DIFF_DESCRIZIONI_GEMINI' è uno strumento di monitoraggio e sintesi direzionale
basato sulla tabella globale di audit 'dbo.SO_DIFF_DESCRIZIONI_GEMINI'.

OBIETTIVO DI CONTROLLO:
Permette ai responsabili dell'Ufficio Tecnico, della Qualità e dei Sistemi Informativi di avere
una fotografia immediata dello stato di disallineamento descrittivo della base dati, aggregato per:
- Famiglia / Prefisso articolo (es. TD, TS, T-, VE, D-, ecc.).
- Volume totale di anomalie riscontrate.
- Dettaglio anomalie su lingua italiana (SHORT) ed estera (LONG).
- Conteggio esatto degli articoli privi di traduzione inglese (INSERT 'LNG').
- Volume degli articoli già bonificati rispetto a quelli ancora pendenti.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio iniziale della vista aggregata di monitoraggio discrepanze.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[VPSO_DIFF_DESCRIZIONI_GEMINI]', 'V') IS NOT NULL
    DROP VIEW [dbo].[VPSO_DIFF_DESCRIZIONI_GEMINI];
GO

CREATE OR ALTER VIEW [dbo].[VPSO_DIFF_DESCRIZIONI_GEMINI]
AS
SELECT 
    Ditta,
    Prefisso,
    MotivoDifferenza,
    COUNT(*) AS TotaleArticoli,
    SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END) AS TotShortDaAggiornare,
    SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END) AS TotLongDaAggiornare,
    SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END) AS TotLongDaInserire,
    SUM(CASE WHEN DataAdeguamento IS NOT NULL THEN 1 ELSE 0 END) AS TotArticoliAdeguati,
    SUM(CASE WHEN DataAdeguamento IS NULL THEN 1 ELSE 0 END) AS TotArticoliPendenti,
    MIN(DataRilevamento) AS PrimaDataRilevamento,
    MAX(DataAdeguamento) AS UltimaDataAdeguamento
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY Ditta, Prefisso, MotivoDifferenza;
GO

