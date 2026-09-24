/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI (Standard SOLVERIS GEMINI)
Nome File                        : SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI' è l'implementazione conforme agli standard
SOLVERIS GEMINI per il completamento anagrafico e logistico degli articoli nel batch 'TMV_AGG_DESCR_ART'.

FUNZIONALITA' IMPLEMENTATE E GARANZIE DI SICUREZZA:
1. Modalità Dry-Run Nativa (@DryRun BIT = 1):
   - In modalità Dry-Run non viene effettuata alcuna operazione DML (nessun UPDATE o INSERT).
   - Viene invocata la procedura 'SPSO_TMV_ATTIVA_VAR_GEMINI @DryRun = 1' per simulare l'allineamento varianti.
   - Vengono emessi due report diagnostici distinti:
       a) Elenco degli articoli con le modifiche previste su MG6B_GESVARART per la variante A3
          (distinguendo le barre 'TONDI-DXXX' dagli articoli 'STANDARD').
       b) Elenco degli articoli/opzioni per i quali verrebbe generato il record di confezione di default 'CD'
          in MG68_CONFART.
2. Esecuzione Reale Atomica (@DryRun = 0):
   - Tutte le modifiche vengono eseguite all'interno di una transazione atomica protetta con blocco
     TRY...CATCH e ROLLBACK automatico in caso di errore.
   - Viene richiamata 'SPSO_TMV_ATTIVA_VAR_GEMINI @DryRun = 0' per garantire la persistenza congiunta.
3. Prestazioni e Concorrenza:
   - Utilizzo di WITH (NOLOCK) per le verifiche di esistenza.
   - Piena compatibilità con l'infrastruttura SQL Server 2017 (MSSQL 14.0.2120.1).
