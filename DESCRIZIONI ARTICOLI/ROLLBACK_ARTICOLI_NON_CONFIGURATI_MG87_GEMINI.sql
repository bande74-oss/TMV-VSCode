/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 11:40
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Script di Rollback Articoli Non Configurati e Purge Staging
Nome File                        : ROLLBACK_ARTICOLI_NON_CONFIGURATI_MG87_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Il presente script recepisce la regola cardine dell'architettura ERP Gamma Enterprise per TMV:
L'algoritmo di decodifica e ricostruzione automatica delle descrizioni ('SPRT_TMV_DESCRIZIONE' e
'SFSO_TMV_DESCRIZIONE_GEMINI') ha validità operativa ESCLUSIVAMENTE per gli articoli generati e
configurati a partire da un Articolo Modello all'interno del Configuratore Commerciale ('dbo.CM15_CONFGCOMM').

MOTIVAZIONE TECNICA E RISCHIO DI BUSINESS EVITATO:
1. Gli articoli NON censiti in CM15_CONFGCOMM (es. articoli a disegno cliente come '01950265', viteria speciale
   manuale, articoli commerciali o matrici non parametriche) NON possiedono la struttura di codifica
   dimensionale (diametro, passo, filettatura, norma, classe di finitura) attesa dall'algoritmo.
2. Interrogata su tali articoli, la funzione SQL restituisce stringhe vuote o tronche (es. solo il suffisso
   dell'opzione 'Zn Phosphate', spazzando via la descrizione tecnica principale 'D.1"UNFx166,7 VITI A193 B7...'),
   causando la totale distruzione della descrizione anagrafica manuale.
3. Anche il tracciato batch originale 'VPRT_TMV_AGG_DESCR_ART' prevede strutturalmente la clausola:
   INNER JOIN dbo.CM15_CONFGCOMM AS CM15 ON MG87_DITTA = CM15_DITTA AND MG87_CODART = CM15_CODART

AZIONI ESEGUITE DALLO SCRIPT:
1. Ripristina in 'dbo.MG87_ARTDESC' le descrizioni SHORT originali per i 5 articoli non configurati della
   famiglia 'TD' che erano stati coinvolti nel run pilota (es. TDMB3404229613, TDN00B16D57-8GL350-D48-4P, TDM).
2. Elimina da 'dbo.MG87_ARTDESC' i record di lingua 'LNG' inseriti indebitamente per tali articoli.
3. Rimuove da 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' tutti i 3.309 record di articoli non configurati in CM15
   (inclusi i record a campione '01950265', '01950265 FZO', '01950265 FZS') affinché non compaiano più
   tra le anomalie da bonificare.
4. Rimuove i record non configurati anche da 'dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI'.

Tutto l'intervento è racchiuso in una transazione protetta con blocco TRY...CATCH.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Esecuzione del rollback per gli articoli non configurati e allineamento perimetro di staging a CM15_CONFGCOMM.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '====================================================================================';
PRINT 'AVVIO ROLLBACK ARTICOLI NON CONFIGURATI E PURGE STAGING (Standard SOLVERIS)';
PRINT 'Data e Ora Inizio: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. IDENTIFICAZIONE ARTICOLI NON CONFIGURATI CHE ERANO STATI AGGIORNATI
    DECLARE @ArticoliDaRipristinare TABLE (
        Ditta               DECIMAL(5,0) NOT NULL,
        CodiceArticolo      CHAR(25)     COLLATE DATABASE_DEFAULT NOT NULL,
        Opzione             CHAR(20)     COLLATE DATABASE_DEFAULT NOT NULL,
        ShortAttuale        NVARCHAR(72) NULL,
        ShortEstesaAttuale  NVARCHAR(1672) NULL,
        LongAttuale         NVARCHAR(72) NULL,
        PRIMARY KEY (Ditta, CodiceArticolo, Opzione)
    );

    INSERT INTO @ArticoliDaRipristinare (Ditta, CodiceArticolo, Opzione, ShortAttuale, ShortEstesaAttuale, LongAttuale)
    SELECT 
        d.Ditta, 
        d.CodiceArticolo, 
        d.Opzione, 
        d.ShortAttuale, 
        d.ShortEstesaAttuale, 
        d.LongAttuale
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS d WITH (NOLOCK)
    LEFT JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
        ON  d.Ditta          = c.CM15_DITTA_CG18
        AND d.CodiceArticolo = c.CM15_CODART_MG66
    WHERE d.DataAdeguamento IS NOT NULL
      AND c.CM15_CODART_MG66 IS NULL;

    DECLARE @TotDaRipristinare INT = (SELECT COUNT(*) FROM @ArticoliDaRipristinare);
    PRINT 'Articoli non configurati precedentemente aggiornati da ripristinare: ' + CAST(@TotDaRipristinare AS VARCHAR(10));

    -- 2. RIPRISTINO DESCRIZIONI SHORT ORIGINALI IN MG87_ARTDESC
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
    PRINT '1. Ripristinate ' + CAST(@RipristinatiShort AS VARCHAR(10)) + ' descrizioni SHORT (Italiano) originali in MG87_ARTDESC.';

    -- 3. ELIMINAZIONE RIGHE LNG INSERITE INDEBITAMENTE PER QUESTI ARTICOLI
    DELETE tgt
    FROM dbo.MG87_ARTDESC AS tgt
    INNER JOIN @ArticoliDaRipristinare AS src
        ON  tgt.MG87_DITTA_CG18     = src.Ditta
        AND tgt.MG87_CODART_MG66    = src.CodiceArticolo
        AND tgt.MG87_OPZIONE_MG5E   = src.Opzione
        AND RTRIM(tgt.MG87_LINGUA_MG52) = 'LNG'
    WHERE src.LongAttuale IS NULL;

    DECLARE @EliminatiLongIns INT = @@ROWCOUNT;
    PRINT '2. Eliminate ' + CAST(@EliminatiLongIns AS VARCHAR(10)) + ' righe LONG (Inglese ''LNG'') inserite indebitamente in MG87_ARTDESC.';

    -- 4. EPURAZIONE GENERALE DA SO_DIFF_DESCRIZIONI_GEMINI DI TUTTI GLI ARTICOLI NON IN CM15
    DELETE d
    FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI AS d
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
        WHERE c.CM15_DITTA_CG18  = d.Ditta
          AND c.CM15_CODART_MG66 = d.CodiceArticolo
    );

    DECLARE @EliminatiSO_DIFF INT = @@ROWCOUNT;
    PRINT '3. Rimossi ' + CAST(@EliminatiSO_DIFF AS VARCHAR(10)) + ' record di articoli non derivanti da configuratore da dbo.SO_DIFF_DESCRIZIONI_GEMINI.';

    -- 5. EPURAZIONE DA SO_DIFF_DESCRIZIONI_TD_GEMINI (se esistente)
    IF OBJECT_ID('dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI', 'U') IS NOT NULL
    BEGIN
        DELETE d
        FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI AS d
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
            WHERE c.CM15_DITTA_CG18  = d.Ditta
              AND c.CM15_CODART_MG66 = d.CodiceArticolo
        );

        DECLARE @EliminatiSO_DIFF_TD INT = @@ROWCOUNT;
        PRINT '4. Rimossi ' + CAST(@EliminatiSO_DIFF_TD AS VARCHAR(10)) + ' record di articoli non derivanti da configuratore da dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI.';
    END;

    COMMIT TRANSACTION;

    PRINT '====================================================================================';
    PRINT 'ROLLBACK E ALLINEAMENTO COMPLETATI CON SUCCESSO SENZA ERRORI.';
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

