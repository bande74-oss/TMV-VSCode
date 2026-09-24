/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 09:35
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI
Nome File                        : SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI' è uno strumento diagnostico avanzato
concepito per effettuare una scansione massiva ad alta efficienza di tutti gli articoli della famiglia
tondi, barre e tiranti (filtro di default 'TD%') presenti in anagrafica articoli ('MG87_ARTDESC' / 'MG66_ANAGRART').

RUOLO E FUNZIONAMENTO NEL CONTROLLO QUALITÀ DATI:
La procedura:
1. Isola l'elenco di tutte le combinazioni articolo/opzione censite in MG87 con lingua predefinita.
2. Invoca la funzione algoritmica 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI' per ricalcolare in tempo reale
   sia la descrizione SHORT (lingua italiana predefinita '') sia la descrizione LONG (lingua estera 'LNG').
3. Applica il medesimo spezzamento intelligente protetto a 70 caratteri (evitando di troncare parole).
4. Confronta i valori attuali presenti nel database con i valori ricalcolati:
   - Se individua una discrepanza su SHORT o LONG, oppure se rileva la totale assenza del record 'LNG',
     salva l'anomalia nella tabella di audit 'dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI'.
5. Esegue un'analisi causale del motivo di disallineamento, classificandolo in:
   - 'DIAMETRO_RT05_BONIFICATO' : Il nuovo calcolo introduce la formattazione metrica con simbolo 'Ø' e
     valore in mm (grazie al recente popolamento di RT05), sostituendo la dicitura grezza 'Mxxx passo'.
   - 'ASSENZA_DESCRIZIONE_LNG'  : Mancanza del record in lingua estera in MG87_ARTDESC.
   - 'BONIFICA_TESTO_MODELLO'   : Presenza di testo 'modello' o 'Min.0' derivato da anomalia storica.
   - 'BONIFICA_REFUSO_UNS'      : Correzione di codici UNS errati (es. S020910 -> S20910).
   - 'RETTIFICA_DESCRIZIONE'    : Differenze di spaziatura, punteggiatura o standard filettatura.
6. Emette a console un report completo di audit suddiviso per tipologia (TDP, TDL, TDN, TDM, ecc.)
   e motivo di disallineamento, con campionamento visivo dei record più significativi.

PARAMETRI DI INPUT:
- @Ditta              : DECIMAL(5,0) = 1 (Identificativo ditta Gamma).
- @FiltroArticolo     : VARCHAR(25) = 'TD%' (Maschera filtro per codici articolo).
- @PulisciTabella     : BIT = 1 (Se 1, svuota preventivamente SO_DIFF_DESCRIZIONI_TD_GEMINI).
- @SoloConDifferenze  : BIT = 1 (Se 1, inserisce solo le righe che presentano almeno una discrepanza).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio iniziale della procedura di controllo massivo e auditing differenze descrizioni TD.
- Rev. 1.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Esclusione tassativa degli articoli modello censiti in 'dbo.VPRT_ARTICOLI_MODELLO' (CM15_CONFGCOMM),
  in quanto matrici astratte prive di parametri dimensionali finiti che devono preservare la descrizione originale.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI];
GO

