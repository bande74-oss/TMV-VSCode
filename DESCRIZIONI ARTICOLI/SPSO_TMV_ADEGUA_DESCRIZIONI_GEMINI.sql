/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 11:45
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI
Nome File                        : SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI' è il motore esecutivo di bonifica universale
per l'intera base dati Gamma Enterprise di TMV. Essa attinge ai dati di audit archiviati nella tabella
'dbo.SO_DIFF_DESCRIZIONI_GEMINI' per applicare le descrizioni corrette in 'dbo.MG87_ARTDESC'.

SICUREZZA OPERATIVA E TRANSAZIONI A CHUNK (Protezione Transaction Log):
1. Parametro @DryRun = 1 di default:
   - In modalità DryRun, la procedura non scrive nulla su MG87_ARTDESC, ma calcola e visualizza i volumi
     esatti di modifiche previste e produce un campionamento verboso a video.
   - AUTO-POPOLAMENTO IN DRY-RUN: Se la tabella 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' è vuota (es. a valle di un
     rollback o prima analisi) oppure se viene esplicitamente richiesto tramite @RicalcolaAudit = 1, la
     procedura lancia automaticamente in apertura 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI' popolando
     la tabella di staging esattamente con le descrizioni calcolate che la modalità effettiva andrà ad applicare.
2. In modalità EFFETTIVA (@DryRun = 0):
   - Per gestire in sicurezza aggiornamenti di decine di migliaia di articoli senza bloccare le tabelle
     o esaurire lo spazio del transaction log di SQL Server, la procedura esegue le scritture a blocchi
     controllati (parametro @BatchSize, default 5.000 record per transazione atomica).
   - Ogni batch è racchiuso in un blocco TRY...CATCH con COMMIT immediato e avanzamento progressivo.
3. Flessibilità di Bonifica Mirata:
   - Parametro @Prefisso: consente di bonificare famiglia per famiglia a 3 caratteri (es. 'TDP', 'TDN', 'VTF', 'T--')
     oppure l'intero archivio impostando NULL.
   - Parametro @MotivoDifferenza: consente di bonificare prioritariamente una determinata classe di anomalie
     (es. 'DIAMETRO_RT05_BONIFICATO' o 'BONIFICA_REFUSO_UNS').

PROTEZIONE ARTICOLI MODELLO E ARTICOLI NON CONFIGURATI:
La procedura include un duplice presidio di sicurezza invalicabile:
1. INNER JOIN tassativo con 'dbo.CM15_CONFGCOMM': garantisce che solo gli articoli derivati da configuratore
   di modello vengano elaborati. Gli articoli manuali/a disegno non configurati (es. '01950265') non possono mai
   essere alterati.
2. NOT EXISTS con 'dbo.VPRT_ARTICOLI_MODELLO': esclude tassativamente gli articoli modello matrice, preservando
   intatta la descrizione anagrafica generale.

PARAMETRI DI INPUT:
- @Ditta              : DECIMAL(5,0) = 1 (Identificativo ditta Gamma).
- @DryRun             : BIT = 1 (1 = Simulazione Verbosa Protetta, 0 = Scrittura Reale su Database).
- @Prefisso           : VARCHAR(10) = NULL (Filtro opzionale famiglia/prefisso a 3 car. NULL = Tutte le famiglie).
- @MotivoDifferenza   : VARCHAR(50) = NULL (Filtro opzionale motivo anomalia. NULL = Tutti i motivi).
- @AlimentaRT12       : BIT = 0 (Se 1, inserisce le chiavi bonificate nella tabella di frontiera RT12).
- @BatchSize          : INT = 5000 (Dimensione del singolo blocco transazionale).
- @RicalcolaAudit     : BIT = 0 (Se 1, riesegue preventivamente il controllo diagnostico globale).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della procedura universale di bonifica massiva a batch per l'intero database.
- Rev. 1.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Ottimizzazione architettura a batch: introduzione tabella temporanea #BatchKeys per garantire che ogni ciclo
  transazionale elabori e marchi atomicamente l'esatto medesimo insieme di chiavi (Ditta, CodiceArticolo, Opzione),
  azzerando ogni rischio di disallineamento tra Short, Long ed esito DataAdeguamento.
