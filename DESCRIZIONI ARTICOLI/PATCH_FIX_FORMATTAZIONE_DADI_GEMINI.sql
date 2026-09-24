/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 18:05
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : SCRIPT DI PATCH RAPIDA: Correzione Formattazione e Spaziatura Dadi
Nome File                        : PATCH_FIX_FORMATTAZIONE_DADI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED ANALISI DELL'ANOMALIA:
Durante la fase di collaudo e verifica post-diagnostica su base dati di produzione (Check 4),
è emersa un'evidente aberrazione estetica nella colonna 'ShortNuovo' generata per la famiglia dei dadi
(es. prefisso 'D--', articoli come 'D--00002M160G-', 'D--00025M160G-', 'D--0010-M1104-'):
- Testo Attuale : 'Hex Nut DIN 934 H=D  HASTELLOY X/UNS N06002  M160 Passo Grosso'
- Testo Nuovo   : 'Hex Nut DIN 934 H=DHASTELLOY X/UNS N06002M160x8'

RADICE TECNICA DEL DIFETTO (Root Cause):
1. In TeamSystem Gamma Enterprise, il 99.5% delle descrizioni anagrafiche in 'MG87_DESCART' è nativamente
   strutturato su righe multiple: la Tipologia (es. 'Hex Nut DIN 934 H=D') termina con un ritorno a capo
   completo CR+LF (CHAR(13)+CHAR(10)), il Materiale (es. 'HASTELLOY X/UNS N06002') termina anch'esso
   con CR+LF, e la specifica di Diametro/Passo (es. 'M160x8') occupa la riga finale.
2. Nella precedente Patch per l'Errore 8632, all'interno della funzione 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI',
   l'istruzione di pulizia preliminare era stata impostata come:
   DECLARE @Clean VARCHAR(MAX) = RTRIM(LTRIM(REPLACE(REPLACE(@TestoGrezzo, CHAR(13), ''), CHAR(10), '')));
3. Questa istruzione ha eliminato indiscriminatamente TUTTI i caratteri di ritorno a capo INTERNI alla stringa,
   rimuovendo il separatore naturale tra le righe senza sostituirlo con alcuno spazio.
   Di conseguenza, l'ultimo carattere della riga 1 ('H=D') si è fuso direttamente con il primo della riga 2
   ('HASTELLOY' -> 'H=DHASTELLOY') e l'ultimo carattere del materiale ('N06002') si è incollato al diametro
   ('M160x8' -> 'N06002M160x8').
4. Inoltre, poiché 'ShortAttuale' in 'MG87_DESCART' possiede i ritorni a capo mentre 'ShortNuovo' ne era
   privato, e la formula di confronto eseguiva RTRIM PRIMA di eliminare i ritorni a capo (non rimuovendo
   gli spazi di coda dell'ultima riga prima del CR+LF), centinaia di migliaia di articoli conformi sono
   risultati fittiziamente classificati come 'RETTIFICA_SOLO_SHORT'.

RISOLUZIONE APPLICATA CON QUESTA PATCH:
1. STEP 1 - Bonifica 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI':
   Sostituzione del distruttivo REPLACE con TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM @TestoGrezzo).
   La funzione TRIM con set di caratteri (nativa di SQL Server 2017) opera ESCLUSIVAMENTE sui bordi esterni
   (iniziali e finali) della stringa, preservando integralmente i ritorni a capo interni (CHAR(13)+CHAR(10))
   tra Tipologia, Materiale e Diametro.
   Aggiunta la salvaguardia del blocco diametro: impedisce lo spezzamento subito dopo il simbolo 'Ø' o CHAR(216).
2. STEP 2 - Aggiornamento 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI':
   - Inversione dell'ordine di pulizia nel confronto semantico: RTRIM(REPLACE(REPLACE(testo, CR, ''), LF, ''))
     assicura che gli spazi residui di fine riga vengano eliminati DOPO la rimozione del CR+LF, azzerando i falsi positivi.
   - Iniezione della clausola (@FiltroFamiglia IS NULL OR mShort.MG87_CODART_MG66 LIKE @FiltroFamiglia)
     all'interno del cursore a blocchi per consentire scansioni mirate istantanee.
