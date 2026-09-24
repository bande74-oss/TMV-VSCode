/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 09:40
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI
Nome File                        : SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI' costituisce il motore esecutivo di bonifica
e riallineamento massivo delle descrizioni per gli articoli della famiglia barre, tondi e tiranti (prefisso 'TD%').
Essa opera basandosi sui dati censiti nella tabella di audit 'dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI'
preventivamente popolata dalla procedura di diagnosi 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI'.

SICUREZZA OPERATIVA E MODALITÀ DRY-RUN:
Per impostazione predefinita, il parametro @DryRun è valorizzato a 1:
- In modalità DRY-RUN (@DryRun = 1), la procedura opera in sola simulazione. Non esegue alcuna modifica,
  cancellazione o inserimento nell'anagrafica reale di Gamma Enterprise ('dbo.MG87_ARTDESC'), ma emette
  un report esaustivo e verboso a video indicando esattamente quanti e quali articoli verrebbero aggiornati.
- In modalità EFFETTIVA (@DryRun = 0), la procedura richiede la specifica esplicita del parametro ed
  esegue le modifiche all'interno di una transazione atomica (BEGIN TRAN ... COMMIT) protetta da
  blocco TRY...CATCH.

AZIONI APPLICATE:
1. UPDATE su MG87_ARTDESC per lingua predefinita (Italiano '') con il valore 'ShortNuovo' e 'ShortEstesaNuova'.
2. UPDATE su MG87_ARTDESC per lingua estera ('LNG') con il valore 'LongNuovo' e 'LongEstesaNuova'.
3. INSERT su MG87_ARTDESC per lingua estera ('LNG') per tutti gli articoli che ne risultavano totalmente sprovvisti.
4. Tracciamento dell'avvenuto adeguamento aggiornando il campo 'DataAdeguamento' in 'SO_DIFF_DESCRIZIONI_TD_GEMINI'.
5. Opzionalmente (parametro @AlimentaRT12 = 1), popolamento della tabella di frontiera 'dbo.RT12_AGG_DESCR_ART'
   qualora si intenda sincronizzare l'operazione con il normale flusso ImpExp di Gamma Enterprise.