- Rev. 1.2 (24/09/2026 - SOLVERIS - Bandera Marco):
  Protezione tassativa degli articoli modello censiti in 'dbo.VPRT_ARTICOLI_MODELLO' (CM15_CONFGCOMM):
  esclusione esplicita da conteggi e scritture (#BatchKeys ed RT12) per preservare le descrizioni anagrafiche originali.
- Rev. 1.3 (24/09/2026 - SOLVERIS - Bandera Marco):
  Integrazione presidio di sicurezza strutturale con INNER JOIN su 'dbo.CM15_CONFGCOMM' nell'estrazione dei
  batch transazionali (#BatchKeys) e nell'alimentazione RT12, garantendo l'impossibilità assoluta di alterare
  articoli non derivanti da modello configuratore (es. articoli a disegno cliente o manuali come '01950265').
- Rev. 2.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Adozione dello standard di prefisso/famiglia a 3 caratteri (LEFT(CodiceArticolo, 3)) in linea con
  'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI' Rev. 2.0.
  Integrazione dell'auto-popolamento trasparente della tabella audit 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' in modalità
  Dry-Run (@DryRun = 1) o su richiesta (@RicalcolaAudit = 1): se la tabella è vuota, lancia preventivamente la SP
  diagnostica così che la simulazione prepari ed esponga esattamente i record e le descrizioni che la modalità
  effettiva (@DryRun = 0) andrà ad applicare.
- Rev. 2.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Allineamento con la Rev. 3.0 del modulo diagnostico: le descrizioni applicate ereditano la formattazione
  della nuova funzione 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI', con salvaguardia dell'integrità delle misure
  ('mm' mai separato dalla quota), assenza di spazi di coda e garanzia di terminatore CR+LF su ogni campo valorizzato.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI]
    @Ditta              DECIMAL(5,0)    = 1,
    @DryRun             BIT             = 1,
    @Prefisso           VARCHAR(10)     = NULL,
    @MotivoDifferenza   VARCHAR(50)     = NULL,
    @AlimentaRT12       BIT             = 0,
    @BatchSize          INT             = 5000,
    @RicalcolaAudit     BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '====================================================================================';
    PRINT 'AVVIO PROCEDURA BONIFICA UNIVERSALE: dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI (Rev. 2.0)';
    PRINT 'Modalità Operativa : ' + CASE WHEN @DryRun = 1 THEN 'DRY-RUN (Simulazione Verbosa - Nessuna Scrittura)' ELSE 'EFFETTIVA (Scrittura Massiva su MG87_ARTDESC)' END;
    PRINT 'Filtro Prefisso    : ' + ISNULL(@Prefisso, 'TUTTE LE FAMIGLIE (Standard 3 caratteri)');
    PRINT 'Filtro Motivo      : ' + ISNULL(@MotivoDifferenza, 'TUTTE LE TIPOLOGIE DI ANOMALIA');
    PRINT 'Batch Size         : ' + CAST(@BatchSize AS VARCHAR(10)) + ' record per transazione';
    PRINT 'Alimenta RT12      : ' + CASE WHEN @AlimentaRT12 = 1 THEN 'SI' ELSE 'NO' END;
    PRINT 'Ricalcola Audit    : ' + CASE WHEN @RicalcolaAudit = 1 THEN 'SI' ELSE 'NO (Auto-popola se tabella vuota)' END;
    PRINT 'Data e Ora Inizio  : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';

    -- =============================================================================================
    -- AUTO-POPOLAMENTO / RICALCOLO AUDIT PREVENTIVO IN SO_DIFF_DESCRIZIONI_GEMINI
    -- =============================================================================================
    -- Se richiesto esplicitamente (@RicalcolaAudit = 1) OPPURE se in DryRun la tabella audit
    -- non contiene record pendenti per l'ambito specificato, viene invocata la SP diagnostica.
    IF @RicalcolaAudit = 1 OR (@DryRun = 1 AND NOT EXISTS (
        SELECT 1 FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
        WHERE Ditta = @Ditta
          AND (@Prefisso IS NULL OR Prefisso = @Prefisso)
          AND (@MotivoDifferenza IS NULL OR MotivoDifferenza = @MotivoDifferenza)
          AND DataAdeguamento IS NULL
    ))
    BEGIN
        PRINT '>>> Tabella audit vuota o ricalcolo richiesto: avvio calcolo diagnostico preventivo...';
        PRINT '>>> Chiamata a dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI...';
        
        DECLARE @FiltroCheck VARCHAR(25) = CASE WHEN @Prefisso IS NOT NULL THEN @Prefisso + '%' ELSE NULL END;
        
        EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
            @Ditta              = @Ditta,
            @FiltroFamiglia     = @FiltroCheck,
            @PulisciTabella     = 1,
            @SoloConDifferenze  = 1;

        PRINT '>>> Popolamento diagnostico completato. Calcolo delle descrizioni memorizzato in SO_DIFF_DESCRIZIONI_GEMINI.';
        PRINT '------------------------------------------------------------------------------------';
    END;

    -- Conteggi generali da tabella audit (filtrati con i presidi di sicurezza)
    DECLARE @TotShort INT = 0;
    DECLARE @TotLongUpd INT = 0;
    DECLARE @TotLongIns INT = 0;

    SELECT 
        @TotShort   = SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END),
        @TotLongUpd = SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END),
        @TotLongIns = SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END)
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src WITH (NOLOCK)
    INNER JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
        ON  src.Ditta          = c.CM15_DITTA_CG18
        AND src.CodiceArticolo = c.CM15_CODART_MG66
    WHERE src.Ditta = @Ditta
      AND (@Prefisso IS NULL OR src.Prefisso = @Prefisso)
      AND (@MotivoDifferenza IS NULL OR src.MotivoDifferenza = @MotivoDifferenza)
      AND src.DataAdeguamento IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
          WHERE mod.CM15_DITTA_CG18 = src.Ditta
            AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
      );

    PRINT 'Record pendenti individuati per l''ambito selezionato:';
    PRINT ' - Aggiornamenti SHORT (Italiano) : ' + CAST(ISNULL(@TotShort, 0) AS VARCHAR(10));
    PRINT ' - Aggiornamenti LONG (Estero)    : ' + CAST(ISNULL(@TotLongUpd, 0) AS VARCHAR(10));
    PRINT ' - Inserimenti LONG (Estero manc.): ' + CAST(ISNULL(@TotLongIns, 0) AS VARCHAR(10));
    PRINT '------------------------------------------------------------------------------------';

    IF ISNULL(@TotShort, 0) = 0 AND ISNULL(@TotLongUpd, 0) = 0 AND ISNULL(@TotLongIns, 0) = 0
    BEGIN
        PRINT 'Nessun record pendente da adeguare per i filtri selezionati.';
        RETURN;
    END;

    -- =============================================================================================
    -- SE MODALITÀ DRY-RUN: REPORT DETTAGLIATO A VIDEO
    -- =============================================================================================
    IF @DryRun = 1
    BEGIN
        PRINT '>>> MODALITÀ DRY-RUN ATTIVA: Nessuna modifica verrà applicata a MG87_ARTDESC.';
        PRINT '';
        PRINT '--- CAMPIONAMENTO 20 PROPOSTE DI BONIFICA ---';

        SELECT TOP 20
            CodiceArticolo,
            Opzione,
            Prefisso,
            MotivoDifferenza,
            TipoAzioneShort,
            ShortAttuale,
            ShortNuovo,
            TipoAzioneLong,
            LongAttuale,
            LongNuovo
        FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
        WHERE Ditta = @Ditta
          AND (@Prefisso IS NULL OR Prefisso = @Prefisso)
          AND (@MotivoDifferenza IS NULL OR MotivoDifferenza = @MotivoDifferenza)
          AND DataAdeguamento IS NULL
        ORDER BY DiffShort DESC, DiffLong DESC;

        PRINT '';
        PRINT '>>> DRY-RUN COMPLETATO CON SUCCESSO.';
        PRINT '>>> La tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI è ora interamente popolata con i dati e le descrizioni calcolate.';
        PRINT '>>> I record memorizzati sono esattamente quelli che verranno elaborati dalla modalità effettiva (@DryRun = 0).';
        PRINT '>>> È possibile consultare la vista dbo.VPSO_DIFF_DESCRIZIONI_GEMINI per il riepilogo aggregato per prefisso.';
        PRINT '>>> Per applicare le modifiche su MG87_ARTDESC, rilanciare specificando: @DryRun = 0';
        RETURN;
    END;

    -- =============================================================================================
    -- SE MODALITÀ EFFETTIVA (@DryRun = 0): ESECUZIONE TRANSAZIONALE A BATCH
    -- =============================================================================================
    CREATE TABLE #BatchKeys (
        Ditta           DECIMAL(5,0) NOT NULL,
        CodiceArticolo  CHAR(25)     COLLATE DATABASE_DEFAULT NOT NULL,
        Opzione         CHAR(20)     COLLATE DATABASE_DEFAULT NOT NULL,
        PRIMARY KEY (Ditta, CodiceArticolo, Opzione)
    );

    DECLARE @Ciclo INT = 1;
    DECLARE @TotArticoliBonificati INT = 0;
    DECLARE @TotOperazioniMG87 INT = 0;

    WHILE 1 = 1
    BEGIN
        BEGIN TRY
            TRUNCATE TABLE #BatchKeys;

            INSERT INTO #BatchKeys (Ditta, CodiceArticolo, Opzione)
            SELECT TOP (@BatchSize) src.Ditta, src.CodiceArticolo, src.Opzione
            FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src WITH (NOLOCK)
            INNER JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
                ON  src.Ditta          = c.CM15_DITTA_CG18
                AND src.CodiceArticolo = c.CM15_CODART_MG66
            WHERE src.Ditta = @Ditta
              AND (@Prefisso IS NULL OR src.Prefisso = @Prefisso)
              AND (@MotivoDifferenza IS NULL OR src.MotivoDifferenza = @MotivoDifferenza)
              AND src.DataAdeguamento IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
                  WHERE mod.CM15_DITTA_CG18 = src.Ditta
                    AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
              );

            IF @@ROWCOUNT = 0
                BREAK;

            BEGIN TRANSACTION;

            -- 1. UPDATE SHORT a blocchi per le chiavi del batch
            UPDATE tgt
            SET tgt.MG87_DESCART     = src.ShortNuovo,
                tgt.MG87_DESCARTEST  = src.ShortEstesaNuova,
                tgt.MG87_LASTCHANGE  = GETDATE()
            FROM dbo.MG87_ARTDESC AS tgt
            INNER JOIN dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src
                ON  tgt.MG87_DITTA_CG18     = src.Ditta
                AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
                AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
                AND RTRIM(tgt.MG87_LINGUA_MG52) = ''
            INNER JOIN #BatchKeys AS b
                ON  src.Ditta          = b.Ditta
                AND src.CodiceArticolo = b.CodiceArticolo
                AND src.Opzione        = b.Opzione
            WHERE src.DiffShort = 1;

            DECLARE @UpdShortBatch INT = @@ROWCOUNT;

            -- 2. UPDATE LONG esistenti a blocchi per le chiavi del batch
            UPDATE tgt
            SET tgt.MG87_DESCART     = src.LongNuovo,
                tgt.MG87_DESCARTEST  = src.LongEstesaNuova,
                tgt.MG87_LASTCHANGE  = GETDATE()
            FROM dbo.MG87_ARTDESC AS tgt
            INNER JOIN dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src
                ON  tgt.MG87_DITTA_CG18     = src.Ditta
                AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
                AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
                AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
            INNER JOIN #BatchKeys AS b
                ON  src.Ditta          = b.Ditta
                AND src.CodiceArticolo = b.CodiceArticolo
                AND src.Opzione        = b.Opzione
            WHERE src.DiffLong = 1
              AND src.TipoAzioneLong = 'UPDATE';

            DECLARE @UpdLongBatch INT = @@ROWCOUNT;

            -- 3. INSERT LONG mancanti a blocchi per le chiavi del batch
            INSERT INTO dbo.MG87_ARTDESC (
                MG87_DITTA_CG18, MG87_CODART_MG66, MG87_OPZIONE_MG5E, MG87_LINGUA_MG52,
                MG87_DESCART, MG87_DESCARTEST, MG87_LASTCHANGE, MG87_GUID
            )
            SELECT
                src.Ditta, src.CodiceArticolo, src.Opzione, 'LNG',
                src.LongNuovo, src.LongEstesaNuova, GETDATE(), NEWID()
            FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src
            INNER JOIN #BatchKeys AS b
                ON  src.Ditta          = b.Ditta
                AND src.CodiceArticolo = b.CodiceArticolo
                AND src.Opzione        = b.Opzione
            WHERE src.TipoAzioneLong = 'INSERT'
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.MG87_ARTDESC AS t WITH (NOLOCK)
                  WHERE t.MG87_DITTA_CG18     = src.Ditta
                    AND t.MG87_CODART_MG66    = src.CodiceArticolo
                    AND t.MG87_OPZIONE_MG5E   = src.Opzione
                    AND RTRIM(t.MG87_LINGUA_MG52) = 'LNG'
              );

            DECLARE @InsLongBatch INT = @@ROWCOUNT;

            -- 4. Marcatura DataAdeguamento ESATTAMENTE per gli articoli del batch corrente
            UPDATE src
            SET src.DataAdeguamento = GETDATE()
            FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src
            INNER JOIN #BatchKeys AS b
                ON  src.Ditta          = b.Ditta
                AND src.CodiceArticolo = b.CodiceArticolo
                AND src.Opzione        = b.Opzione;

            DECLARE @MarcatiBatch INT = @@ROWCOUNT;
            DECLARE @OperazioniBatch INT = @UpdShortBatch + @UpdLongBatch + @InsLongBatch;

            SET @TotArticoliBonificati = @TotArticoliBonificati + @MarcatiBatch;
            SET @TotOperazioniMG87     = @TotOperazioniMG87 + @OperazioniBatch;

            COMMIT TRANSACTION;

            PRINT 'Batch ' + CAST(@Ciclo AS VARCHAR(5)) + ' completato: ' +
                  CAST(@MarcatiBatch AS VARCHAR(10)) + ' articoli bonificati (Short Upd: ' +
                  CAST(@UpdShortBatch AS VARCHAR(10)) + ', Long Upd: ' +
                  CAST(@UpdLongBatch AS VARCHAR(10)) + ', Long Ins: ' +
                  CAST(@InsLongBatch AS VARCHAR(10)) + '). Totale progressivo articoli: ' +
                  CAST(@TotArticoliBonificati AS VARCHAR(10)) + '.';

            SET @Ciclo = @Ciclo + 1;

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            PRINT 'ERRORE al Batch ' + CAST(@Ciclo AS VARCHAR(5)) + ':';
            PRINT ERROR_MESSAGE();
            IF OBJECT_ID('tempdb..#BatchKeys') IS NOT NULL DROP TABLE #BatchKeys;
            THROW;
        END CATCH;
    END;

    IF OBJECT_ID('tempdb..#BatchKeys') IS NOT NULL 
        DROP TABLE #BatchKeys;

    -- 5. Se richiesto, alimenta RT12_AGG_DESCR_ART
    IF @AlimentaRT12 = 1
    BEGIN
        INSERT INTO dbo.RT12_AGG_DESCR_ART (RT12_DITTA_CG18, RT12_CODART_MG66, RT12_OPZIONE_MG5E)
        SELECT DISTINCT src.Ditta, src.CodiceArticolo, src.Opzione
        FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS src
        INNER JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
            ON  src.Ditta          = c.CM15_DITTA_CG18
            AND src.CodiceArticolo = c.CM15_CODART_MG66
        WHERE src.Ditta = @Ditta
          AND (@Prefisso IS NULL OR src.Prefisso = @Prefisso)
          AND (@MotivoDifferenza IS NULL OR src.MotivoDifferenza = @MotivoDifferenza)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = src.Ditta
                AND mod.CM15_CODARTMOD_MG66 = src.CodiceArticolo
          )
          AND NOT EXISTS (
              SELECT 1 FROM dbo.RT12_AGG_DESCR_ART AS r WITH (NOLOCK)
              WHERE r.RT12_DITTA_CG18     = src.Ditta
                AND r.RT12_CODART_MG66    = src.CodiceArticolo
                AND r.RT12_OPZIONE_MG5E   = src.Opzione
          );

        DECLARE @RowRT12 INT = @@ROWCOUNT;
        PRINT 'Alimentata RT12_AGG_DESCR_ART con ' + CAST(@RowRT12 AS VARCHAR(10)) + ' chiavi per sincronizzazione batch.';
    END;

    PRINT '====================================================================================';
    PRINT 'BONIFICA COMPLETATA CON SUCCESSO.';
    PRINT 'Totale articoli bonificati in SO_DIFF_DESCRIZIONI_GEMINI : ' + CAST(@TotArticoliBonificati AS VARCHAR(10));
    PRINT 'Totale operazioni applicate su MG87_ARTDESC             : ' + CAST(@TotOperazioniMG87 AS VARCHAR(10));
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END;
GO