3. STEP 3 - Ricalcolo Immediato della Famiglia Dadi 'D--%':
   Esecuzione selettiva per ricalcolare e riallineare istantaneamente la tabella 'SO_DIFF_DESCRIZIONI_GEMINI'.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '====================================================================================';
PRINT 'AVVIO APPLICAZIONE PATCH FIX FORMATTAZIONE DADI (Rev. 2.2 SOLVERIS GEMINI)';
PRINT 'Data e Ora: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';
GO

-- =================================================================================================
-- STEP 1: RICONVERSIONE dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI (PRESERVAZIONE CRLF INTERNI)
-- =================================================================================================
PRINT '>>> [STEP 1/3] Aggiornamento dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI...';
GO

IF OBJECT_ID(N'[dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI]') IS NOT NULL
    DROP FUNCTION [dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI];
GO

CREATE FUNCTION dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI
(
    @TestoGrezzo NVARCHAR(MAX)
)
RETURNS @Result TABLE
(
    DescrizionePrimaria  VARCHAR(72)    NULL,
    DescrizioneEstesa    VARCHAR(1672)  NULL,
    Descr                VARCHAR(72)    NULL,
    DescrEst             VARCHAR(1672)  NULL
)
AS
BEGIN
    IF @TestoGrezzo IS NULL
    BEGIN
        INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
        VALUES (NULL, NULL, NULL, NULL);
        RETURN;
    END;

    -- Pulizia preliminare: eliminazione di spazi, tabulazioni e ritorni a capo SOLO AI BORDI (iniziali e finali)
    -- I ritorni a capo INTERNI (tra Tipologia, Materiale, Diametro) DEVONO ESSERE PRESERVATI INTEGRALMENTE!
    DECLARE @Clean VARCHAR(MAX) = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM @TestoGrezzo);

    IF @Clean = ''
    BEGIN
        INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
        VALUES (NULL, NULL, NULL, NULL);
        RETURN;
    END;

    -- 1. Se la stringa pulita entra interamente nei 72 caratteri fisici di MG87_DESCART:
    --    non richiede alcuno spezzamento e viene allocata interamente nella descrizione primaria.
    IF LEN(@Clean) <= 72
    BEGIN
        -- Se <= 70 caratteri, possiamo accodare il terminatore CR+LF finale rimanendo entro 72 caratteri
        IF LEN(@Clean) <= 70
        BEGIN
            DECLARE @d70 VARCHAR(72) = @Clean + CHAR(13) + CHAR(10);
            INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
            VALUES (@d70, NULL, @d70, NULL);
            RETURN;
        END
        ELSE
        BEGIN
            -- Se esattamente 71 o 72 caratteri, occupa per intero il campo:
            -- salvaguardiamo la stringa intera senza spezzarla e senza aggiungere CR+LF di coda
            INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
            VALUES (@Clean, NULL, @Clean, NULL);
            RETURN;
        END;
    END;

    -- 2. Se supera i 72 caratteri, ricerca del punto di spezzamento a ritroso da posizione 71
    DECLARE @cut INT = 0;
    DECLARE @pos INT = 71;

    WHILE @pos > 1
    BEGIN
        IF SUBSTRING(@Clean, @pos, 1) IN (' ', CHAR(13), CHAR(10))
        BEGIN
            -- Isola la porzione testuale successiva allo spazio/separatore (eliminando spazi iniziali)
            DECLARE @after VARCHAR(20) = LTRIM(SUBSTRING(@Clean, @pos + 1, 10));

            -- REGOLA FONDAMENTALE DI BUSINESS:
            -- Non spezzare mai se lo spazio precede direttamente:
            -- a) Un'unità di misura ('mm', 'mt', 'in')
            -- b) Una virgola decimale (',')
            -- c) Una frazione numerica di pollice (es. '1/2', '1/4', '3/8')
            -- d) Subito dopo il simbolo diametro 'Ø' (preserva il blocco 'Ø 125 mm' o 'Ø 14,65mm')
            IF @after NOT LIKE 'mm%' 
               AND @after NOT LIKE 'mt%' 
               AND @after NOT LIKE 'in%' 
               AND @after NOT LIKE ',%'
               AND @after NOT LIKE '[0-9]/%'
               AND SUBSTRING(@Clean, @pos - 1, 1) <> CHAR(216)
               AND SUBSTRING(@Clean, @pos - 1, 1) <> 'Ø'
            BEGIN
                SET @cut = @pos;
                BREAK;
            END;
        END;
        SET @pos = @pos - 1;
    END;

    -- Fallback se non trovato alcuno spazio utile: spezza forzatamente al 70° carattere
    IF @cut = 0 
        SET @cut = 70;

    -- Estrazione e pulizia ai bordi delle due porzioni risultanti
    DECLARE @p1 VARCHAR(72)   = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM LEFT(@Clean, @cut));
    DECLARE @p2 VARCHAR(MAX)  = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM SUBSTRING(@Clean, @cut + 1, LEN(@Clean)));

    DECLARE @descr VARCHAR(72) = CASE 
                                     WHEN @p1 = '' THEN NULL 
                                     WHEN LEN(@p1) <= 70 THEN @p1 + CHAR(13) + CHAR(10)
                                     ELSE @p1 
                                 END;
    DECLARE @descrEst VARCHAR(1672) = CASE WHEN @p2 <> '' THEN @p2 + CHAR(13) + CHAR(10) ELSE NULL END;

    INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
    VALUES (@descr, @descrEst, @descr, @descrEst);

    RETURN;
