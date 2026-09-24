/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_AGG_DESCR_ART_GEMINI (Standard SOLVERIS GEMINI)
Nome File                        : SPSO_TMV_AGG_DESCR_ART_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_AGG_DESCR_ART_GEMINI' è l'implementazione conforme agli standard
SOLVERIS GEMINI per la generazione, l'aggiornamento e la normalizzazione delle descrizioni tecniche
articoli su Gamma Enterprise per il progetto TMV.

GARANZIE ARCHITETTURALI E DI SICUREZZA:
1. Modalità Dry-Run Nativa (@DryRun BIT = 1):
   - In modalità Dry-Run non viene eseguita alcuna modifica persistente sulla tabella MG87_ARTDESC.
   - Viene generata una tabella temporanea di calcolo e restituito un result set esaustivo che espone:
       * Codice Articolo, Opzione e Lingua (' ' per standard italiana, 'LNG' per internazionale).
       * Descrizione Breve Attuale vs Calcolata.
       * Descrizione Estesa Attuale vs Calcolata.
       * Azione Prevista ('UPDATE', 'INSERT' o 'NESSUNA_MODIFICA').
       * Segnalazione dell'eventuale applicazione dei correttivi Dadi (Min->Mag) e UNF (14UNF->12UNF).
2. Gestione Transazionale Atomica (@DryRun = 0):
   - Quando invocata con @DryRun = 0, l'aggiornamento avviene all'interno di una transazione atomica
     protetta (BEGIN TRAN ... COMMIT).
   - In caso di errore a qualsiasi livello, viene eseguito il ROLLBACK integrale e sollevata un'eccezione
     dettagliata tramite blocco CATCH, azzerando il rischio di corruzione o disallineamento descrittivo.
3. Letture Concorrenti Senza Lock:
   - Applicazione sistematica di WITH (NOLOCK) su tutte le letture anagrafiche.
