/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 12:40
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI
Nome File                        : SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI' è il motore diagnostico universale
e massivo per il controllo di qualità e conformità delle descrizioni su TUTTA la base dati aziendale
di TMV in Gamma Enterprise (oltre 652.000 combinazioni articolo/opzione in MG87_ARTDESC).

ARCHITETTURA SCALABILE AD ALTE PRESTAZIONI (Chunking per Prefisso Famigliare a 3 Caratteri):
Per gestire una mole dati di centinaia di migliaia di articoli senza incorrere in saturazioni del
transaction log, lock prolungati o esaurimento delle risorse di memoria tempdb, la procedura:
1. Isola l'elenco dei prefissi distinti a 3 caratteri presenti in anagrafica configuratore (CM15_CONFGCOMM),
   escludendo tassativamente gli articoli modello matrice (VPRT_ARTICOLI_MODELLO) e gli articoli non
   configurati a disegno/manuali.
2. Elabora l'archivio famiglia per famiglia all'interno di un loop controllato a blocchi isolati.
3. Invoca la funzione centrale 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI' sia per SHORT che per LONG.
4. Applica la funzione 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' per lo spezzamento intelligente protetto:
   - Salvaguardia totale delle unità di misura ('mm', 'mt', 'in'): impedisce di separare il valore dalla sua unità.
   - Eliminazione totale degli spazi di coda (trailing spaces).
   - Aggiunta tassativa del ritorno a capo CR+LF (CHAR(13)+CHAR(10)) a fine campo solo se non vuoto/NULL.
5. Esegue il confronto semantico normalizzato tra testo attuale e calcolato, azzerando i falsi positivi
   dovuti a mere discrepanze invisibili di whitespace.
6. Emette a console un feedback in tempo reale al completamento di ogni prefisso.

PARAMETRI DI INPUT:
- @Ditta              : DECIMAL(5,0) = 1 (Identificativo ditta).
- @FiltroFamiglia     : VARCHAR(25) = NULL (Se NULL, scansiona l'INTERO DATABASE; se valorizzato,
                        es. 'TDP%', 'VTF%', elabora esclusivamente la famiglia specificata).