END;
GO

PRINT '>>> STEP 1 COMPLETATO con successo. Funzione dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI aggiornata.';
GO

-- =================================================================================================
-- STEP 2: RICOMPILAZIONE STORED PROCEDURE DIAGNOSTICA dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI
-- =================================================================================================
PRINT '>>> [STEP 2/3] Ricompilazione Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI...';
GO

CREATE OR ALTER PROCEDURE dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI
    @Ditta              DECIMAL(5,0)    = 1,
    @FiltroFamiglia     VARCHAR(25)     = NULL,
    @PulisciTabella     BIT             = 1,
    @SoloConDifferenze  BIT             = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InizioGlobal DATETIME = GETDATE();

    PRINT '====================================================================================';
    PRINT 'AVVIO DIAGNOSTICA GLOBALE: dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.2)';
    PRINT 'Ambito : ' + ISNULL('Famiglia: ' + @FiltroFamiglia, 'INTERA BASE DATI AZIENDALE (Tutte le Famiglie CM15)');
    PRINT 'Ditta  : ' + CAST(@Ditta AS VARCHAR(10));
    PRINT '====================================================================================';

    IF @PulisciTabella = 1
    BEGIN
        IF @FiltroFamiglia IS NULL
        BEGIN
            TRUNCATE TABLE dbo.SO_DIFF_DESCRIZIONI_GEMINI;
            PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI svuotata integralmente (TRUNCATE).';
        END
        ELSE
        BEGIN
            DELETE FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI
            WHERE Ditta = @Ditta AND CodiceArticolo LIKE @FiltroFamiglia;
            PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI ripulita per il filtro: ' + @FiltroFamiglia;
        END;
    END;

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
        ON  m.MG87_DITTA_CG18   = c.CM15_DITTA_CG18
        AND m.MG87_CODART_MG66  = c.CM15_CODART_MG66
    WHERE m.MG87_DITTA_CG18 = @Ditta
      AND RTRIM(m.MG87_LINGUA_MG52) = ''
      AND (@FiltroFamiglia IS NULL OR m.MG87_CODART_MG66 LIKE @FiltroFamiglia)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
          WHERE mod.CM15_DITTA_CG18 = m.MG87_DITTA_CG18
            AND mod.CM15_CODARTMOD_MG66 = m.MG87_CODART_MG66
      )
    GROUP BY LEFT(m.MG87_CODART_MG66, 3)
    ORDER BY LEFT(m.MG87_CODART_MG66, 3);

    DECLARE @TotPrefissi INT = @@ROWCOUNT;
    DECLARE @TotArticoliGlobal INT = 0;
    SELECT @TotArticoliGlobal = SUM(TotRecord) FROM #Prefissi;

    PRINT 'Individuati ' + CAST(@TotPrefissi AS VARCHAR(10)) + ' prefissi/famiglie per un totale di ' +
          CAST(@TotArticoliGlobal AS VARCHAR(10)) + ' record da analizzare.';
    PRINT '------------------------------------------------------------------------------------';

    DECLARE @IdProgCorrente INT = 1;
    DECLARE @PrefissoCorrente VARCHAR(10);
    DECLARE @TotRecordPrefisso INT;
    DECLARE @InizioPrefisso DATETIME;
    DECLARE @SecondiPrefisso INT;
    DECLARE @DiscrepanzePrefisso INT;

    WHILE @IdProgCorrente <= @TotPrefissi
    BEGIN
        SELECT 
            @PrefissoCorrente    = Prefisso,
            @TotRecordPrefisso   = TotRecord
        FROM #Prefissi
        WHERE IdProg = @IdProgCorrente;

        SET @InizioPrefisso = GETDATE();

        -- Pulizia preventiva per il prefisso corrente per prevenire qualsiasi rischio di duplicati PK
        DELETE FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI
        WHERE Ditta = @Ditta AND Prefisso = @PrefissoCorrente
          AND (@FiltroFamiglia IS NULL OR CodiceArticolo LIKE @FiltroFamiglia);

        INSERT INTO dbo.SO_DIFF_DESCRIZIONI_GEMINI (
            Ditta,
            CodiceArticolo,
            Opzione,
            Prefisso,
            DiffShort,
            DiffLong,
            TipoAzioneShort,
            TipoAzioneLong,
            ShortAttuale,
            ShortNuovo,
            ShortEstesaAttuale,
            ShortEstesaNuova,
            LongAttuale,
            LongNuovo,
            LongEstesaAttuale,
            LongEstesaNuova,
            MotivoDifferenza,
            DataRilevamento,
            DataAdeguamento
        )
        SELECT 
            c.Ditta,
            c.CodiceArticolo,
            c.Opzione,
            @PrefissoCorrente AS Prefisso,
            c.DiffShort,
            c.DiffLong,
            CASE WHEN c.DiffShort = 1 THEN 'UPDATE' ELSE 'INVARIATO' END AS TipoAzioneShort,
            CASE 
                WHEN c.LongAttuale IS NULL AND c.LongNuovo IS NOT NULL THEN 'INSERT'
                WHEN c.DiffLong = 1 THEN 'UPDATE'
                ELSE 'INVARIATO'
            END AS TipoAzioneLong,
            c.ShortAttuale,
            c.ShortNuovo,
            c.ShortEstesaAttuale,
            c.ShortEstesaNuova,
            c.LongAttuale,
            c.LongNuovo,
            c.LongEstesaAttuale,
            c.LongEstesaNuova,
            c.MotivoDifferenza,
            GETDATE() AS DataRilevamento,
            NULL AS DataAdeguamento
        FROM (
            SELECT 
                b.Ditta,
                b.CodiceArticolo,
                b.Opzione,
                b.ShortAttuale,
                b.ShortEstesaAttuale,
                spShort.DescrizionePrimaria AS ShortNuovo,
                spShort.DescrizioneEstesa   AS ShortEstesaNuova,
                b.LongAttuale,
                b.LongEstesaAttuale,
                spLong.DescrizionePrimaria  AS LongNuovo,
                spLong.DescrizioneEstesa    AS LongEstesaNuova,

                -- Differenza su SHORT: confronto semantico normalizzato (ignora spazi/CRLF di coda residui)
                CASE 
                    WHEN (
                        ISNULL(RTRIM(b.ShortAttuale), '') <> ISNULL(RTRIM(spShort.DescrizionePrimaria), '')
                        OR ISNULL(RTRIM(b.ShortEstesaAttuale), '') <> ISNULL(RTRIM(spShort.DescrizioneEstesa), '')
                    )
                    AND (
                        ISNULL(RTRIM(REPLACE(REPLACE(b.ShortAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spShort.DescrizionePrimaria, CHAR(13), ''), CHAR(10), '')), '')
                        OR
                        ISNULL(RTRIM(REPLACE(REPLACE(b.ShortEstesaAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spShort.DescrizioneEstesa, CHAR(13), ''), CHAR(10), '')), '')
                    )
                    THEN 1 ELSE 0 
                END AS DiffShort,

                -- Differenza su LONG: confronto semantico normalizzato
                CASE 
                    WHEN b.LongAttuale IS NULL AND spLong.DescrizionePrimaria IS NOT NULL THEN 1
                    WHEN (
                        ISNULL(RTRIM(b.LongAttuale), '') <> ISNULL(RTRIM(spLong.DescrizionePrimaria), '')
                        OR ISNULL(RTRIM(b.LongEstesaAttuale), '') <> ISNULL(RTRIM(spLong.DescrizioneEstesa), '')
                    )
                    AND (
                        ISNULL(RTRIM(REPLACE(REPLACE(b.LongAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spLong.DescrizionePrimaria, CHAR(13), ''), CHAR(10), '')), '')
                        OR
                        ISNULL(RTRIM(REPLACE(REPLACE(b.LongEstesaAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spLong.DescrizioneEstesa, CHAR(13), ''), CHAR(10), '')), '')
                    )
                    THEN 1 ELSE 0 
                END AS DiffLong,

                -- Classificazione causale dell'anomalia
                CASE 
                    WHEN b.LongAttuale IS NULL AND spLong.DescrizionePrimaria IS NOT NULL THEN 'ASSENZA_DESCRIZIONE_LNG'
                    WHEN b.ShortAttuale LIKE '%UNS S020910%' OR b.LongAttuale LIKE '%UNS S020910%' THEN 'BONIFICA_REFUSO_UNS'
                    WHEN (b.ShortAttuale LIKE '%Modello%' OR b.ShortAttuale LIKE '%Min.0%') THEN 'BONIFICA_TESTO_MODELLO'
                    WHEN (b.ShortAttuale LIKE '%M125 4%' OR b.ShortAttuale LIKE '%M125 Passo%') AND spShort.DescrizionePrimaria LIKE '%Ø%' THEN 'DIAMETRO_RT05_BONIFICATO'
                    WHEN (
                        ISNULL(RTRIM(REPLACE(REPLACE(b.ShortAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spShort.DescrizionePrimaria, CHAR(13), ''), CHAR(10), '')), '')
                    ) AND (
                        ISNULL(RTRIM(REPLACE(REPLACE(b.LongAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spLong.DescrizionePrimaria, CHAR(13), ''), CHAR(10), '')), '')
                    ) THEN 'RETTIFICA_SHORT_E_LONG'
                    WHEN (
                        ISNULL(RTRIM(REPLACE(REPLACE(b.ShortAttuale, CHAR(13), ''), CHAR(10), '')), '') <>
                        ISNULL(RTRIM(REPLACE(REPLACE(spShort.DescrizionePrimaria, CHAR(13), ''), CHAR(10), '')), '')
                    ) THEN 'RETTIFICA_SOLO_SHORT'
                    ELSE 'RETTIFICA_SOLO_LONG'
                END AS MotivoDifferenza
            FROM (
                SELECT 
                    mShort.MG87_DITTA_CG18   AS Ditta,
                    mShort.MG87_CODART_MG66  AS CodiceArticolo,
                    mShort.MG87_OPZIONE_MG5E AS Opzione,
                    mShort.MG87_DESCART      AS ShortAttuale,
                    mShort.MG87_DESCARTEST   AS ShortEstesaAttuale,
                    mLong.MG87_DESCART       AS LongAttuale,
                    mLong.MG87_DESCARTEST    AS LongEstesaAttuale,
                    dbo.SFSO_TMV_DESCRIZIONE_GEMINI(mShort.MG87_DITTA_CG18, mShort.MG87_CODART_MG66, mShort.MG87_OPZIONE_MG5E, '')    AS ShortCalcolatoGrezzo,
                    dbo.SFSO_TMV_DESCRIZIONE_GEMINI(mShort.MG87_DITTA_CG18, mShort.MG87_CODART_MG66, mShort.MG87_OPZIONE_MG5E, 'LNG') AS LongCalcolatoGrezzo
                FROM dbo.MG87_ARTDESC AS mShort WITH (NOLOCK)
                LEFT JOIN dbo.MG87_ARTDESC AS mLong WITH (NOLOCK)
                    ON  mShort.MG87_DITTA_CG18     = mLong.MG87_DITTA_CG18
                    AND mShort.MG87_CODART_MG66    = mLong.MG87_CODART_MG66
                    AND mShort.MG87_OPZIONE_MG5E   = mLong.MG87_OPZIONE_MG5E
                    AND RTRIM(mLong.MG87_LINGUA_MG52) = 'LNG'
                WHERE mShort.MG87_DITTA_CG18 = @Ditta
                  AND RTRIM(mShort.MG87_LINGUA_MG52) = ''
                  AND LEFT(mShort.MG87_CODART_MG66, 3) = @PrefissoCorrente
                  AND (@FiltroFamiglia IS NULL OR mShort.MG87_CODART_MG66 LIKE @FiltroFamiglia)
                  AND EXISTS (
                      SELECT 1 FROM dbo.CM15_CONFGCOMM AS c WITH (NOLOCK)
                      WHERE c.CM15_DITTA_CG18  = mShort.MG87_DITTA_CG18
                        AND c.CM15_CODART_MG66 = mShort.MG87_CODART_MG66
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
                      WHERE mod.CM15_DITTA_CG18 = mShort.MG87_DITTA_CG18
                        AND mod.CM15_CODARTMOD_MG66 = mShort.MG87_CODART_MG66
                  )
            ) AS b
            CROSS APPLY dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(b.ShortCalcolatoGrezzo) AS spShort
            CROSS APPLY dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(b.LongCalcolatoGrezzo)  AS spLong
        ) AS c
        WHERE (@SoloConDifferenze = 0 OR c.DiffShort = 1 OR c.DiffLong = 1);

        SET @DiscrepanzePrefisso = @@ROWCOUNT;
        SET @SecondiPrefisso = DATEDIFF(SECOND, @InizioPrefisso, GETDATE());

        PRINT ' Famiglia ''' + @PrefissoCorrente + '%'' (' + CAST(@TotRecordPrefisso AS VARCHAR(10)) + 
              ' record) elaborata in ' + CAST(@SecondiPrefisso AS VARCHAR(5)) + 's. Discrepanze trovate: ' + 
              CAST(@DiscrepanzePrefisso AS VARCHAR(10));

        SET @IdProgCorrente = @IdProgCorrente + 1;
    END;

    DROP TABLE #Prefissi;

    DECLARE @TotDiscrepanzeGlobal INT = 0;
    SELECT @TotDiscrepanzeGlobal = COUNT(*) FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK);

    PRINT '====================================================================================';
    PRINT 'DIAGNOSTICA COMPLETATA CON SUCCESSO.';
    PRINT 'Totale discrepanze registrate in SO_DIFF_DESCRIZIONI_GEMINI: ' + CAST(@TotDiscrepanzeGlobal AS VARCHAR(10));
    PRINT 'Durata totale scansione: ' + CAST(DATEDIFF(SECOND, @InizioGlobal, GETDATE()) AS VARCHAR(10)) + ' secondi.';
    PRINT '====================================================================================';