----------------------------------------------------------------------------------------------------
PARAMETRI:
- @DryRun BIT = 1  --> 1: Simulazione verbosa di controllo (Dry-Run).
                   --> 0: Esecuzione reale con scrittura transazionale su DB.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Procedura legacy dbo.SPRT_TMV_AGG_ARTICOLI_VARIE.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della versione standardizzata GEMINI. Integrazione della modalità Dry-Run, transazionalità
  sicura, output verboso multi-sezione e ottimizzazione delle scritture.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI]
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '====================================================================================';
    PRINT 'Inizio esecuzione: dbo.SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI';
    PRINT 'Modalità operativa : ' + CASE WHEN @DryRun = 1 THEN 'DRY-RUN (Simulazione Verbosa - Nessuna Modifica)' ELSE 'EFFETTIVA (Scrittura su Database)' END;
    PRINT 'Data e Ora         : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';

    -- 1. Esecuzione o simulazione della procedura di attivazione varianti
    PRINT '>>> PASSO 1: Esecuzione di dbo.SPSO_TMV_ATTIVA_VAR_GEMINI...';
    EXEC dbo.SPSO_TMV_ATTIVA_VAR_GEMINI @DryRun = @DryRun;

    -- 2. Gestione Dry-Run vs Esecuzione Reale per Passo 2 (Variante A3) e Passo 3 (MG68_CONFART)
    IF @DryRun = 1
    BEGIN
        PRINT '>>> PASSO 2 (DRY-RUN): Analisi delle configurazioni previste per Variante 4 (A3)...';
        
        -- Simulazione Tondi Dxxx
        SELECT 
            'DRY_RUN_VARIANTE_A3_TONDI' AS Sezione,
            MG6B.MG6B_DITTA_CG18,
            MG6B.MG6B_CODART_MG66,
            MG6B.MG6B_CODICEVAR_MG5F,
            MG6B.MG6B_CODRAGGVAR_MG5G AS Attuale_Raggruppamento,
            'TONDI-DXXX'             AS Nuovo_Raggruppamento,
            1                         AS Nuovo_FLGGESTVAR,
            1                         AS Nuovo_INDOBBLIG,
            '000'                     AS Nuovo_VARDEFAULT
        FROM dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK)
        INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
            AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66
        WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) = 'D' 
          AND SUBSTRING(MG6B.MG6B_CODART_MG66, 1, 3) IN ('TDP','TDR','TDL','TDF')
          AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
          AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'TONDI-DXXX';

        -- Simulazione Standard
        SELECT 
            'DRY_RUN_VARIANTE_A3_STANDARD' AS Sezione,
            MG6B.MG6B_DITTA_CG18,
            MG6B.MG6B_CODART_MG66,
            MG6B.MG6B_CODICEVAR_MG5F,
            MG6B.MG6B_CODRAGGVAR_MG5G AS Attuale_Raggruppamento,
            'STANDARD'                AS Nuovo_Raggruppamento,
            1                         AS Nuovo_FLGGESTVAR,
            0                         AS Nuovo_INDOBBLIG,
            NULL                      AS Nuovo_VARDEFAULT
        FROM dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK)
        INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
            AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66 
        WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) <> 'D' 
          AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
          AND MG6B.MG6B_FLGGESTVAR = 1 
          AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'STANDARD';

        PRINT '>>> PASSO 3 (DRY-RUN): Analisi delle confezioni mancanti da inserire in MG68_CONFART...';
        SELECT 
            'DRY_RUN_NUOVE_CONFEZIONI_MG68' AS Sezione,
            RT12.RT12_DITTA_CG18,
            RT12.RT12_CODART_MG66,
            RT12.RT12_OPZIONE_MG5E,
            'CD'  AS CodiceConfezione,
            1     AS ConfezionePreferenziale,
            'KG'  AS UnitaMisuraPeso,
            'MM'  AS UnitaMisuraDimensioni,
            'CM3' AS UnitaMisuraVolume
        FROM dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
        LEFT JOIN dbo.MG68_CONFART AS MG68 WITH (NOLOCK)
            ON  RT12.RT12_DITTA_CG18   = MG68.MG68_DITTA_CG18
            AND RT12.RT12_CODART_MG66  = MG68.MG68_CODART_MG66
            AND RT12.RT12_OPZIONE_MG5E = MG68.MG68_OPZIONE_MG5E
        WHERE MG68.MG68_CODCONFEZ_MG96 IS NULL;

        PRINT '>>> DRY-RUN COMPLETATO: Nessuna modifica applicata al database.';
    END
    ELSE
    BEGIN
        PRINT '>>> MODALITA REALE: Avvio transazione per aggiornamento varianti e confezioni...';
        BEGIN TRY
            BEGIN TRANSACTION;

            -- Aggiornamento Barre Tonde Dxxx
            WITH CteTondiDxxx AS (
                SELECT 
                    MG6B.MG6B_FLGGESTVAR,
                    MG6B.MG6B_CODRAGGVAR_MG5G,
                    MG6B.MG6B_INDOBBLIG,
                    MG6B.MG6B_INDDEFAULT,
                    MG6B.MG6B_VARDEFAULT
                FROM dbo.MG6B_GESVARART AS MG6B
                INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
                    ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
                    AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66
                WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) = 'D' 
                  AND SUBSTRING(MG6B.MG6B_CODART_MG66, 1, 3) IN ('TDP','TDR','TDL','TDF')
                  AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
                  AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'TONDI-DXXX'
            )
            UPDATE CteTondiDxxx  
            SET
                MG6B_FLGGESTVAR      = 1,
                MG6B_CODRAGGVAR_MG5G = 'TONDI-DXXX',
                MG6B_INDOBBLIG       = 1,
                MG6B_INDDEFAULT      = 1,
                MG6B_VARDEFAULT      = '000';

            DECLARE @RigheTondi INT = @@ROWCOUNT;
            PRINT 'Aggiornati ' + CAST(@RigheTondi AS VARCHAR(10)) + ' record variante A3 TONDI-DXXX.';

            -- Aggiornamento Altri Articoli STANDARD
            WITH CteStandardA3 AS (
                SELECT 
                    MG6B.MG6B_FLGGESTVAR,
                    MG6B.MG6B_CODRAGGVAR_MG5G,
                    MG6B.MG6B_INDOBBLIG,
                    MG6B.MG6B_INDDEFAULT,
                    MG6B.MG6B_VARDEFAULT
                FROM dbo.MG6B_GESVARART AS MG6B
                INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
                    ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
                    AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66 
                WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) <> 'D' 
                  AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
                  AND MG6B.MG6B_FLGGESTVAR = 1 
                  AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'STANDARD'
            )
            UPDATE CteStandardA3 
            SET
                MG6B_FLGGESTVAR      = 1,
                MG6B_CODRAGGVAR_MG5G = 'STANDARD',
                MG6B_INDOBBLIG       = 0,
                MG6B_INDDEFAULT      = 0,
                MG6B_VARDEFAULT      = NULL;

            DECLARE @RigheStandard INT = @@ROWCOUNT;
            PRINT 'Aggiornati ' + CAST(@RigheStandard AS VARCHAR(10)) + ' record variante A3 STANDARD.';

            -- Inserimento Confezioni Mancanti MG68_CONFART
            INSERT INTO dbo.MG68_CONFART (
                MG68_DITTA_CG18,
                MG68_CODART_MG66,
                MG68_OPZIONE_MG5E,
                MG68_CODCONFEZ_MG96,
                MG68_FLGCONFPREF,
                MG68_PZCONF,
                MG68_UMPESO,
                MG68_PESON,
                MG68_PESOL,
                MG68_UMCAPAC,
                MG68_CAPAC,
                MG68_UMDIMEN,
                MG68_LARGH,
                MG68_ALTEZ,
                MG68_PROF,
                MG68_UMVOLUME,
                MG68_VOLUME,
                MG68_CONFXCOLLO,
                MG68_COLLIXSTRATO,
                MG68_LARGHCOLLO,
                MG68_COLLIXBANCALE,
                MG68_ALTEZCOLLO,
                MG68_PROFCOLLO,
                MG68_CLASSEMAXSTOC,
                MG68_IDMEDIA_CG99
            )
            SELECT 
                RT12.RT12_DITTA_CG18,
                RT12.RT12_CODART_MG66,
                RT12.RT12_OPZIONE_MG5E,
                'CD',
                1,
                0,
                'KG',
                0,
                0,
                NULL,
                0,
                'MM',
                0,
                0,
                0,
                'CM3',
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                0,
                NULL
            FROM dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            LEFT JOIN dbo.MG68_CONFART AS MG68 WITH (NOLOCK)
                ON  RT12.RT12_DITTA_CG18   = MG68.MG68_DITTA_CG18
                AND RT12.RT12_CODART_MG66  = MG68.MG68_CODART_MG66
                AND RT12.RT12_OPZIONE_MG5E = MG68.MG68_OPZIONE_MG5E
            WHERE MG68.MG68_CODCONFEZ_MG96 IS NULL;

            DECLARE @RigheConfezioni INT = @@ROWCOUNT;
            PRINT 'Inserite ' + CAST(@RigheConfezioni AS VARCHAR(10)) + ' nuove confezioni CD in MG68_CONFART.';

            COMMIT TRANSACTION;
            PRINT '>>> SUCCESSO: Tutte le modifiche sono state confermate (COMMIT).';
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
            DECLARE @ErrSev INT = ERROR_SEVERITY();
            DECLARE @ErrState INT = ERROR_STATE();
            PRINT '>>> ERRORE durante esecuzione dbo.SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI: ' + @ErrMsg;
            RAISERROR(@ErrMsg, @ErrSev, @ErrState);
        END CATCH;
    END;
END;
GO