- @PulisciTabella     : BIT = 1 (Se 1, pulisce preventivamente i dati della tabella globale per l'ambito selezionato).
- @SoloConDifferenze  : BIT = 1 (Se 1, memorizza esclusivamente gli articoli con almeno una discrepanza reale).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della procedura di controllo massivo globale senza filtri restrittivi.
- Rev. 1.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Esclusione tassativa degli articoli modello censiti in 'dbo.VPRT_ARTICOLI_MODELLO' (CM15_CONFGCOMM).
- Rev. 1.2 (24/09/2026 - SOLVERIS - Bandera Marco):
  Integrazione vincolo fondamentale su 'dbo.CM15_CONFGCOMM' (INNER JOIN): l'algoritmo di decodifica opera
  tassativamente solo su articoli derivanti da configuratore. Gli articoli manuali/a disegno non configurati
  vengono rigorosamente esclusi per preservare intatte le descrizioni custom.
- Rev. 2.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Adozione dello standard di raggruppamento per prefisso a 3 caratteri (LEFT(m.MG87_CODART_MG66, 3))
  per tutti gli articoli configurati in CM15.
- Rev. 3.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Integrazione della funzione modulare 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' per lo spezzamento intelligente:
  1. Presidio unità di misura: eliminata tassativamente la separazione di 'mm' (e analoghe quote) dal valore numerico.
  2. Presidio CR+LF e spazi di coda: tutte le nuove descrizioni generate terminano con CR+LF (se non vuote/NULL)
     e sono rigorosamente prive di spazi di coda.
  3. Normalizzazione semantica nel confronto differenze: azzeramento dei falsi positivi su articoli con testo identico
     (es. '02700270M5--G-') causati da sole differenze di spaziatura o terminatori di riga.
- Rev. 3.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Allineamento alla Rev. 2.0 di 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI': eliminazione dei falsi positivi da
  ipersensibilità sui 70 caratteri (articoli con testi da 71-72 caratteri non vengono più spezzati in modo fittizio).
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI]
    @Ditta              DECIMAL(5,0)    = 1,
    @FiltroFamiglia     VARCHAR(25)     = NULL,
    @PulisciTabella     BIT             = 1,
    @SoloConDifferenze  BIT             = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InizioGlobal DATETIME = GETDATE();

    PRINT '====================================================================================';
    PRINT 'AVVIO PROCEDURA DIAGNOSTICA GLOBALE: dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.0)';
    PRINT 'Ambito Elaborazione: ' + ISNULL('FAMIGLIA SPECIFICA: ' + @FiltroFamiglia, 'INTERA BASE DATI AZIENDALE (TUTTE LE FAMIGLIE CONFIGURED CM15)');
    PRINT 'Standard Prefisso  : 3 CARATTERI DI CODICE ARTICOLO (Famiglia di Modello)';
    PRINT 'Presidi Attivi     : Salvaguardia Unità Misura (mm) | Terminatore CR+LF | Zero Spazi Coda';
    PRINT 'Ditta              : ' + CAST(@Ditta AS VARCHAR(10));
    PRINT 'Data e Ora Inizio  : ' + CONVERT(VARCHAR(30), @InizioGlobal, 120);
    PRINT '====================================================================================';

    -- Pulizia preventiva mirata
    IF @PulisciTabella = 1
    BEGIN
        IF @FiltroFamiglia IS NULL
        BEGIN
            TRUNCATE TABLE dbo.SO_DIFF_DESCRIZIONI_GEMINI;
            PRINT 'Tabella globale dbo.SO_DIFF_DESCRIZIONI_GEMINI svuotata integralmente (TRUNCATE).';
        END
        ELSE
        BEGIN
            DELETE FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI
            WHERE Ditta = @Ditta AND CodiceArticolo LIKE @FiltroFamiglia;
            PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI ripulita per il filtro: ' + @FiltroFamiglia;
        END;
    END;

    -- Tabella temporanea per elencare i prefissi a 3 caratteri da elaborare a blocchi
    CREATE TABLE #Prefissi (
        IdProg      INT IDENTITY(1,1) PRIMARY KEY,
        Prefisso    VARCHAR(10) NOT NULL,
        TotRecord   INT NOT NULL
    );

    INSERT INTO #Prefissi (Prefisso, TotRecord)
    SELECT 
        LEFT(m.MG87_CODART_MG66, 3) AS Prefisso,
        COUNT(*) AS TotRecord
    FROM dbo.MG87_ARTDESC AS m WITH (NOLOCK)
    INNER JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
        ON  m.MG87_DITTA_CG18  = c.CM15_DITTA_CG18
        AND m.MG87_CODART_MG66 = c.CM15_CODART_MG66
    WHERE m.MG87_DITTA_CG18 = @Ditta
      AND RTRIM(m.MG87_LINGUA_MG52) = ''
      AND (@FiltroFamiglia IS NULL OR m.MG87_CODART_MG66 LIKE @FiltroFamiglia)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
          WHERE mod.CM15_DITTA_CG18 = m.MG87_DITTA_CG18
            AND mod.CM15_CODARTMOD_MG66 = m.MG87_CODART_MG66
      )
    GROUP BY LEFT(m.MG87_CODART_MG66, 3)
    ORDER BY TotRecord DESC;

    DECLARE @TotPrefissi INT = (SELECT COUNT(*) FROM #Prefissi);
    DECLARE @TotRecordDaElaborare INT = (SELECT ISNULL(SUM(TotRecord), 0) FROM #Prefissi);

    PRINT 'Individuati ' + CAST(@TotPrefissi AS VARCHAR(10)) + ' prefissi/famiglie per un totale di ' + CAST(@TotRecordDaElaborare AS VARCHAR(10)) + ' record da analizzare.';
    PRINT '------------------------------------------------------------------------------------';

    DECLARE @CurProg INT = 1;
    DECLARE @CurPrefisso VARCHAR(10);
    DECLARE @CurTotRecord INT;
    DECLARE @TotDiffTrovate INT = 0;

    WHILE @CurProg <= @TotPrefissi
    BEGIN
        SELECT 
            @CurPrefisso  = Prefisso,
            @CurTotRecord = TotRecord
        FROM #Prefissi
        WHERE IdProg = @CurProg;

        DECLARE @InizioBlocco DATETIME = GETDATE();

        -- Inserimento a blocchi per singolo prefisso con applicazione dello smart split e confronto semantico
        INSERT INTO dbo.SO_DIFF_DESCRIZIONI_GEMINI (
            Ditta, CodiceArticolo, Opzione, Prefisso,
            DiffShort, DiffLong, TipoAzioneShort, TipoAzioneLong,
            ShortAttuale, ShortNuovo, ShortEstesaAttuale, ShortEstesaNuova,
            LongAttuale, LongNuovo, LongEstesaAttuale, LongEstesaNuova,
            MotivoDifferenza, DataRilevamento
        )
        SELECT 
            src.Ditta,
            src.CodiceArticolo,
            src.Opzione,
            @CurPrefisso AS Prefisso,
            src.DiffShort,
            src.DiffLong,
            src.TipoAzioneShort,
            src.TipoAzioneLong,
            src.ShortAttuale,
            src.ShortNuovo,
            src.ShortEstesaAttuale,
            src.ShortEstesaNuova,
            src.LongAttuale,
            src.LongNuovo,
            src.LongEstesaAttuale,
            src.LongEstesaNuova,
            -- Classificazione causale dell'anomalia
            CASE 
                WHEN src.LongAttuale IS NULL THEN 'ASSENZA_DESCRIZIONE_LNG'
                WHEN CHARINDEX(CHAR(216), src.ShortNuovo) > 0 AND CHARINDEX(CHAR(216), ISNULL(src.ShortAttuale, '')) = 0 THEN 'DIAMETRO_RT05_BONIFICATO'
                WHEN CHARINDEX('modello', ISNULL(src.ShortAttuale, '')) > 0 OR CHARINDEX('Min.0', ISNULL(src.ShortAttuale, '')) > 0 THEN 'BONIFICA_TESTO_MODELLO'
                WHEN CHARINDEX('UNS S020910', ISNULL(src.LongAttuale, '')) > 0 THEN 'BONIFICA_REFUSO_UNS'
                WHEN src.DiffShort = 1 AND src.DiffLong = 1 THEN 'RETTIFICA_SHORT_E_LONG'
                WHEN src.DiffShort = 1 THEN 'RETTIFICA_SOLO_SHORT'
                WHEN src.DiffLong = 1 THEN 'RETTIFICA_SOLO_LONG'
                ELSE 'ALLINEATO'
            END AS MotivoDifferenza,
            GETDATE()
        FROM (
            SELECT 
                m.MG87_DITTA_CG18       AS Ditta,
                m.MG87_CODART_MG66      AS CodiceArticolo,
                m.MG87_OPZIONE_MG5E     AS Opzione,
                m.MG87_DESCART          AS ShortAttuale,
                m.MG87_DESCARTEST       AS ShortEstesaAttuale,
                s_split.Descr           AS ShortNuovo,
                s_split.DescrEst        AS ShortEstesaNuova,
                l_mg87.MG87_DESCART     AS LongAttuale,
                l_mg87.MG87_DESCARTEST  AS LongEstesaAttuale,
                l_split.Descr           AS LongNuovo,
                l_split.DescrEst        AS LongEstesaNuova,

                -- Differenza su SHORT: confronto semantico normalizzato (ignora differenze puramente estetiche di whitespace/CRLF di coda)
                CASE 
                    WHEN TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(m.MG87_DESCART, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(s_split.Descr, ''), CHAR(13), ''))
                      OR TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(m.MG87_DESCARTEST, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(s_split.DescrEst, ''), CHAR(13), ''))
                    THEN 1 ELSE 0 
                END AS DiffShort,

                -- Differenza su LONG: confronto semantico normalizzato
                CASE 
                    WHEN l_mg87.MG87_CODART_MG66 IS NULL THEN 1
                    WHEN TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_mg87.MG87_DESCART, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_split.Descr, ''), CHAR(13), ''))
                      OR TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_mg87.MG87_DESCARTEST, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_split.DescrEst, ''), CHAR(13), ''))
                    THEN 1 ELSE 0 
                END AS DiffLong,

                -- Tipo Azione SHORT
                CASE 
                    WHEN TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(m.MG87_DESCART, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(s_split.Descr, ''), CHAR(13), ''))
                      OR TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(m.MG87_DESCARTEST, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(s_split.DescrEst, ''), CHAR(13), ''))
                    THEN 'UPDATE' ELSE 'INVARIATO' 
                END AS TipoAzioneShort,

                -- Tipo Azione LONG
                CASE 
                    WHEN l_mg87.MG87_CODART_MG66 IS NULL THEN 'INSERT'
                    WHEN TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_mg87.MG87_DESCART, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_split.Descr, ''), CHAR(13), ''))
                      OR TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_mg87.MG87_DESCARTEST, ''), CHAR(13), ''))
                         <> TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM REPLACE(ISNULL(l_split.DescrEst, ''), CHAR(13), ''))
                    THEN 'UPDATE' ELSE 'INVARIATO' 
                END AS TipoAzioneLong

            FROM dbo.MG87_ARTDESC AS m WITH (NOLOCK)
            INNER JOIN dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
                ON  m.MG87_DITTA_CG18  = c.CM15_DITTA_CG18
                AND m.MG87_CODART_MG66 = c.CM15_CODART_MG66

            -- Calcolo e spezzamento intelligente protetto SHORT
            CROSS APPLY (
                SELECT dbo.SFSO_TMV_DESCRIZIONE_GEMINI(m.MG87_DITTA_CG18, m.MG87_CODART_MG66, m.MG87_OPZIONE_MG5E, 'SHORT') AS ValRaw
            ) AS s_calc
            CROSS APPLY dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(s_calc.ValRaw) AS s_split

            -- Calcolo e spezzamento intelligente protetto LONG
            CROSS APPLY (
                SELECT dbo.SFSO_TMV_DESCRIZIONE_GEMINI(m.MG87_DITTA_CG18, m.MG87_CODART_MG66, m.MG87_OPZIONE_MG5E, 'LONG') AS ValRaw
            ) AS l_calc
            CROSS APPLY dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(l_calc.ValRaw) AS l_split

            -- Join con record esistente in lingua 'LNG'
            LEFT JOIN dbo.MG87_ARTDESC AS l_mg87 WITH (NOLOCK)
                ON  l_mg87.MG87_DITTA_CG18     = m.MG87_DITTA_CG18
                AND l_mg87.MG87_CODART_MG66    = m.MG87_CODART_MG66
                AND l_mg87.MG87_OPZIONE_MG5E   = m.MG87_OPZIONE_MG5E
                AND RTRIM(l_mg87.MG87_LINGUA_MG52) = 'LNG'

            WHERE m.MG87_DITTA_CG18 = @Ditta
              AND m.MG87_CODART_MG66 LIKE @CurPrefisso + '%'
              AND RTRIM(m.MG87_LINGUA_MG52) = ''
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
                  WHERE mod.CM15_DITTA_CG18 = m.MG87_DITTA_CG18
                    AND mod.CM15_CODARTMOD_MG66 = m.MG87_CODART_MG66
              )
        ) AS src
        WHERE (@SoloConDifferenze = 0 OR src.DiffShort = 1 OR src.DiffLong = 1);

        DECLARE @DiffBlocco INT = @@ROWCOUNT;
        SET @TotDiffTrovate = @TotDiffTrovate + @DiffBlocco;

        DECLARE @SecBlocco INT = DATEDIFF(SECOND, @InizioBlocco, GETDATE());

        PRINT '[' + CAST(@CurProg AS VARCHAR(5)) + '/' + CAST(@TotPrefissi AS VARCHAR(5)) + '] ' +
              'Famiglia ''' + @CurPrefisso + '%'' (' + CAST(@CurTotRecord AS VARCHAR(10)) + ' record) elaborata in ' +
              CAST(@SecBlocco AS VARCHAR(5)) + 's. Discrepanze trovate: ' + CAST(@DiffBlocco AS VARCHAR(10));

        SET @CurProg = @CurProg + 1;
    END;

    DECLARE @SecondiGlobali INT = DATEDIFF(SECOND, @InizioGlobal, GETDATE());

    PRINT '====================================================================================';
    PRINT 'DIAGNOSI GLOBALE COMPLETATA CON SUCCESSO IN ' + CAST(@SecondiGlobali AS VARCHAR(10)) + ' SECONDI.';
    PRINT 'Totale discrepanze reali archiviate in SO_DIFF_DESCRIZIONI_GEMINI: ' + CAST(@TotDiffTrovate AS VARCHAR(10));
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END;
GO