PARAMETRI DI INPUT:
- @Ditta         : DECIMAL(5,0) = 1 (Identificativo ditta).
- @DryRun        : BIT = 1 (1 = Simulazione Verbosa Protetta, 0 = Scrittura Reale su Database).
- @TipologiaTD   : CHAR(3) = NULL (Filtro opzionale: TDP, TDL, TDN, TDM, TDR, TDC, TDF. Se NULL, elabora tutti).
- @AlimentaRT12  : BIT = 0 (Se 1, inserisce le chiavi bonificate in RT12_AGG_DESCR_ART).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio iniziale della procedura di adeguamento massivo e bonifica descrizioni articoli TD.
- Rev. 1.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Esclusione tassativa degli articoli modello censiti in 'dbo.VPRT_ARTICOLI_MODELLO' (CM15_CONFGCOMM)
  per impedire qualsiasi riscrittura o alterazione delle descrizioni anagrafiche dei modelli.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI]
    @Ditta          DECIMAL(5,0)    = 1,
    @DryRun         BIT             = 1,
    @TipologiaTD    CHAR(3)         = NULL,
    @AlimentaRT12   BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    PRINT '====================================================================================';
    PRINT 'AVVIO PROCEDURA ADEGUAMENTO: dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI';
    PRINT 'Modalità Operativa : ' + CASE WHEN @DryRun = 1 THEN 'DRY-RUN (Simulazione Verbosa - Nessuna Scrittura)' ELSE 'EFFETTIVA (Scrittura su MG87_ARTDESC)' END;
    PRINT 'Filtro Tipologia   : ' + ISNULL(@TipologiaTD, 'TUTTE LE TIPOLOGIE TD');
    PRINT 'Alimenta RT12      : ' + CASE WHEN @AlimentaRT12 = 1 THEN 'SI' ELSE 'NO' END;
    PRINT 'Data e Ora Inizio  : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';

    -- Conteggio record eleggibili da tabella audit
    DECLARE @TotShortDaAggiornare INT = 0;
    DECLARE @TotLongDaAggiornare  INT = 0;
    DECLARE @TotLongDaInserire     INT = 0;

    SELECT 
        @TotShortDaAggiornare = SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END),
        @TotLongDaAggiornare  = SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END),
        @TotLongDaInserire     = SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END)
    FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI WITH (NOLOCK)
    WHERE Ditta = @Ditta
      AND (@TipologiaTD IS NULL OR TipologiaTD = @TipologiaTD)
      AND DataAdeguamento IS NULL;

    PRINT 'Record individuati da elaborare:';
    PRINT ' - Aggiornamenti SHORT (Italiano) : ' + CAST(ISNULL(@TotShortDaAggiornare, 0) AS VARCHAR(10));
    PRINT ' - Aggiornamenti LONG (Estero)    : ' + CAST(ISNULL(@TotLongDaAggiornare, 0) AS VARCHAR(10));
    PRINT ' - Inserimenti LONG (Estero manc.): ' + CAST(ISNULL(@TotLongDaInserire, 0) AS VARCHAR(10));
    PRINT '------------------------------------------------------------------------------------';

    -- SE MODALITÀ DRY-RUN
    IF @DryRun = 1
    BEGIN
        PRINT '>>> MODALITÀ DRY-RUN ATTIVA: Nessuna modifica verrà applicata a MG87_ARTDESC.';
        PRINT '';
        PRINT '--- CAMPIONE DI 15 PROPOSTE DI ADEGUAMENTO IN DRY-RUN ---';

        SELECT TOP 15
            CodiceArticolo,
            Opzione,
            TipologiaTD,
            MotivoDifferenza,
            TipoAzioneShort,
            ShortAttuale,
            ShortNuovo,
            TipoAzioneLong,
            LongAttuale,
            LongNuovo
        FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI WITH (NOLOCK)
        WHERE Ditta = @Ditta
          AND (@TipologiaTD IS NULL OR TipologiaTD = @TipologiaTD)
          AND DataAdeguamento IS NULL
        ORDER BY DiffShort DESC, DiffLong DESC;

        PRINT '';
        PRINT '>>> DRY-RUN COMPLETATO: Per confermare e scrivere le modifiche nel database,';
        PRINT '>>> rieseguire la procedura specificando esplicitamente: @DryRun = 0';
        RETURN;
    END;

    -- =============================================================================================
    -- SE MODALITÀ EFFETTIVA (@DryRun = 0): APPLICAZIONE TRANSAZIONALE PROTETTA
    -- =============================================================================================
    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. AGGIORNAMENTO SHORT IN MG87_ARTDESC
        UPDATE tgt
        SET tgt.MG87_DESCART     = src.ShortNuovo,
            tgt.MG87_DESCARTEST  = src.ShortEstesaNuova,
            tgt.MG87_LASTCHANGE  = GETDATE()
        FROM dbo.MG87_ARTDESC AS tgt
        INNER JOIN dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS src
            ON  tgt.MG87_DITTA_CG18     = src.Ditta
            AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
            AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
            AND RTRIM(tgt.MG87_LINGUA_MG52) = ''
        WHERE src.Ditta = @Ditta
          AND src.DiffShort = 1
          AND (@TipologiaTD IS NULL OR src.TipologiaTD = @TipologiaTD)
          AND src.DataAdeguamento IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = src.Ditta
                AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
          );

        DECLARE @RowShortUpd INT = @@ROWCOUNT;
        PRINT '1. Aggiornati con successo ' + CAST(@RowShortUpd AS VARCHAR(10)) + ' record SHORT in MG87_ARTDESC.';

        -- 2. AGGIORNAMENTO LONG ESISTENTI IN MG87_ARTDESC
        UPDATE tgt
        SET tgt.MG87_DESCART     = src.LongNuovo,
            tgt.MG87_DESCARTEST  = src.LongEstesaNuova,
            tgt.MG87_LASTCHANGE  = GETDATE()
        FROM dbo.MG87_ARTDESC AS tgt
        INNER JOIN dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS src
            ON  tgt.MG87_DITTA_CG18     = src.Ditta
            AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
            AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
            AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
        WHERE src.Ditta = @Ditta
          AND src.DiffLong = 1
          AND src.TipoAzioneLong = 'UPDATE'
          AND (@TipologiaTD IS NULL OR src.TipologiaTD = @TipologiaTD)
          AND src.DataAdeguamento IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = src.Ditta
                AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
          );

        DECLARE @RowLongUpd INT = @@ROWCOUNT;
        PRINT '2. Aggiornati con successo ' + CAST(@RowLongUpd AS VARCHAR(10)) + ' record LONG in MG87_ARTDESC.';

        -- 3. INSERIMENTO LONG MANCANTI IN MG87_ARTDESC
        INSERT INTO dbo.MG87_ARTDESC (
            MG87_DITTA_CG18,
            MG87_CODART_MG66,
            MG87_OPZIONE_MG5E,
            MG87_LINGUA_MG52,
            MG87_DESCART,
            MG87_DESCARTEST,
            MG87_LASTCHANGE,
            MG87_GUID
        )
        SELECT 
            src.Ditta,
            src.CodiceArticolo,
            src.Opzione,
            'LNG',
            src.LongNuovo,
            src.LongEstesaNuova,
            GETDATE(),
            NEWID()
        FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS src
        WHERE src.Ditta = @Ditta
          AND src.TipoAzioneLong = 'INSERT'
          AND (@TipologiaTD IS NULL OR src.TipologiaTD = @TipologiaTD)
          AND src.DataAdeguamento IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = src.Ditta
                AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
          )
          AND NOT EXISTS (
              SELECT 1 
              FROM dbo.MG87_ARTDESC AS tgt WITH (NOLOCK)
              WHERE tgt.MG87_DITTA_CG18     = src.Ditta
                AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
                AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
                AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
          );

        DECLARE @RowLongIns INT = @@ROWCOUNT;
        PRINT '3. Inseriti con successo ' + CAST(@RowLongIns AS VARCHAR(10)) + ' nuovi record LONG in MG87_ARTDESC.';

        -- 4. AGGIORNAMENTO FLAG DI ADEGUAMENTO IN SO_DIFF_DESCRIZIONI_TD_GEMINI
        UPDATE src
        SET src.DataAdeguamento = GETDATE()
        FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS src
        WHERE src.Ditta = @Ditta
          AND (@TipologiaTD IS NULL OR src.TipologiaTD = @TipologiaTD)
          AND src.DataAdeguamento IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = src.Ditta
                AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
          );

        -- 5. POPOLAMENTO FACOLTATIVO DI RT12_AGG_DESCR_ART
        IF @AlimentaRT12 = 1
        BEGIN
            INSERT INTO dbo.RT12_AGG_DESCR_ART (RT12_DITTA_CG18, RT12_CODART_MG66, RT12_OPZIONE_MG5E)
            SELECT DISTINCT src.Ditta, src.CodiceArticolo, src.Opzione
            FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS src
            WHERE src.Ditta = @Ditta
              AND (@TipologiaTD IS NULL OR src.TipologiaTD = @TipologiaTD)
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
                  WHERE mod.CM15_DITTA_CG18 = src.Ditta
                    AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
              )
              AND NOT EXISTS (
                  SELECT 1 
                  FROM dbo.RT12_AGG_DESCR_ART AS r WITH (NOLOCK)
                  WHERE r.RT12_DITTA_CG18     = src.Ditta
                    AND r.RT12_CODART_MG66    = src.CodiceArticolo
                    AND r.RT12_OPZIONE_MG5E   = src.Opzione
              );

            DECLARE @RowRT12 INT = @@ROWCOUNT;
            PRINT '4. Inserite ' + CAST(@RowRT12 AS VARCHAR(10)) + ' chiavi articolo in RT12_AGG_DESCR_ART.';
        END;

        COMMIT TRANSACTION;
        PRINT '====================================================================================';
        PRINT 'TRANSAZIONE COMPLETATA CON SUCCESSO (COMMIT). Tutte le descrizioni sono state allineate.';
        PRINT '====================================================================================';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT 'ERRORE DURANTE L''ADEGUAMENTO DELLE DESCRIZIONI:';
        PRINT 'Messaggio : ' + ERROR_MESSAGE();
        PRINT 'Riga      : ' + CAST(ERROR_LINE() AS VARCHAR(10));
        PRINT 'Numero    : ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        THROW;
    END CATCH;
END;
GO

