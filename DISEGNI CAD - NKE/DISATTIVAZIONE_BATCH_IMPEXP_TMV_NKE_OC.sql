-- =================================================================================================================================
-- Cartiglio Narrativo Obbligatorio (Standard di Codifica SOLVERIS - Progetto TMV)
-- =================================================================================================================================
-- Data e Ora Creazione : 2026-10-23 12:25
-- Autore               : SOLVERIS - Bandera Marco
-- Oggetto SQL          : Script DDL/DML - Disattivazione Tracciato ImpExp TMV_NKE_OC
-- Tipologia Oggetto    : Script di Configurazione Batch ERP
-- Versione Compatibile : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1)
-- Ambiente Target      : DBTMV (Produzione / Staging)
--
-- MOTIVAZIONE OPERATIVA:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- A seguito del rilascio della nuova Stored Procedure [dbo].[SPSO_NKE_ALIMENTA_CODA_GEMINI], l'estrazione dati dal modulo
-- ImpExp di Gamma Enterprise tramite il tracciato 'TMV_NKE_OC' risulta formalmente deprecata e obsoleta.
-- Tale tracciato presentava il grave difetto di filtrare esclusivamente lo stato riga 10045 ('Generato'), perdendo tutte le
-- modifiche e gli ordini approvati.
-- Per evitare inserimenti concorrenti e ridondanti nella tabella RT13_NKE, il passo 2 dell'insieme 'TMV_NKE' viene disattivato
-- impostando il flag IE34_FLGATTIVO = 0.
-- =================================================================================================================================

USE [DBTMV];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Verifica stato attuale prima della modifica
    SELECT 
        IE34_INSIEME_IE33   AS [Insieme],
        IE34_PROG           AS [Prog],
        IE34_DESCRIZIONE    AS [Descrizione],
        IE34_TRACCIATO_IE25 AS [Tracciato],
        IE34_FLGATTIVO      AS [Stato Attivo Attuale (Prima)]
    FROM dbo.IE34_INSIEMIDETT WITH (NOLOCK)
    WHERE IE34_INSIEME_IE33 = 'TMV_NKE' 
      AND IE34_TRACCIATO_IE25 = 'TMV_NKE_OC';

    -- Disattivazione del tracciato obsoleto
    UPDATE dbo.IE34_INSIEMIDETT
    SET IE34_FLGATTIVO = 0
    WHERE IE34_INSIEME_IE33 = 'TMV_NKE' 
      AND IE34_TRACCIATO_IE25 = 'TMV_NKE_OC';

    -- Verifica stato post modifica
    SELECT 
        IE34_INSIEME_IE33   AS [Insieme],
        IE34_PROG           AS [Prog],
        IE34_DESCRIZIONE    AS [Descrizione],
        IE34_TRACCIATO_IE25 AS [Tracciato],
        IE34_FLGATTIVO      AS [Stato Attivo Nuovo (Dopo)]
    FROM dbo.IE34_INSIEMIDETT WITH (NOLOCK)
    WHERE IE34_INSIEME_IE33 = 'TMV_NKE' 
      AND IE34_TRACCIATO_IE25 = 'TMV_NKE_OC';

    COMMIT TRANSACTION;
    PRINT 'Disattivazione del tracciato TMV_NKE_OC completata con successo.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR('Errore durante la disattivazione del tracciato: %s', 16, 1, @Msg);
END CATCH;
GO