END;
GO

PRINT '>>> STEP 2 COMPLETATO con successo. Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI aggiornata.';
GO

-- =================================================================================================
-- STEP 3: ESECUZIONE DIAGNOSTICA SELETTIVA DADI (Prefisso 'D--%')
-- =================================================================================================
PRINT '>>> [STEP 3/3] Avvio Ricalcolo Diagnostico per Famiglia Dadi ''D--%''...';
PRINT '>>> Tempo stimato: circa 10-15 secondi.';
GO

EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
    @Ditta              = 1,
    @FiltroFamiglia     = 'D--%', -- Ricalcola e verifica solo i dadi
    @PulisciTabella     = 0,      -- Non svuotare il resto della tabella
    @SoloConDifferenze  = 1;
GO

PRINT '>>> RICALCOLO DADI COMPLETATO CON SUCCESSO.';
GO

-- =================================================================================================
-- QUERY DI VERIFICA IMMEDIATA FORMATTAZIONE DADI (CHECK 4)
-- =================================================================================================
PRINT '>>> VERIFICA FORMATTAZIONE SHORT SU DADI (CHECK 4):';
GO

SELECT TOP 15
    CodiceArticolo,
    Prefisso,
    ShortAttuale,
    ShortNuovo,
    MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE Prefisso = 'D--'
ORDER BY CodiceArticolo;
GO