CREATE PROCEDURE [dbo].[SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI]
    @Ditta              DECIMAL(5,0)    = 1,
    @FiltroArticolo     VARCHAR(25)     = 'TD%',
    @PulisciTabella     BIT             = 1,
    @SoloConDifferenze  BIT             = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Inizio DATETIME = GETDATE();

    PRINT '====================================================================================';
    PRINT 'AVVIO PROCEDURA DIAGNOSTICA: dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI';
    PRINT 'Filtro Articoli    : ' + @FiltroArticolo;
    PRINT 'Ditta              : ' + CAST(@Ditta AS VARCHAR(10));
    PRINT 'Data e Ora Inizio  : ' + CONVERT(VARCHAR(30), @Inizio, 120);
    PRINT '====================================================================================';

    IF @PulisciTabella = 1
    BEGIN
        DELETE FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI
        WHERE Ditta = @Ditta 
          AND CodiceArticolo LIKE @FiltroArticolo;
        PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI ripulita per i filtri selezionati.';
    END;

    -- Tabella temporanea per accogliere i risultati calcolati
    CREATE TABLE #StagingDiff (
        Ditta                   DECIMAL(5,0)    NOT NULL,
        CodiceArticolo          CHAR(25)        NOT NULL,
        Opzione                 CHAR(20)        NOT NULL,
        TipologiaTD             CHAR(3)         NOT NULL,
        DiffShort               BIT             NOT NULL,
        DiffLong                BIT             NOT NULL,
        TipoAzioneShort         VARCHAR(15)     NOT NULL,
        TipoAzioneLong          VARCHAR(15)     NOT NULL,
        ShortAttuale            NVARCHAR(72)    NULL,
        ShortNuovo              NVARCHAR(72)    NULL,
        ShortEstesaAttuale      NVARCHAR(1672)  NULL,
        ShortEstesaNuova        NVARCHAR(1672)  NULL,
        LongAttuale             NVARCHAR(72)    NULL,
        LongNuovo               NVARCHAR(72)    NULL,
        LongEstesaAttuale       NVARCHAR(1672)  NULL,
        LongEstesaNuova         NVARCHAR(1672)  NULL,
        MotivoDifferenza        NVARCHAR(250)   NULL
    );

    PRINT 'Elaborazione in corso e calcolo descrizioni con funzione scalare GEMINI...';

    INSERT INTO #StagingDiff (
        Ditta, CodiceArticolo, Opzione, TipologiaTD,
        DiffShort, DiffLong, TipoAzioneShort, TipoAzioneLong,
        ShortAttuale, ShortNuovo, ShortEstesaAttuale, ShortEstesaNuova,
        LongAttuale, LongNuovo, LongEstesaAttuale, LongEstesaNuova,
        MotivoDifferenza
    )
    SELECT 
        src.Ditta,
        src.CodiceArticolo,
        src.Opzione,
        src.TipologiaTD,
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
        -- Classificazione causa disallineamento
        CASE 
            WHEN src.LongAttuale IS NULL THEN 'ASSENZA_DESCRIZIONE_LNG'
            WHEN CHARINDEX(CHAR(216), src.ShortNuovo) > 0 AND CHARINDEX(CHAR(216), ISNULL(src.ShortAttuale, '')) = 0 THEN 'DIAMETRO_RT05_BONIFICATO'
            WHEN CHARINDEX('modello', ISNULL(src.ShortAttuale, '')) > 0 OR CHARINDEX('Min.0', ISNULL(src.ShortAttuale, '')) > 0 THEN 'BONIFICA_TESTO_MODELLO'
            WHEN CHARINDEX('UNS S020910', ISNULL(src.LongAttuale, '')) > 0 THEN 'BONIFICA_REFUSO_UNS'
            WHEN src.DiffShort = 1 AND src.DiffLong = 1 THEN 'RETTIFICA_SHORT_E_LONG'
            WHEN src.DiffShort = 1 THEN 'RETTIFICA_SOLO_SHORT'
            WHEN src.DiffLong = 1 THEN 'RETTIFICA_SOLO_LONG'
            ELSE 'ALLINEATO'
        END AS MotivoDifferenza
    FROM (
        SELECT 
            m.MG87_DITTA_CG18       AS Ditta,
            m.MG87_CODART_MG66      AS CodiceArticolo,
            m.MG87_OPZIONE_MG5E     AS Opzione,
            SUBSTRING(m.MG87_CODART_MG66, 1, 3) AS TipologiaTD,
            m.MG87_DESCART          AS ShortAttuale,
            m.MG87_DESCARTEST       AS ShortEstesaAttuale,
            s_split.DescrS          AS ShortNuovo,
            s_split.DescrSEst       AS ShortEstesaNuova,
            l_mg87.MG87_DESCART     AS LongAttuale,
            l_mg87.MG87_DESCARTEST  AS LongEstesaAttuale,
            l_split.DescrL          AS LongNuovo,
            l_split.DescrLEst       AS LongEstesaNuova,

            -- Differenza su SHORT
            CASE 
                WHEN ISNULL(m.MG87_DESCART, '') <> ISNULL(s_split.DescrS, '') 
                  OR ISNULL(m.MG87_DESCARTEST, '') <> ISNULL(s_split.DescrSEst, '') 
                THEN 1 ELSE 0 
            END AS DiffShort,

            -- Differenza su LONG
            CASE 
                WHEN l_mg87.MG87_CODART_MG66 IS NULL 
                  OR ISNULL(l_mg87.MG87_DESCART, '') <> ISNULL(l_split.DescrL, '') 
                  OR ISNULL(l_mg87.MG87_DESCARTEST, '') <> ISNULL(l_split.DescrLEst, '') 
                THEN 1 ELSE 0 
            END AS DiffLong,

            -- Tipo Azione
            CASE 
                WHEN ISNULL(m.MG87_DESCART, '') <> ISNULL(s_split.DescrS, '') 
                  OR ISNULL(m.MG87_DESCARTEST, '') <> ISNULL(s_split.DescrSEst, '') 
                THEN 'UPDATE' ELSE 'INVARIATO' 
            END AS TipoAzioneShort,

            CASE 
                WHEN l_mg87.MG87_CODART_MG66 IS NULL THEN 'INSERT'
                WHEN ISNULL(l_mg87.MG87_DESCART, '') <> ISNULL(l_split.DescrL, '') 
                  OR ISNULL(l_mg87.MG87_DESCARTEST, '') <> ISNULL(l_split.DescrLEst, '') 
                THEN 'UPDATE' ELSE 'INVARIATO' 
            END AS TipoAzioneLong

        FROM dbo.MG87_ARTDESC AS m WITH (NOLOCK)

        -- Calcolo SHORT
        CROSS APPLY (
            SELECT dbo.SFSO_TMV_DESCRIZIONE_GEMINI(m.MG87_DITTA_CG18, m.MG87_CODART_MG66, m.MG87_OPZIONE_MG5E, 'SHORT') AS ValRaw
        ) AS s_calc
        CROSS APPLY (
            SELECT 
                LEFT(s_calc.ValRaw, 73 - CHARINDEX(' ', REVERSE(LEFT(s_calc.ValRaw, 73)), 0)) AS DescrS,
                TRIM(RIGHT(TRIM(s_calc.ValRaw), LEN(TRIM(s_calc.ValRaw)) - LEN(LEFT(s_calc.ValRaw, 73 - CHARINDEX(' ', REVERSE(LEFT(s_calc.ValRaw, 73)), 0))))) AS DescrSEst
        ) AS s_split

        -- Calcolo LONG
        CROSS APPLY (
            SELECT dbo.SFSO_TMV_DESCRIZIONE_GEMINI(m.MG87_DITTA_CG18, m.MG87_CODART_MG66, m.MG87_OPZIONE_MG5E, 'LONG') AS ValRaw
        ) AS l_calc
        CROSS APPLY (
            SELECT 
                LEFT(l_calc.ValRaw, 73 - CHARINDEX(' ', REVERSE(LEFT(l_calc.ValRaw, 73)), 0)) AS DescrL,
                TRIM(RIGHT(TRIM(l_calc.ValRaw), LEN(TRIM(l_calc.ValRaw)) - LEN(LEFT(l_calc.ValRaw, 73 - CHARINDEX(' ', REVERSE(LEFT(l_calc.ValRaw, 73)), 0))))) AS DescrLEst
        ) AS l_split

        -- Join con record esistente in lingua 'LNG'
        LEFT JOIN dbo.MG87_ARTDESC AS l_mg87 WITH (NOLOCK)
            ON  l_mg87.MG87_DITTA_CG18     = m.MG87_DITTA_CG18
            AND l_mg87.MG87_CODART_MG66    = m.MG87_CODART_MG66
            AND l_mg87.MG87_OPZIONE_MG5E   = m.MG87_OPZIONE_MG5E
            AND RTRIM(l_mg87.MG87_LINGUA_MG52) = 'LNG'

        WHERE m.MG87_DITTA_CG18 = @Ditta
          AND m.MG87_CODART_MG66 LIKE @FiltroArticolo
          AND RTRIM(m.MG87_LINGUA_MG52) = ''
          AND NOT EXISTS (
              SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
              WHERE mod.CM15_DITTA_CG18 = m.MG87_DITTA_CG18
                AND mod.CM15_CODARTMOD_MG66 = m.MG87_CODART_MG66
          )
    ) AS src
    WHERE (@SoloConDifferenze = 0 OR src.DiffShort = 1 OR src.DiffLong = 1);

    -- Trasferimento persistente nella tabella audit
    INSERT INTO dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI (
        Ditta, CodiceArticolo, Opzione, TipologiaTD,
        DiffShort, DiffLong, TipoAzioneShort, TipoAzioneLong,
        ShortAttuale, ShortNuovo, ShortEstesaAttuale, ShortEstesaNuova,
        LongAttuale, LongNuovo, LongEstesaAttuale, LongEstesaNuova,
        MotivoDifferenza, DataRilevamento
    )
    SELECT 
        Ditta, CodiceArticolo, Opzione, TipologiaTD,
        DiffShort, DiffLong, TipoAzioneShort, TipoAzioneLong,
        ShortAttuale, ShortNuovo, ShortEstesaAttuale, ShortEstesaNuova,
        LongAttuale, LongNuovo, LongEstesaAttuale, LongEstesaNuova,
        MotivoDifferenza, GETDATE()
    FROM #StagingDiff;

    DECLARE @TotRilevati INT = @@ROWCOUNT;
    DECLARE @Fine DATETIME = GETDATE();
    DECLARE @Secondi INT = DATEDIFF(SECOND, @Inizio, @Fine);

    PRINT '====================================================================================';
    PRINT 'SCANSIONE COMPLETATA con successo in ' + CAST(@Secondi AS VARCHAR(10)) + ' secondi.';
    PRINT 'Totale Articoli/Opzioni con Differenze Rilevate: ' + CAST(@TotRilevati AS VARCHAR(10));
    PRINT '====================================================================================';

    -- REPORT 1: RIEPILOGO PER TIPOLOGIA TD
    PRINT '';
    PRINT '--- RIEPILOGO ANOMALIE PER TIPOLOGIA ARTICOLO TD ---';
    SELECT 
        TipologiaTD,
        COUNT(*) AS TotaleDiscrepanze,
        SUM(CAST(DiffShort AS INT)) AS AnomalieShort,
        SUM(CAST(DiffLong AS INT)) AS AnomalieLong,
        SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END) AS MancantiLinguaLNG
    FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI WITH (NOLOCK)
    WHERE Ditta = @Ditta AND CodiceArticolo LIKE @FiltroArticolo
    GROUP BY TipologiaTD
    ORDER BY TotaleDiscrepanze DESC;

    -- REPORT 2: RIEPILOGO PER MOTIVO DIFFERENZA
    PRINT '';
    PRINT '--- RIEPILOGO ANOMALIE PER MOTIVO PRINCIPALE ---';
    SELECT 
        MotivoDifferenza,
        COUNT(*) AS ConteggioArticoli
    FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI WITH (NOLOCK)
    WHERE Ditta = @Ditta AND CodiceArticolo LIKE @FiltroArticolo
    GROUP BY MotivoDifferenza
    ORDER BY ConteggioArticoli DESC;

    -- REPORT 3: CAMPIONE DI 10 CASI SIGNIFICATIVI
    PRINT '';
    PRINT '--- CAMPIONAMENTO 10 CASI CON DIFFERENZE ---';
    SELECT TOP 10 
        CodiceArticolo,
        Opzione,
        MotivoDifferenza,
        ShortAttuale,
        ShortNuovo,
        LongAttuale,
        LongNuovo
    FROM dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI WITH (NOLOCK)
    WHERE Ditta = @Ditta AND CodiceArticolo LIKE @FiltroArticolo
    ORDER BY DiffShort DESC, DiffLong DESC;

    DROP TABLE #StagingDiff;
END;
GO

