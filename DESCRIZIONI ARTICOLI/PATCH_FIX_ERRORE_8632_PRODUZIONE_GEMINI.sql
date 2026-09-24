/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 17:15
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : SCRIPT PATCH CHIRURGICO FIX ERRORE MSSQL 8632 (Expression Services Limit)
Nome File                        : PATCH_FIX_ERRORE_8632_PRODUZIONE_GEMINI.sql
Ambiente Database Destinazione   : DBTMV Produzione (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED ANALISI DELLA ROOT CAUSE (ERRORE MSSQL 8632):
Durante l'esecuzione del Master Deploy sul Database di Produzione, la Fase 10 (chiamata alla SP
diagnostica 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI') ha restituito il seguente errore:
    "Messaggio 8632, livello 17, stato 2, procedura dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI, riga 84
     Internal error: An expression services limit has been reached. Please look for potentially 
     complex expressions in your query, and try to simplify them."

ANALISI TECNICA APPROFONDITA DEL COMPILATORE SQL SERVER:
1. Nella precedente formulazione, la funzione 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' era definita
   come INLINE Table-Valued Function (iTVF con clausola RETURNS TABLE AS RETURN (...)), composta
   da 5 CTE concatenate ('PuliziaBase', 'AnalisiLunghezza', 'PuntoDiTaglioCandidato', 'PuntoDiTaglioProtetto',
   'EstrazioneCampi') ricche di logiche condizionali (CASE, REVERSE, CHARINDEX, SUBSTRING).
2. All'interno della SP diagnostica, la funzione veniva invocata per due volte in CROSS APPLY (per Short e Long)
   alimentata dalla complessa funzione scalare 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI'.
3. Poiché iTVF forza il Query Optimizer di SQL Server ad espandere "in linea" l'intero albero sintattico
   delle 5 CTE per CIASCUN riferimento alle colonne ('DescrizionePrimaria' e 'DescrizioneEstesa') nelle decine
   di espressioni di confronto (DiffShort, DiffLong, MotivoDifferenza con 7 rami WHEN), la profondità
   dell'Abstract Syntax Tree (AST) ha superato il limite fisico dell'Expression Services Engine (limite ~100 livelli).

SOLUZIONE CHIRURGICA APPLICATA (Rev. 2.1):
1. Riconversione di 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' in MULTI-STATEMENT Table-Valued Function (mTVF)
   con tabella di ritorno '@Result TABLE (...)'. SQL Server compila ed esegue la mTVF come routine autonoma,
   trattandola come "black box" a costo fisso e azzerando completamente la profondità dell'albero sintattico
   del chiamante.
2. Inserimento nella mTVF sia dei nomi standard ('DescrizionePrimaria', 'DescrizioneEstesa') sia degli
   alias storici ('Descr', 'DescrEst') per garantire totale retrocompatibilità con tutti i chiamanti.
3. Inserimento nella SP diagnostica di una clausola 'DELETE' preventiva mirata sul singolo prefisso prima
   dell'INSERT, scongiurando qualsiasi rischio di duplicazione su Primary Key in caso di rilancio.

ISTRUZIONI OPERATIVE:
Eseguire questo script su DBTMV Produzione per applicare istantaneamente il fix e lanciare la diagnostica.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT '====================================================================================';
PRINT 'AVVIO APPLICAZIONE PATCH FIX ERRORE 8632 (Rev. 2.1 SOLVERIS GEMINI)';
PRINT 'Data e Ora: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';
GO

-- =================================================================================================
-- STEP 1: RICONVERSIONE dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI IN MULTI-STATEMENT TVF
-- =================================================================================================
PRINT '>>> [STEP 1/3] Riconversione dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI in Multi-Statement TVF...';
GO

IF OBJECT_ID(N'[dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI]') IS NOT NULL
    DROP FUNCTION [dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI];
GO

CREATE FUNCTION dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI
(
    @TestoGrezzo VARCHAR(MAX)
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

    -- 1. Se la stringa pulita entra interamente nei 72 caratteri fisici di MG87_DESCART
    IF LEN(@Clean) <= 72
    BEGIN
        IF LEN(@Clean) <= 70
        BEGIN
            DECLARE @d70 VARCHAR(72) = @Clean + CHAR(13) + CHAR(10);
            INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
            VALUES (@d70, NULL, @d70, NULL);
            RETURN;
        END
        ELSE
        BEGIN
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
            DECLARE @after VARCHAR(20) = LTRIM(SUBSTRING(@Clean, @pos + 1, 10));

            -- Presidi: non spezzare prima di unità di misura, virgole, frazioni o subito dopo 'Ø'
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

    -- Fallback se non trovato alcuno spazio utile
    IF @cut = 0 
        SET @cut = 70;

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

PRINT '>>> STEP 1 COMPLETATO con successo. Funzione dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI riconvertita a mTVF.';
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
    PRINT 'AVVIO DIAGNOSTICA GLOBALE: dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.1)';
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
        WHERE Ditta = @Ditta AND Prefisso = @PrefissoCorrente;

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
    PRINT 'Durata totale scansione: ' + CAST(DATEDIFF(MINUTE, @InizioGlobal, GETDATE()) AS VARCHAR(5)) + ' minuti.';
    PRINT '====================================================================================';
END;
GO

PRINT '>>> STEP 2 COMPLETATO con successo. Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI aggiornata.';
GO

-- =================================================================================================
-- STEP 3: ESECUZIONE DIAGNOSTICA SU PRODUZIONE (Popolamento SO_DIFF_DESCRIZIONI_GEMINI)
-- =================================================================================================
PRINT '>>> [STEP 3/3] Avvio Esecuzione Diagnostica Preventiva...';
PRINT '>>> ATTENZIONE: Scansione massiva in sola lettura dell''archivio di produzione.';
PRINT '>>> Tempo stimato: circa 15-20 minuti.';
GO

EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
    @Ditta              = 1,
    @FiltroFamiglia     = NULL, -- Scansiona tutte le famiglie di produzione
    @PulisciTabella     = 1,
    @SoloConDifferenze  = 1;
GO

PRINT '>>> DIAGNOSTICA ESEGUITA CON SUCCESSO. SO_DIFF_DESCRIZIONI_GEMINI popolata.';
GO

-- =================================================================================================
-- QUERY DI VERIFICA IMMEDIATA DEI RISULTATI
-- =================================================================================================
SELECT 
    MotivoDifferenza,
    COUNT(*) AS TotaleArticoli,
    SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END) AS ShortDaAggiornare,
    SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END) AS LongDaAggiornare,
    SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END) AS LongDaInserire
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY MotivoDifferenza
ORDER BY TotaleArticoli DESC;
GO

SELECT 
    CodiceArticolo,
    ShortAttuale,
    ShortNuovo,
    LongAttuale,
    LongNuovo,
    MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE CodiceArticolo LIKE '%M1254-%';
GO

