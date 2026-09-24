/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 11:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Script di Ripristino (Rollback) Articoli Modello dbo.MG87_ARTDESC
Nome File                        : ROLLBACK_ARTICOLI_MODELLO_MG87_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Il presente script esegue il ripristino ("Rollback") immediato e controllato delle descrizioni originali
su 'dbo.MG87_ARTDESC' per tutti gli articoli censiti come "Articoli Modello" nella vista di configuratore
'dbo.VPRT_ARTICOLI_MODELLO' (originati da CM15_CONFGCOMM) che erano stati erroneamente coinvolti
nell'adeguamento pilota delle descrizioni (famiglia 'TD').

MOTIVAZIONE DI BUSINESS DELLA REGOLA:
Gli articoli modello rappresentano matrici astratte di configurazione commerciale di Gamma Enterprise
e NON articoli fisici/dimensionali finiti. Di conseguenza:
1. La funzione di calcolo descrizioni 'SFSO_TMV_DESCRIZIONE_GEMINI' / 'SPRT_TMV_DESCRIZIONE' riceve per
   questi articoli stringhe dimensionali prive dei necessari parametri (diametro, passo, minorazione, norma)
   e produce stringhe vuote.
2. Gli articoli modello DEVONO mantenere intatta la propria descrizione anagrafica esistente (spesso contenente
   la dicitura 'modello', 'DWG. modello' o specifiche generiche ad uso dell'ufficio commerciale/tecnico).
3. Non devono essere inserite descrizioni in lingua estera ('LNG') fittizie o vuote per questi modelli.

STRATEGIA DI RIPRISTINO:
Lo script attinge ai valori storici fedelmente congelati prima dell'adeguamento nella tabella di staging
'dbo.SO_DIFF_DESCRIZIONI_GEMINI' (colonne ShortAttuale e ShortEstesaAttuale):
1. Aggiorna i record di lingua italiana (MG87_LINGUA_MG52 = '') ripristinando ShortAttuale e ShortEstesaAttuale.
2. Elimina i record in lingua inglese ('LNG') che erano stati inseriti ex-novo con descrizione vuota
   (riconoscibili in quanto LongAttuale era NULL).
3. Rimuove i record degli articoli modello da 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' e 'dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI'
   affinché non compaiano più tra le anomalie o le discrepanze da bonificare.

Tutto l'intervento è racchiuso in una transazione protetta con blocco TRY...CATCH.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Esecuzione del rollback selettivo per gli 8 articoli modello della famiglia 'TD' erroneamente bonificati
  e contestuale pulizia delle tabelle di staging da qualsiasi articolo modello.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '====================================================================================';
PRINT 'AVVIO SCRIPT DI ROLLBACK DESCRIZIONI ARTICOLI MODELLO (Standard SOLVERIS)';
PRINT 'Data e Ora Inizio: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. IDENTIFICAZIONE ARTICOLI MODELLO COINVOLTI NELL'ADEGUAMENTO
    DECLARE @ModelliCoinvolti TABLE (
        Ditta           DECIMAL(5,0) NOT NULL,
        CodiceArticolo  CHAR(25)     COLLATE DATABASE_DEFAULT NOT NULL,
        Opzione         CHAR(20)     COLLATE DATABASE_DEFAULT NOT NULL,
        ShortAttuale    NVARCHAR(72) NULL,
        ShortEstesaAttuale NVARCHAR(1672) NULL,
        LongAttuale     NVARCHAR(72) NULL,
        PRIMARY KEY (Ditta, CodiceArticolo, Opzione)
    );

    INSERT INTO @ModelliCoinvolti (Ditta, CodiceArticolo, Opzione, ShortAttuale, ShortEstesaAttuale, LongAttuale)
    SELECT 
        d.Ditta, 
        d.CodiceArticolo, 
        d.Opzione, 
        d.ShortAttuale, 
        d.ShortEstesaAttuale, 
        d.LongAttuale
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS d WITH (NOLOCK)
    INNER JOIN dbo.VPRT_ARTICOLI_MODELLO AS m WITH (NOLOCK)
        ON  d.Ditta          = m.CM15_DITTA_CG18
        AND d.CodiceArticolo = m.CM15_CODARTMOD_MG66
    WHERE d.DataAdeguamento IS NOT NULL;

    DECLARE @TotDaRipristinare INT = (SELECT COUNT(*) FROM @ModelliCoinvolti);
    PRINT 'Articoli modello precedentemente adeguati da ripristinare: ' + CAST(@TotDaRipristinare AS VARCHAR(10));

    -- 2. RIPRISTINO DESCRIZIONI SHORT (ITALIANO) IN MG87_ARTDESC
    UPDATE tgt
    SET tgt.MG87_DESCART     = src.ShortAttuale,
        tgt.MG87_DESCARTEST  = src.ShortEstesaAttuale,
        tgt.MG87_LASTCHANGE  = GETDATE()
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ModelliCoinvolti AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = '';

    DECLARE @RipristinatiShort INT = @@ROWCOUNT;
    PRINT '1. Ripristinate ' + CAST(@RipristinatiShort AS VARCHAR(10)) + ' descrizioni SHORT (Italiano) originali in MG87_ARTDESC.';

    -- 3. ELIMINAZIONE RIGHE LNG INSERITE EX-NOVO PER GLI ARTICOLI MODELLO
    DELETE tgt
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ModelliCoinvolti AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
    WHERE src.LongAttuale IS NULL;

    DECLARE @EliminatiLongIns INT = @@ROWCOUNT;
    PRINT '2. Eliminate ' + CAST(@EliminatiLongIns AS VARCHAR(10)) + ' righe LONG (Inglese ''LNG'') inserite indebitamente in MG87_ARTDESC.';

    -- 4. EPURAZIONE ARTICOLI MODELLO DA SO_DIFF_DESCRIZIONI_GEMINI
    DELETE d
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS d
    INNER JOIN dbo.VPRT_ARTICOLI_MODELLO AS m WITH (NOLOCK)
        ON  d.Ditta          = m.CM15_DITTA_CG18
        AND d.CodiceArticolo = m.CM15_CODARTMOD_MG66;

    DECLARE @EliminatiSO_DIFF INT = @@ROWCOUNT;
    PRINT '3. Rimossi ' + CAST(@EliminatiSO_DIFF AS VARCHAR(10)) + ' record di articoli modello da dbo.SO_DIFF_DESCRIZIONI_GEMINI.';

    -- 5. EPURAZIONE ARTICOLI MODELLO DA SO_DIFF_DESCRIZIONI_TD_GEMINI (se esistente)
    IF OBJECT_ID('dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI', 'U') IS NOT NULL
    BEGIN
        DELETE d
        FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS d
        INNER JOIN dbo.VPRT_ARTICOLI_MODELLO AS m WITH (NOLOCK)
            ON  d.Ditta          = m.CM15_DITTA_CG18
            AND d.CodiceArticolo = m.CM15_CODARTMOD_MG66;

        DECLARE @EliminatiSO_DIFF_TD INT = @@ROWCOUNT;
        PRINT '4. Rimossi ' + CAST(@EliminatiSO_DIFF_TD AS VARCHAR(10)) + ' record di articoli modello da dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI.';
    END;

    COMMIT TRANSACTION;

    PRINT '====================================================================================';
    PRINT 'ROLLBACK COMPLETATO CON SUCCESSO SENZA ERRORI.';
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'ERRORE DURANTE L''ESECUZIONE DEL ROLLBACK:';
    PRINT ERROR_MESSAGE();
    THROW;
END CATCH;
GO

