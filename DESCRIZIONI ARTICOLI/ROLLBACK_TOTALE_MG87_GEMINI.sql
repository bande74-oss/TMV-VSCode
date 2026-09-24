/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 11:50
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Script di Rollback Totale su dbo.MG87_ARTDESC
Nome File                        : ROLLBACK_TOTALE_MG87_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Il presente script esegue il ripristino integrale ("Rollback Totale") delle descrizioni su 'dbo.MG87_ARTDESC'
per TUTTI gli articoli modificati durante i lanci di test/pilota precedenti, consentendo di ripartire
dalla situazione ORIGINALE del Database prima di rieseguire il ciclo di controllo con il nuovo criterio a 3 lettere.

STRATEGIA DI RIPRISTINO:
Attingendo ai valori storici congelati in 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' per tutti i record che hanno
avuto 'DataAdeguamento IS NOT NULL':
1. Descrizioni SHORT (Italiano - MG87_LINGUA_MG52 = ''):
   Vengono ripristinate fedelmente le colonne 'ShortAttuale' e 'ShortEstesaAttuale'.
2. Descrizioni LONG (Inglese - MG87_LINGUA_MG52 = 'LNG'):
   - Per i record che NON avevano una lingua 'LNG' in origine (LongAttuale IS NULL), la riga creata
     fittiziamente viene eliminata.
   - Per i record che avevano una lingua 'LNG' in origine (LongAttuale IS NOT NULL), viene ripristinato
     il testo storico di 'LongAttuale' e 'LongEstesaAttuale'.
3. Reset del campo 'DataAdeguamento = NULL' in 'SO_DIFF_DESCRIZIONI_GEMINI'.

Tutto l'intervento è racchiuso in una transazione protetta con blocco TRY...CATCH.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Ripristino totale dello stato originale di MG87_ARTDESC su tutto il database per ripartenza pulita.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '====================================================================================';
PRINT 'AVVIO SCRIPT DI ROLLBACK TOTALE DESCRIZIONI MG87_ARTDESC (Standard SOLVERIS)';
PRINT 'Data e Ora Inizio: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. IDENTIFICAZIONE RECORD DA RIPRISTINARE
    DECLARE @ArticoliDaRipristinare TABLE (
        Ditta               DECIMAL(5,0) NOT NULL,
        CodiceArticolo      CHAR(25)     COLLATE DATABASE_DEFAULT NOT NULL,
        Opzione             CHAR(20)     COLLATE DATABASE_DEFAULT NOT NULL,
        ShortAttuale        NVARCHAR(72) NULL,
        ShortEstesaAttuale  NVARCHAR(1672) NULL,
        LongAttuale         NVARCHAR(72) NULL,
        LongEstesaAttuale   NVARCHAR(1672) NULL,
        PRIMARY KEY (Ditta, CodiceArticolo, Opzione)
    );

    INSERT INTO @ArticoliDaRipristinare (
        Ditta, CodiceArticolo, Opzione, 
        ShortAttuale, ShortEstesaAttuale, LongAttuale, LongEstesaAttuale
    )
    SELECT 
        d.Ditta, 
        d.CodiceArticolo, 
        d.Opzione, 
        d.ShortAttuale, 
        d.ShortEstesaAttuale, 
        d.LongAttuale,
        d.LongEstesaAttuale
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS d WITH (NOLOCK)
    WHERE d.DataAdeguamento IS NOT NULL;

    DECLARE @TotDaRipristinare INT = (SELECT COUNT(*) FROM @ArticoliDaRipristinare);
    PRINT 'Articoli totali precedentemente adeguati da ripristinare: ' + CAST(@TotDaRipristinare AS VARCHAR(10));

    -- 2. RIPRISTINO SHORT (ITALIANO) IN MG87_ARTDESC
    UPDATE tgt
    SET tgt.MG87_DESCART     = src.ShortAttuale,
        tgt.MG87_DESCARTEST  = src.ShortEstesaAttuale,
        tgt.MG87_LASTCHANGE  = GETDATE()
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ArticoliDaRipristinare AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = '';

    DECLARE @RipristinatiShort INT = @@ROWCOUNT;
    PRINT '1. Ripristinate ' + CAST(@RipristinatiShort AS VARCHAR(10)) + ' descrizioni SHORT (Italiano) in MG87_ARTDESC.';

    -- 3. ELIMINAZIONE RIGHE LNG INSERITE EX-NOVO (LongAttuale IS NULL)
    DELETE tgt
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ArticoliDaRipristinare AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
    WHERE src.LongAttuale IS NULL;

    DECLARE @EliminatiLongIns INT = @@ROWCOUNT;
    PRINT '2. Eliminate ' + CAST(@EliminatiLongIns AS VARCHAR(10)) + ' righe LONG (Inglese ''LNG'') inserite ex-novo in MG87_ARTDESC.';

    -- 4. RIPRISTINO RIGHE LNG PREESISTENTI (LongAttuale IS NOT NULL)
    UPDATE tgt
    SET tgt.MG87_DESCART     = src.LongAttuale,
        tgt.MG87_DESCARTEST  = src.LongEstesaAttuale,
        tgt.MG87_LASTCHANGE  = GETDATE()
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ArticoliDaRipristinare AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
    WHERE src.LongAttuale IS NOT NULL;

    DECLARE @RipristinatiLong INT = @@ROWCOUNT;
    PRINT '3. Ripristinate ' + CAST(@RipristinatiLong AS VARCHAR(10)) + ' descrizioni LONG preesistenti in MG87_ARTDESC.';

    -- 5. SVUOTAMENTO DELLA TABELLA DI STAGING PER RIPARTENZA PULITA
    TRUNCATE TABLE dbo.SO_DIFF_DESCRIZIONI_GEMINI;
    PRINT '4. Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI svuotata (TRUNCATE) con successo.';

    IF OBJECT_ID('dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI', 'U') IS NOT NULL
    BEGIN
        TRUNCATE TABLE dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI;
        PRINT '5. Tabella dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI svuotata (TRUNCATE) con successo.';
    END;

    COMMIT TRANSACTION;

    PRINT '====================================================================================';
    PRINT 'ROLLBACK TOTALE COMPLETATO CON SUCCESSO SENZA ERRORI.';
    PRINT 'Il database MG87_ARTDESC e lo staging sono tornati allo stato iniziale originale.';
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'ERRORE DURANTE IL ROLLBACK TOTALE:';
    PRINT ERROR_MESSAGE();
    THROW;
END CATCH;
GO