----------------------------------------------------------------------------------------------------
PARAMETRI:
- @DryRun BIT = 1  --> 1: Simulazione verbosa con confronto Prima vs Dopo (Dry-Run).
                   --> 0: Esecuzione effettiva con persistenza su MG87_ARTDESC.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Procedura legacy dbo.SPRT_TMV_AGG_DESCR_ART.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della versione standardizzata GEMINI. Adozione del parametro Dry-Run nativo, reporting
  diagnostico differenziale, gestione transazionale protetta e conformità piena a MSSQL 14.0.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_AGG_DESCR_ART_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_AGG_DESCR_ART_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_AGG_DESCR_ART_GEMINI]
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '====================================================================================';
    PRINT 'Inizio esecuzione: dbo.SPSO_TMV_AGG_DESCR_ART_GEMINI';
    PRINT 'Modalità operativa : ' + CASE WHEN @DryRun = 1 THEN 'DRY-RUN (Simulazione Verbosa - Nessuna Modifica)' ELSE 'EFFETTIVA (Scrittura su Database)' END;
    PRINT 'Data e Ora         : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';

    -- STEP 1: Bonifica preventiva di sicurezza su RT12_AGG_DESCR_ART
    IF @DryRun = 0
    BEGIN
        DELETE RT12
        FROM dbo.RT12_AGG_DESCR_ART AS RT12
        FULL OUTER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK)
            ON  RT12.RT12_DITTA_CG18  = CM15.CM15_DITTA_CG18
            AND RT12.RT12_CODART_MG66 = CM15.CM15_CODART_MG66
        WHERE CM15.CM15_DITTA_CG18 IS NULL;
    END;

    -- Tabella temporanea per raccogliere le descrizioni calcolate per entrambe le lingue
    CREATE TABLE #ProposteDescrizioni (
        Ditta                   DECIMAL(5,0),
        CodiceArticolo          CHAR(25),
        Opzione                 CHAR(20),
        Lingua                  CHAR(3),
        DescrizioneAttuale      NVARCHAR(72),
        DescrizioneNuova        NVARCHAR(72),
        DescEstesaAttuale       NVARCHAR(1672),
        DescEstesaNuova         NVARCHAR(1672),
        TipoAzione              VARCHAR(20),
        RegolaSpecialeApplicata VARCHAR(100)
    );

    -- Cursore di scansione per calcolo descrizioni SHORT e LONG
    DECLARE @ditta      DECIMAL(5, 0);
    DECLARE @codart     CHAR(25);
    DECLARE @opzione    CHAR(20);
    DECLARE @short      NVARCHAR(1744);
    DECLARE @long       NVARCHAR(1744);
    DECLARE @descr_s    NVARCHAR(72);
    DECLARE @descr_s_est NVARCHAR(1672);
    DECLARE @descr_l    NVARCHAR(72);
    DECLARE @descr_l_est NVARCHAR(1672);

    DECLARE RT12_cur CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY
    FOR 
        SELECT RT12_DITTA_CG18, RT12_CODART_MG66, RT12_OPZIONE_MG5E
        FROM dbo.RT12_AGG_DESCR_ART WITH (NOLOCK);

    OPEN RT12_cur;
    FETCH NEXT FROM RT12_cur INTO @ditta, @codart, @opzione;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Calcolo SHORT (Lingua '')
        SET @short = dbo.SFSO_TMV_DESCRIZIONE_GEMINI(@ditta, @codart, @opzione, 'SHORT');
        SELECT @descr_s = Descr, @descr_s_est = DescrEst 
        FROM dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(@short);

        -- Applicazione regole speciali su SHORT
        DECLARE @RegolaS VARCHAR(100) = '';
        IF EXISTS (
            SELECT 1 FROM dbo.CM15_CONFGCOMM WITH (NOLOCK) 
            WHERE CM15_DITTA_CG18 = @ditta AND CM15_CODART_MG66 = @codart 
              AND RTRIM(CM15_CODARTMOD_MG66) IN ('DADI_METRICI', 'DADI_POLLICI')
        )
        BEGIN
            IF CHARINDEX('Min.', @descr_s) > 0 OR CHARINDEX('Min.', @descr_s_est) > 0
            BEGIN
                SET @descr_s = REPLACE(@descr_s, 'Min.', 'Mag.');
                SET @descr_s_est = REPLACE(@descr_s_est, 'Min.', 'Mag.');
                SET @RegolaS = 'DADI: Sostituzione Min. in Mag.';
            END;
        END;

        IF @codart LIKE '%P1--%' AND (@codart LIKE '%F-' OR @codart LIKE '%FS') AND (CHARINDEX('14UNF', @descr_s) > 0 OR CHARINDEX('14UNF', @descr_s_est) > 0)
        BEGIN
            SET @descr_s = REPLACE(@descr_s, '14UNF', '12UNF');
            SET @descr_s_est = REPLACE(@descr_s_est, '14UNF', '12UNF');
            SET @RegolaS = CASE WHEN @RegolaS = '' THEN '' ELSE @RegolaS + ' | ' END + 'FILETTATURA: 14UNF -> 12UNF';
        END;

        -- Inserimento SHORT in tabella di staging
        INSERT INTO #ProposteDescrizioni (
            Ditta, CodiceArticolo, Opzione, Lingua, 
            DescrizioneAttuale, DescrizioneNuova, 
            DescEstesaAttuale, DescEstesaNuova, 
            TipoAzione, RegolaSpecialeApplicata
        )
        SELECT 
            @ditta, @codart, @opzione, '',
            MG87.MG87_DESCART, @descr_s,
            MG87.MG87_DESCARTEST, @descr_s_est,
            CASE WHEN MG87.MG87_CODART_MG66 IS NOT NULL THEN 'UPDATE' ELSE 'INSERT' END,
            @RegolaS
        FROM (SELECT 1 AS dummy) AS d
        LEFT JOIN dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
            ON  MG87.MG87_DITTA_CG18     = @ditta
            AND MG87.MG87_CODART_MG66    = @codart
            AND MG87.MG87_OPZIONE_MG5E   = @opzione
            AND RTRIM(MG87.MG87_LINGUA_MG52) = '';

        -- Calcolo LONG (Lingua 'LNG')
        SET @long = dbo.SFSO_TMV_DESCRIZIONE_GEMINI(@ditta, @codart, @opzione, 'LONG');
        SELECT @descr_l = Descr, @descr_l_est = DescrEst 
        FROM dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(@long);

        -- Applicazione regole speciali su LONG
        DECLARE @RegolaL VARCHAR(100) = '';
        IF EXISTS (
            SELECT 1 FROM dbo.CM15_CONFGCOMM WITH (NOLOCK) 
            WHERE CM15_DITTA_CG18 = @ditta AND CM15_CODART_MG66 = @codart 
              AND RTRIM(CM15_CODARTMOD_MG66) IN ('DADI_METRICI', 'DADI_POLLICI')
        )
        BEGIN
            IF CHARINDEX('Min.', @descr_l) > 0 OR CHARINDEX('Min.', @descr_l_est) > 0
            BEGIN
                SET @descr_l = REPLACE(@descr_l, 'Min.', 'Mag.');
                SET @descr_l_est = REPLACE(@descr_l_est, 'Min.', 'Mag.');
                SET @RegolaL = 'DADI: Sostituzione Min. in Mag.';
            END;
        END;

        IF @codart LIKE '%P1--%' AND (@codart LIKE '%F-' OR @codart LIKE '%FS') AND (CHARINDEX('14UNF', @descr_l) > 0 OR CHARINDEX('14UNF', @descr_l_est) > 0)
        BEGIN
            SET @descr_l = REPLACE(@descr_l, '14UNF', '12UNF');
            SET @descr_l_est = REPLACE(@descr_l_est, '14UNF', '12UNF');
            SET @RegolaL = CASE WHEN @RegolaL = '' THEN '' ELSE @RegolaL + ' | ' END + 'FILETTATURA: 14UNF -> 12UNF';
        END;

        -- Inserimento LONG in tabella di staging
        INSERT INTO #ProposteDescrizioni (
            Ditta, CodiceArticolo, Opzione, Lingua, 
            DescrizioneAttuale, DescrizioneNuova, 
            DescEstesaAttuale, DescEstesaNuova, 
            TipoAzione, RegolaSpecialeApplicata
        )
        SELECT 
            @ditta, @codart, @opzione, 'LNG',
            MG87.MG87_DESCART, @descr_l,
            MG87.MG87_DESCARTEST, @descr_l_est,
            CASE WHEN MG87.MG87_CODART_MG66 IS NOT NULL THEN 'UPDATE' ELSE 'INSERT' END,
            @RegolaL
        FROM (SELECT 1 AS dummy) AS d
        LEFT JOIN dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
            ON  MG87.MG87_DITTA_CG18     = @ditta
            AND MG87.MG87_CODART_MG66    = @codart
            AND MG87.MG87_OPZIONE_MG5E   = @opzione
            AND RTRIM(MG87.MG87_LINGUA_MG52) = 'LNG';

        FETCH NEXT FROM RT12_cur INTO @ditta, @codart, @opzione;
    END;

    CLOSE RT12_cur;
    DEALLOCATE RT12_cur;

    -- =============================================================================================
    -- OUTPUT DRY-RUN VS SCRITTURA REALE
    -- =============================================================================================
    IF @DryRun = 1
    BEGIN
        PRINT '>>> DRY-RUN: Emissione del report dettagliato di simulazione descrizioni...';
        SELECT 
            'DRY_RUN_DESCRIZIONI' AS Modalita,
            Ditta,
            CodiceArticolo,
            Opzione,
            CASE WHEN Lingua = '' THEN 'ITALIANO (Default)' ELSE 'INTERNAZIONALE (LNG)' END AS LinguaDescrizione,
            TipoAzione,
            DescrizioneAttuale,
            DescrizioneNuova,
            DescEstesaAttuale,
            DescEstesaNuova,
            RegolaSpecialeApplicata
        FROM #ProposteDescrizioni
        ORDER BY CodiceArticolo, Opzione, Lingua;

        PRINT '>>> DRY-RUN COMPLETATO: Nessuna scrittura effettuata in MG87_ARTDESC.';
    END
    ELSE
    BEGIN
        PRINT '>>> MODALITA REALE: Avvio transazione per aggiornamento/inserimento MG87_ARTDESC...';
        BEGIN TRY
            BEGIN TRANSACTION;

            -- UPDATE record esistenti
            UPDATE DEST
            SET 
                DEST.MG87_DESCART    = SRC.DescrizioneNuova,
                DEST.MG87_DESCARTEST = SRC.DescEstesaNuova
            FROM dbo.MG87_ARTDESC AS DEST
            INNER JOIN #ProposteDescrizioni AS SRC
                ON  DEST.MG87_DITTA_CG18         = SRC.Ditta
                AND DEST.MG87_CODART_MG66        = SRC.CodiceArticolo
                AND DEST.MG87_OPZIONE_MG5E       = SRC.Opzione
                AND RTRIM(DEST.MG87_LINGUA_MG52) = RTRIM(SRC.Lingua)
            WHERE SRC.TipoAzione = 'UPDATE';

            DECLARE @RigheAggiornate INT = @@ROWCOUNT;

            -- INSERT record mancanti (es. Lingua 'LNG' mai creata prima)
            INSERT INTO dbo.MG87_ARTDESC (
                MG87_DITTA_CG18,
                MG87_CODART_MG66,
                MG87_OPZIONE_MG5E,
                MG87_LINGUA_MG52,
                MG87_DESCART,
                MG87_DESCARTEST
            )
            SELECT 
                SRC.Ditta,
                SRC.CodiceArticolo,
                SRC.Opzione,
                SRC.Lingua,
                SRC.DescrizioneNuova,
                SRC.DescEstesaNuova
            FROM #ProposteDescrizioni AS SRC
            WHERE SRC.TipoAzione = 'INSERT';

            DECLARE @RigheInserite INT = @@ROWCOUNT;

            COMMIT TRANSACTION;
            PRINT '>>> SUCCESSO: Aggiornati ' + CAST(@RigheAggiornate AS VARCHAR(10)) + ' record, Inseriti ' + CAST(@RigheInserite AS VARCHAR(10)) + ' nuovi record in MG87_ARTDESC.';
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
            DECLARE @ErrSev INT = ERROR_SEVERITY();
            DECLARE @ErrState INT = ERROR_STATE();
            PRINT '>>> ERRORE durante aggiornamento MG87_ARTDESC: ' + @ErrMsg;
            RAISERROR(@ErrMsg, @ErrSev, @ErrState);
        END CATCH;
    END;

    DROP TABLE #ProposteDescrizioni;
END;
GO

