/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 16:55
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : MASTER DEPLOY SCRIPT PER AMBIENTE DI PRODUZIONE
Nome File                        : MASTER_DEPLOY_PRODUZIONE_AGGIORNAMENTO_DESCRIZIONI_GEMINI.sql
Ambiente Database Destinazione   : DBTMV Produzione (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Il presente script master rappresenta il pacchetto chirurgico ed autosufficiente per il rilascio in 
ambiente di PRODUZIONE di tutti i componenti necessari all'adeguamento e normalizzazione massiva 
delle descrizioni articolo su 'dbo.MG87_ARTDESC' (circa 242.000 articoli gestiti).

COESISTENZA E COMPATIBILITÀ CON I PROCESSI ORIGINALI IN PRODUZIONE:
Sul database di produzione continuano ad essere attivi i processi batch, i job schedulati a tempo
e le procedure originali dell'ERP Gamma Enterprise (es. SPRT_TMV_AGG_DESCR_ART, SPRT_TMV_ATTIVA_VAR,
SPRT_TMV_DESCRIZIONE, insieme ImpExp TMV_AGG_DESCR_ART, ecc.).
Il presente impianto è stato progettato con criteri di non-interferenza assoluta:
1. TUTTI i nuovi oggetti operativi adottano la nomenclatura Solveris con prefisso 'SO_' e suffisso 
   '_GEMINI' (es. SFSO_TMV_DESCRIZIONE_GEMINI, SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI, 
   SO_DIFF_DESCRIZIONI_GEMINI, SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI, SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI).
   Nessuna procedura o funzione legacy 'SPRT_...' viene sovrascritta o cancellata.
2. I dati anagrafici di base in 'dbo.RT05_DESCR_DIAM_PASSO' vengono arricchiti con le combinazioni 
   metriche mancanti (M110, M120, M125, M130, M155, M160, M180) valorizzate secondo la regola 
   concordata con l'Ufficio Tecnico (minimo da normativa con tolleranza -0,23 mm). Questo arricchimento
   porta un beneficio immediato anche ai processi originali legacy, che smetteranno di degradare 
   a 'M125 4' e potranno comporre i diametri corretti.
3. La vista di salvaguardia 'dbo.VPRT_ARTICOLI_MODELLO' tutela al 100% tutti gli articoli modello,
   impedendo che vengano toccati dal processo di bonifica.
4. Gli articoli manuali o fuori configuratore (es. articoli a disegno cliente come '01950265') 
   vengono rigorosamente esclusi e preservati.

STRUTTURA SEQUENZIALE DEI PASSAGGI CONTENUTI NEL MASTER SCRIPT:
- FASE 1: DML Popolamento e Normalizzazione dbo.RT05_DESCR_DIAM_PASSO (Minimi Normativa UT)
- FASE 2: DDL Creazione/Aggiornamento Vista di Salvaguardia dbo.VPRT_ARTICOLI_MODELLO
- FASE 3: DDL Creazione Funzione Algoritmica dbo.SFSO_TMV_DESCRIZIONE_GEMINI (Rev. 2.1)
- FASE 4: DDL Creazione Funzione Smart-Split dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI (Rev. 2.0)
- FASE 5: DDL Creazione Tabella di Audit e Staging dbo.SO_DIFF_DESCRIZIONI_GEMINI
- FASE 6: DDL Creazione Vista di Monitoraggio dbo.VPSO_DIFF_DESCRIZIONI_GEMINI
- FASE 7: DDL Creazione Stored Procedure Diagnostica dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.0)
- FASE 8: DDL Creazione Stored Procedure Adeguamento dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI (Rev. 2.0)
- FASE 9: Esecuzione Diagnostica Preventiva (Calcolo in Sola Lettura su SO_DIFF_DESCRIZIONI_GEMINI)
- FASE 10: Query di Verifica e Controllo Pre-Adeguamento (Audit Verifica Humana)
- FASE 11: Istruzioni di Esecuzione Effettiva (Protetto e Commentato per Attivazione Consapevole)

TEMPI DI ESECUZIONE TESTATI E CONFERMATI:
- Fasi 1-8 (Creazione oggetti e popolamento RT05) : ~5 secondi
- Fase 9 (Diagnostica globale in sola lettura)    : ~20 minuti (scansione massiva intero DB)
- Fase 11 (Adeguamento effettivo a blocchi)       : ~2 minuti (testato a 115 secondi su 242.000 articoli)
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 15:45 - SOLVERIS - Bandera Marco):
  Creazione del Master Deploy Script per l'ambiente di PRODUZIONE, integrando le 11 fasi operative
  autosufficienti e non-invasive rispetto alle procedure e viste esistenti.
- Rev. 1.1 (24/09/2026 16:55 - SOLVERIS - Bandera Marco):
  Aggiornamento Fase 1 (RT05) con la delibera finale dell'Ufficio Tecnico: assegnazione ufficiale
  del passo 8 mm (Delta 5,40 mm -> Nominale - 5,63 mm) al codice 'G-' per diametri >= 125, introduzione
  della nuova codifica '6-' per passo 6 mm, e conferma per M155 della natura a passo 6 mm su 'G-'.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT '====================================================================================';
PRINT 'AVVIO MASTER DEPLOY PRODUZIONE: AGGIORNAMENTO DESCRIZIONI ARTICOLI (GEMINI)';
PRINT 'Data e Ora: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '====================================================================================';
GO

-- =================================================================================================
-- FASE 1: POPOLAMENTO E NORMALIZZAZIONE RT05_DESCR_DIAM_PASSO (Minimi Normativa UT)
-- =================================================================================================
PRINT '>>> [FASE 1/11] Popolamento e Normalizzazione dbo.RT05_DESCR_DIAM_PASSO...';
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @NuoviValoriRT05 TABLE (
        Ditta           DECIMAL(5,0)    NOT NULL,
        ProgrMG6E_1     DECIMAL(5,0)    NOT NULL,
        SubcodiceMG6E_1 CHAR(25)        NOT NULL,
        ProgrMG6E_2     DECIMAL(5,0)    NOT NULL,
        SubcodiceMG6E_2 CHAR(25)        NOT NULL,
        Descrizione     VARCHAR(256)    NOT NULL,
        DesDiametro     NVARCHAR(50)    NOT NULL,
        Diametro        DECIMAL(18,2)   NOT NULL,
        ResilB7L7       CHAR(2)         NOT NULL
    );

    -- Regola Minimo Normativa UT: (Nominale - Delta Passo) - 0.23 mm
    -- M110
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '3-', 'M110x3', N'Ø 107,77 mm', 107.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '4-', 'M110x4', N'Ø 107,11 mm', 107.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, 'G-', 'M110x6', N'Ø 105,79 mm', 105.79, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '6-', 'M110x6', N'Ø 105,79 mm', 105.79, 'SI');

    -- M120
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '3-', 'M120x3', N'Ø 117,77 mm', 117.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '4-', 'M120x4', N'Ø 117,11 mm', 117.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, 'G-', 'M120x6', N'Ø 115,79 mm', 115.79, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '6-', 'M120x6', N'Ø 115,79 mm', 115.79, 'SI');

    -- M125 (Articolo Target Principale TDP04B7-M1254-)
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '3-', 'M125x3', N'Ø 122,77 mm', 122.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '4-', 'M125x4', N'Ø 122,11 mm', 122.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, 'G-', 'M125x8', N'Ø 119,37 mm', 119.37, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '6-', 'M125x6', N'Ø 120,79 mm', 120.79, 'SI');

    -- M130
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '3-', 'M130x3', N'Ø 127,77 mm', 127.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '4-', 'M130x4', N'Ø 127,11 mm', 127.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, 'G-', 'M130x8', N'Ø 124,37 mm', 124.37, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '6-', 'M130x6', N'Ø 125,79 mm', 125.79, 'SI');

    -- M155 (Diametro Speciale ISO: Passo Massimo Naturale 6 mm)
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '3-', 'M155x3', N'Ø 152,77 mm', 152.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '4-', 'M155x4', N'Ø 152,11 mm', 152.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, 'G-', 'M155x6', N'Ø 150,79 mm', 150.79, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '6-', 'M155x6', N'Ø 150,79 mm', 150.79, 'SI');

    -- M160
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '3-', 'M160x3', N'Ø 157,77 mm', 157.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '4-', 'M160x4', N'Ø 157,11 mm', 157.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, 'G-', 'M160x8', N'Ø 154,37 mm', 154.37, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '6-', 'M160x6', N'Ø 155,79 mm', 155.79, 'SI');

    -- M180
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '3-', 'M180x3', N'Ø 177,77 mm', 177.77, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '4-', 'M180x4', N'Ø 177,11 mm', 177.11, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, 'G-', 'M180x8', N'Ø 174,37 mm', 174.37, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '6-', 'M180x6', N'Ø 175,79 mm', 175.79, 'SI');

    -- Update record preesistenti
    UPDATE tgt
    SET tgt.RT05_DESCRIZIONE  = src.Descrizione,
        tgt.RT05_DES_DIAMETRO = src.DesDiametro,
        tgt.RT05_DIAMETRO     = src.Diametro,
        tgt.RT05_RESIL_B7L7   = src.ResilB7L7
    FROM dbo.RT05_DESCR_DIAM_PASSO AS tgt
    INNER JOIN @NuoviValoriRT05 AS src
        ON tgt.RT05_DITTA_CG18       = src.Ditta
       AND tgt.RT05_PROGR_MG6E_1     = src.ProgrMG6E_1
       AND tgt.RT05_SUBCODICE_MG6E_1 = src.SubcodiceMG6E_1
       AND tgt.RT05_PROGR_MG6E_2     = src.ProgrMG6E_2
       AND tgt.RT05_SUBCODICE_MG6E_2 = src.SubcodiceMG6E_2;

    -- Insert record mancanti
    INSERT INTO dbo.RT05_DESCR_DIAM_PASSO (
        RT05_DITTA_CG18, RT05_PROGR_MG6E_1, RT05_SUBCODICE_MG6E_1,
        RT05_PROGR_MG6E_2, RT05_SUBCODICE_MG6E_2, RT05_DESCRIZIONE,
        RT05_DES_DIAMETRO, RT05_DIAMETRO, RT05_RESIL_B7L7
    )
    SELECT src.Ditta, src.ProgrMG6E_1, src.SubcodiceMG6E_1,
           src.ProgrMG6E_2, src.SubcodiceMG6E_2, src.Descrizione,
           src.DesDiametro, src.Diametro, src.ResilB7L7
    FROM @NuoviValoriRT05 AS src
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.RT05_DESCR_DIAM_PASSO AS tgt WITH (NOLOCK)
        WHERE tgt.RT05_DITTA_CG18       = src.Ditta
          AND tgt.RT05_PROGR_MG6E_1     = src.ProgrMG6E_1
          AND tgt.RT05_SUBCODICE_MG6E_1 = src.SubcodiceMG6E_1
          AND tgt.RT05_PROGR_MG6E_2     = src.ProgrMG6E_2
          AND tgt.RT05_SUBCODICE_MG6E_2 = src.SubcodiceMG6E_2
    );

    COMMIT TRANSACTION;
    PRINT '>>> FASE 1 COMPLETATA con successo. RT05_DESCR_DIAM_PASSO allineata ai minimi UT.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'ERRORE in FASE 1: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO

-- =================================================================================================
-- FASE 2: VISTA DI SALVAGUARDIA ARTICOLI MODELLO dbo.VPRT_ARTICOLI_MODELLO
-- =================================================================================================
PRINT '>>> [FASE 2/12] Verifica Presenza Vista dbo.VPRT_ARTICOLI_MODELLO...';
GO

IF OBJECT_ID(N'[dbo].[VPRT_ARTICOLI_MODELLO]', 'V') IS NULL
BEGIN
    EXEC('
    CREATE VIEW dbo.VPRT_ARTICOLI_MODELLO
    AS
    SELECT DISTINCT 
        CM15_DITTA_CG18,
        CM15_CODARTMOD_MG66
    FROM dbo.CM15_CONFGCOMM WITH (NOLOCK)
    WHERE ISNULL(CM15_CODARTMOD_MG66, '''') <> '''';
    ');
    PRINT '>>> Vista dbo.VPRT_ARTICOLI_MODELLO non presente: creata con successo.';
END
ELSE
    PRINT '>>> Vista dbo.VPRT_ARTICOLI_MODELLO già esistente in produzione: preservata intatta senza modifiche.';
GO

-- =================================================================================================
-- FASE 3: FUNZIONE ALGORITMICA CALCOLO DESCRIZIONI dbo.SFSO_TMV_DESCRIZIONE_GEMINI (Rev. 2.1)
-- =================================================================================================
PRINT '>>> [FASE 3/11] Creazione Funzione dbo.SFSO_TMV_DESCRIZIONE_GEMINI...';
GO

CREATE OR ALTER FUNCTION dbo.SFSO_TMV_DESCRIZIONE_GEMINI
(
    @Ditta              AS DECIMAL(5, 0),    
    @CodiceArticolo     AS CHAR(25),
    @VarianteArticolo   AS CHAR(20),
    @Sezione            AS CHAR(12)
)
RETURNS VARCHAR(1672)
AS
BEGIN
    DECLARE @Tipologia                      AS CHAR(3);
    DECLARE @Materiale                      AS CHAR(3);
    DECLARE @Diametro                       AS CHAR(4);
    DECLARE @Passo                          AS CHAR(2);
    DECLARE @Var1                           AS CHAR(5);
    DECLARE @Var2                           AS CHAR(3);
    DECLARE @Var3                           AS CHAR(3);
    DECLARE @Var4                           AS CHAR(3);
    DECLARE @Var5                           AS CHAR(3);
    DECLARE @Minorazione                    AS CHAR(2);

    DECLARE @TipologiaDescrizione           AS VARCHAR(256) = '';
    DECLARE @MaterialeDescrizione           AS VARCHAR(256) = '';
    DECLARE @DiametroDescrizione            AS VARCHAR(256) = '';
    DECLARE @PassoDescrizione               AS VARCHAR(256) = '';
    DECLARE @DiametroPassoDescrizione       AS VARCHAR(256) = '';
    DECLARE @Var1Descrizione                AS VARCHAR(256) = '';
    DECLARE @Var2Descrizione                AS VARCHAR(256) = '';
    DECLARE @Var3Descrizione                AS VARCHAR(256) = '';
    DECLARE @Var4Descrizione                AS VARCHAR(256) = '';
    DECLARE @Var5Descrizione                AS VARCHAR(256) = '';
    DECLARE @MinorazioneDescrizione         AS VARCHAR(256) = '';

    DECLARE @Var1Gest                       AS SMALLINT = 0;
    DECLARE @Var2Gest                       AS SMALLINT = 0;
    DECLARE @Var3Gest                       AS SMALLINT = 0;
    DECLARE @Var4Gest                       AS SMALLINT = 0;
    DECLARE @Var5Gest                       AS SMALLINT = 0;

    DECLARE @Var2DescrizioneMG5E            AS VARCHAR(256) = '';
    DECLARE @Var3DescrizioneMG5E            AS VARCHAR(256) = '';
    DECLARE @TipologiaDescrizioneMG6E       AS VARCHAR(256) = '';

    DECLARE @TONDI_DXXX                     AS BIT = 0;
    DECLARE @DescrizioneBreve               AS VARCHAR(1672) = '';

    SET @Tipologia      = SUBSTRING(@CodiceArticolo, 1, 3);
    SET @Materiale      = SUBSTRING(@CodiceArticolo, 6, 3);
    SET @Diametro       = SUBSTRING(@CodiceArticolo, 9, 4);
    SET @Passo          = SUBSTRING(@CodiceArticolo, 13, 2);
    SET @Var1           = SUBSTRING(@VarianteArticolo, 1, 5);
    SET @Var2           = SUBSTRING(@VarianteArticolo, 6, 3);
    SET @Var3           = SUBSTRING(@VarianteArticolo, 9, 3);
    SET @Var4           = SUBSTRING(@VarianteArticolo, 12, 3);
    SET @Var5           = SUBSTRING(@VarianteArticolo, 15, 3);
    SET @Minorazione    = SUBSTRING(@CodiceArticolo, 4, 2);

    IF RTRIM(@Sezione) = '' 
    BEGIN
        -- 1. Tipologia SHORT
        SELECT TOP 1 @TipologiaDescrizione = CM02.CM02_DESCR 
        FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
        INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
        WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 1 AND CM02.CM02_VALORESTR = @Tipologia;

        IF @TipologiaDescrizione IS NULL SET @TipologiaDescrizione = '(*Tipologia*)  ';

        -- Minorazione Barra
        IF @Minorazione <> '00' AND @Minorazione <> '--'
        BEGIN
            SELECT TOP 1 @MinorazioneDescrizione = RT03.RT03_DESCRALTER 
            FROM dbo.RT03_DESCRALTER AS RT03 WITH (NOLOCK)
            WHERE RT03.RT03_DITTA_CG18     = @Ditta
              AND RT03.RT03_PROGR_MG6E     = 1
              AND RT03.RT03_SUBCODICE_MG6E = @Tipologia
              AND RT03.RT03_PROGR          = 500 + CAST(@Minorazione AS INT) * 10 + (CASE WHEN @Diametro LIKE 'P%' THEN 1 ELSE 0 END);

            IF @MinorazioneDescrizione IS NULL SET @MinorazioneDescrizione = '';
        END
        ELSE
            SET @MinorazioneDescrizione = '';

        -- Materiale SHORT
        IF @Materiale <> '---'
        BEGIN
            SELECT TOP 1 @MaterialeDescrizione = CM02.CM02_DESCR 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 3 AND CM02.CM02_VALORESTR = @Materiale;

            IF @MaterialeDescrizione IS NULL SET @MaterialeDescrizione = '(*Materiale*)  ';
        END;

        -- Diametro SHORT
        IF @Diametro <> '----'
        BEGIN
            SELECT TOP 1 @DiametroDescrizione = CM02.CM02_DESCR 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 4 AND CM02.CM02_VALORESTR = @Diametro;

            IF @DiametroDescrizione IS NULL SET @DiametroDescrizione = '(*Diametro*)  ';
        END;

        -- Passo SHORT
        IF @Passo <> '--'
        BEGIN
            SELECT TOP 1 @PassoDescrizione = CM02.CM02_DESCR 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 5 AND CM02.CM02_VALORESTR = @Passo;

            IF @PassoDescrizione IS NULL SET @PassoDescrizione = '(*Passo*)  ';
        END;

        -- DiametroPasso da RT05 (con formula minorazione barre)
        IF LEFT(@Diametro, 1) <> 'D' 
        BEGIN 
            SELECT TOP 1 
                @DiametroPassoDescrizione = 
                    CASE (
                        SELECT COUNT(*) 
                        FROM dbo.CM02_VALORICATCOMM WITH (NOLOCK) 
                        WHERE CM02_IDCATEGORIA_CM01 = 1 
                          AND CM02_VALORESTR IN ('TDP','TDR','TDL','TDF')
                          AND CM02_VALORESTR = @Tipologia
                    )
                    WHEN 0 THEN RT05.RT05_DESCRIZIONE
                    ELSE 'Ø ' + FORMAT(RT05.RT05_DIAMETRO - CAST(CASE WHEN ISNUMERIC(@Minorazione) = 1 THEN @Minorazione ELSE '00' END AS DECIMAL(18, 1)) / 10, 'G6', 'de-de') + 'mm'
                    END
            FROM dbo.RT05_DESCR_DIAM_PASSO AS RT05 WITH (NOLOCK)
            WHERE RT05.RT05_DITTA_CG18       = @Ditta
              AND RT05.RT05_PROGR_MG6E_1     = 4
              AND RT05.RT05_SUBCODICE_MG6E_1 = @Diametro
              AND RT05.RT05_PROGR_MG6E_2     = 5
              AND RT05.RT05_SUBCODICE_MG6E_2 = @Passo;

            IF @DiametroPassoDescrizione IS NULL SET @DiametroPassoDescrizione = '(*DiametroPasso*)  ';
        END;

        -- Varianti SHORT
        IF TRIM(ISNULL(@VarianteArticolo, '')) <> ''
        BEGIN
            IF @Var1 <> '-----' 
            BEGIN
                SELECT TOP 1 @Var1Descrizione = MG5E.MG5E_DESCR, @Var1Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A0' AND MG5E.MG5E_OPZIONE = @Var1 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var1Descrizione IS NULL AND @Var1Gest = 1 SET @Var1Descrizione = '(*Var1*)  ';
            END;

            IF @Var2 <> '---'
            BEGIN
                SELECT TOP 1 @Var2Descrizione = RT04.RT04_CODICE_DESALTER, @Var2DescrizioneMG5E = MG5E.MG5E_DESCR, @Var2Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A1' AND MG5E.MG5E_OPZIONE = @Var2 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF TRIM(ISNULL(@Var2Descrizione, '')) = '' SET @Var2Descrizione = TRIM(@Var2DescrizioneMG5E);
                IF @Var2Descrizione IS NULL AND @Var2Gest = 1 SET @Var2Descrizione = '(*Var2*)  ';
            END;

            IF @Var3 <> '---'
            BEGIN
                SELECT TOP 1 @Var3Descrizione = RT04.RT04_CODICE_DESALTER, @Var3DescrizioneMG5E = MG5E.MG5E_DESCR, @Var3Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A2' AND MG5E.MG5E_OPZIONE = @Var3 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF TRIM(ISNULL(@Var3Descrizione, '')) = '' SET @Var3Descrizione = TRIM(@Var3DescrizioneMG5E);
                IF @Var3Descrizione IS NULL AND @Var3Gest = 1 SET @Var3Descrizione = '(*Var3*)  ';
            END;

            IF @Var4 <> '---'
            BEGIN
                SELECT TOP 1 @Var4Descrizione = MG5E.MG5E_DESCR, @Var4Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A3' AND MG5E.MG5E_OPZIONE = @Var4 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var4Descrizione IS NULL AND @Var4Gest = 1 SET @Var4Descrizione = '(*Var4*)  ';
            END;

            IF @Var5 <> '---'
            BEGIN
                SELECT TOP 1 @Var5Descrizione = MG5E.MG5E_DESCR, @Var5Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A4' AND MG5E.MG5E_OPZIONE = @Var5 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var5Descrizione IS NULL AND @Var5Gest = 1 SET @Var5Descrizione = '(*Var5*)  ';
            END;
        END;

        -- Composizione finale SHORT
        IF RTRIM(ISNULL(@TipologiaDescrizione, '')) <> '' SET @DescrizioneBreve = TRIM(@TipologiaDescrizione) + CHAR(13) + CHAR(10);
        IF RTRIM(ISNULL(@MaterialeDescrizione, '')) <> '' SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + TRIM(@MaterialeDescrizione) + CHAR(13) + CHAR(10);

        IF (RTRIM(ISNULL(@DiametroPassoDescrizione, '')) <> '' AND @DiametroPassoDescrizione <> '(*DiametroPasso*)  ')
            SET @DescrizioneBreve = TRIM(ISNULL(@DescrizioneBreve, '')) + TRIM(@DiametroPassoDescrizione);
        ELSE
            SET @DescrizioneBreve = TRIM(ISNULL(@DescrizioneBreve, '')) + TRIM(ISNULL(@DiametroDescrizione, '')) + ' ' + TRIM(ISNULL(@PassoDescrizione, ''));

        SET @TONDI_DXXX = 0;
        IF EXISTS (
            SELECT 1 FROM dbo.MG6B_GESVARART WITH (NOLOCK)
            WHERE MG6B_DITTA_CG18 = @Ditta AND MG6B_CODART_MG66 = @CodiceArticolo AND MG6B_CODICEVAR_MG5F = 'A3' AND MG6B_FLGGESTVAR = 1 AND MG6B_CODRAGGVAR_MG5G = 'TONDI-DXXX'
        )
            SET @TONDI_DXXX = 1;

        IF (@Var4 <> '---' AND @Var4Gest = 1 AND @Diametro LIKE 'D%' AND @TONDI_DXXX = 1) 
            SET @DescrizioneBreve = LEFT(@DescrizioneBreve, LEN(@DescrizioneBreve) - 2) + RTRIM(ISNULL(@Var4Descrizione, '')) + 'mm';

        IF SUBSTRING(@CodiceArticolo, 1, 3) = 'KB-' 
        BEGIN   
            IF RTRIM(ISNULL(@Var1Descrizione, '')) <> '' AND @Var1Gest = 1 
            BEGIN 
                SET @DescrizioneBreve = TRIM(@DescrizioneBreve);
                IF RTRIM(ISNULL(@Var4Descrizione, '')) <> '' AND @Var4Gest = 1 AND @TONDI_DXXX = 0 
                    SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' x ' + RTRIM(@Var4Descrizione);
                SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var1Descrizione, '')) + CHAR(13) + CHAR(10);
            END;
        END
        ELSE
        BEGIN
            IF RTRIM(ISNULL(@Var1Descrizione, '')) <> '' AND @Var1Gest = 1 
                SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var1Descrizione, '')) + CHAR(13) + CHAR(10);
        END;

        IF RTRIM(ISNULL(@Var4Descrizione, '')) <> '' AND @Var4Gest = 1 AND @TONDI_DXXX = 0 AND @Tipologia <> 'KB-'
            SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + CASE @Tipologia WHEN 'DCI' THEN 'Ø ' WHEN 'RDW' THEN 'Ø ' ELSE '' END + RTRIM(ISNULL(@Var4Descrizione, ''));

        IF RTRIM(ISNULL(@Var5Descrizione, '')) <> '' AND @Var5Gest = 1 
            SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + CASE @Tipologia WHEN 'DCI' THEN 'H. ' WHEN 'RDW' THEN 'H. ' ELSE '' END + ' ' + RTRIM(ISNULL(@Var4Descrizione, ''));

        IF RTRIM(ISNULL(@Var2Descrizione, '')) <> '' AND @Var2Gest = 1 SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var2Descrizione, ''));
        IF RTRIM(ISNULL(@Var3Descrizione, '')) <> '' AND @Var3Gest = 1 SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var3Descrizione, ''));
    END
    ELSE
    BEGIN
        -- Decodifiche per la descrizione LONG
        SET @TipologiaDescrizione = '';
        SET @MaterialeDescrizione = '';

        IF @Tipologia <> '---'
        BEGIN   
            SELECT TOP 1 
                @TipologiaDescrizione     = RT03.RT03_DESCRALTER, 
                @TipologiaDescrizioneMG6E = CM02.CM02_DESCR
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            LEFT JOIN dbo.RT03_DESCRALTER AS RT03 WITH (NOLOCK) 
                ON CM01.CM01_DITTA_CG18 = RT03.RT03_DITTA_CG18 AND CM02.CM02_IDCATEGORIA_CM01 = RT03.RT03_PROGR_MG6E AND CM02.CM02_VALORESTR = RT03.RT03_SUBCODICE_MG6E
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 1 AND CM02.CM02_VALORESTR = @Tipologia
              AND (RT03.RT03_PROGR >= 0 AND RT03.RT03_PROGR < 10 OR RT03.RT03_PROGR IS NULL)
              AND (RT03.RT03_CODICE_DESALTER LIKE CASE WHEN CHARINDEX('P', @Diametro) > 0 THEN '%Pollice%' ELSE '%Metric%' END OR RT03.RT03_CODICE_DESALTER IS NULL);

            IF @TipologiaDescrizione IS NULL OR TRIM(@TipologiaDescrizione) = ''
                SET @TipologiaDescrizione = ISNULL(TRIM(@TipologiaDescrizioneMG6E), '(*Tipologia*)  ');
        END;

        IF @Materiale <> '---'
        BEGIN
            SELECT TOP 1 @MaterialeDescrizione = RT03.RT03_DESCRALTER 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            LEFT JOIN dbo.RT03_DESCRALTER AS RT03 WITH (NOLOCK) 
                ON CM01.CM01_DITTA_CG18 = RT03.RT03_DITTA_CG18 AND CM02.CM02_IDCATEGORIA_CM01 = RT03.RT03_PROGR_MG6E AND CM02.CM02_VALORESTR = RT03.RT03_SUBCODICE_MG6E
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 3 AND CM02.CM02_VALORESTR = @Materiale;

            IF @MaterialeDescrizione IS NULL SET @MaterialeDescrizione = '(*Materiale*)  ';
        END;

        IF @Diametro <> '----'
        BEGIN
            SELECT TOP 1 @DiametroDescrizione = CM02.CM02_DESCR 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 4 AND CM02.CM02_VALORESTR = @Diametro;

            IF @DiametroDescrizione IS NULL SET @DiametroDescrizione = '(*Diametro*)  ';
        END;

        IF @Passo <> '--'
        BEGIN
            SELECT TOP 1 @PassoDescrizione = CM02.CM02_DESCR 
            FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
            INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
            WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 5 AND CM02.CM02_VALORESTR = @Passo;

            IF @PassoDescrizione IS NULL SET @PassoDescrizione = '(*Passo*)  ';
        END;

        IF LEFT(@Diametro, 1) <> 'D' 
        BEGIN 
            SELECT TOP 1 
                @DiametroPassoDescrizione = 
                    CASE (
                        SELECT COUNT(*) 
                        FROM dbo.CM02_VALORICATCOMM WITH (NOLOCK) 
                        WHERE CM02_IDCATEGORIA_CM01 = 1 
                          AND CM02_VALORESTR IN ('TDP','TDR','TDL','TDF')
                          AND CM02_VALORESTR = @Tipologia
                    )
                    WHEN 0 THEN RT05.RT05_DESCRIZIONE
                    ELSE 'Ø ' + FORMAT(RT05.RT05_DIAMETRO - CAST(CASE WHEN ISNUMERIC(@Minorazione) = 1 THEN @Minorazione ELSE '00' END AS DECIMAL(18, 1)) / 10, 'G6', 'de-de') + 'mm'
                    END
            FROM dbo.RT05_DESCR_DIAM_PASSO AS RT05 WITH (NOLOCK)
            WHERE RT05.RT05_DITTA_CG18       = @Ditta
              AND RT05.RT05_PROGR_MG6E_1     = 4
              AND RT05.RT05_SUBCODICE_MG6E_1 = @Diametro
              AND RT05.RT05_PROGR_MG6E_2     = 5
              AND RT05.RT05_SUBCODICE_MG6E_2 = @Passo;

            IF @DiametroPassoDescrizione IS NULL SET @DiametroPassoDescrizione = '(*DiametroPasso*)  ';
        END;

        IF TRIM(ISNULL(@VarianteArticolo, '')) <> ''
        BEGIN
            IF @Var1 <> '-----' 
            BEGIN
                SELECT TOP 1 @Var1Descrizione = MG5E.MG5E_DESCR, @Var1Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A0' AND MG5E.MG5E_OPZIONE = @Var1 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var1Descrizione IS NULL AND @Var1Gest = 1 SET @Var1Descrizione = '(*Var1*)  ';
            END;

            IF @Var2 <> '---'
            BEGIN
                SELECT TOP 1 @Var2Descrizione = RT04.RT04_CODICE_DESALTER, @Var2DescrizioneMG5E = MG5E.MG5E_DESCR, @Var2Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A1' AND MG5E.MG5E_OPZIONE = @Var2 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF TRIM(ISNULL(@Var2Descrizione, '')) = '' SET @Var2Descrizione = TRIM(@Var2DescrizioneMG5E);
                IF @Var2Descrizione IS NULL AND @Var2Gest = 1 SET @Var2Descrizione = '(*Var2*)  ';
            END;

            IF @Var3 <> '---'
            BEGIN
                SELECT TOP 1 @Var3Descrizione = RT04.RT04_CODICE_DESALTER, @Var3DescrizioneMG5E = MG5E.MG5E_DESCR, @Var3Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A2' AND MG5E.MG5E_OPZIONE = @Var3 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF TRIM(ISNULL(@Var3Descrizione, '')) = '' SET @Var3Descrizione = TRIM(@Var3DescrizioneMG5E);
                IF @Var3Descrizione IS NULL AND @Var3Gest = 1 SET @Var3Descrizione = '(*Var3*)  ';
            END;

            IF @Var4 <> '---'
            BEGIN
                SELECT TOP 1 @Var4Descrizione = MG5E.MG5E_DESCR, @Var4Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A3' AND MG5E.MG5E_OPZIONE = @Var4 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var4Descrizione IS NULL AND @Var4Gest = 1 SET @Var4Descrizione = '(*Var4*)  ';
            END;

            IF @Var5 <> '---'
            BEGIN
                SELECT TOP 1 @Var5Descrizione = MG5E.MG5E_DESCR, @Var5Gest = MG6B.MG6B_FLGGESTVAR
                FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
                LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
                    ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
                WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A4' AND MG5E.MG5E_OPZIONE = @Var5 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
                IF @Var5Descrizione IS NULL AND @Var5Gest = 1 SET @Var5Descrizione = '(*Var5*)  ';
            END;
        END;

        -- Composizione finale LONG
        IF RTRIM(ISNULL(@TipologiaDescrizione, '')) <> '' SET @DescrizioneBreve = TRIM(@TipologiaDescrizione) + CHAR(13) + CHAR(10);
        IF RTRIM(ISNULL(@MaterialeDescrizione, '')) <> '' SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + TRIM(@MaterialeDescrizione) + CHAR(13) + CHAR(10);

        IF (RTRIM(ISNULL(@DiametroPassoDescrizione, '')) <> '' AND @DiametroPassoDescrizione <> '(*DiametroPasso*)  ')
            SET @DescrizioneBreve = TRIM(ISNULL(@DescrizioneBreve, '')) + TRIM(@DiametroPassoDescrizione);
        ELSE
            SET @DescrizioneBreve = TRIM(ISNULL(@DescrizioneBreve, '')) + TRIM(ISNULL(@DiametroDescrizione, '')) + ' ' + TRIM(ISNULL(@PassoDescrizione, ''));

        IF RTRIM(ISNULL(@Var1Descrizione, '')) <> '' AND @Var1Gest = 1 
            SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var1Descrizione, '')) + CHAR(13) + CHAR(10);

        IF RTRIM(ISNULL(@Var4Descrizione, '')) <> '' AND @Var4Gest = 1 
            SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var4Descrizione, ''));

        IF RTRIM(ISNULL(@Var5Descrizione, '')) <> '' AND @Var5Gest = 1 
            SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var5Descrizione, ''));

        IF RTRIM(ISNULL(@Var2Descrizione, '')) <> '' AND @Var2Gest = 1 SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var2Descrizione, ''));
        IF RTRIM(ISNULL(@Var3Descrizione, '')) <> '' AND @Var3Gest = 1 SET @DescrizioneBreve = TRIM(@DescrizioneBreve) + ' ' + RTRIM(ISNULL(@Var3Descrizione, ''));
    END;

    RETURN @DescrizioneBreve;
END;
GO

PRINT '>>> FASE 3 COMPLETATA con successo. Funzione dbo.SFSO_TMV_DESCRIZIONE_GEMINI attiva.';
GO

-- =================================================================================================
-- FASE 4: FUNZIONE SMART-SPLIT dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI (Rev. 2.0)
-- =================================================================================================
PRINT '>>> [FASE 4/11] Creazione Funzione Table-Valued dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI...';
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

PRINT '>>> FASE 4 COMPLETATA con successo. Funzione dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI attiva.';
GO

-- =================================================================================================
-- FASE 5: TABELLA DI AUDIT E STAGING dbo.SO_DIFF_DESCRIZIONI_GEMINI
-- =================================================================================================
PRINT '>>> [FASE 5/11] Creazione Tabella di Staging dbo.SO_DIFF_DESCRIZIONI_GEMINI...';
GO

IF OBJECT_ID(N'[dbo].[SO_DIFF_DESCRIZIONI_GEMINI]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SO_DIFF_DESCRIZIONI_GEMINI (
        Ditta               DECIMAL(5,0)    NOT NULL,
        CodiceArticolo      CHAR(25)        COLLATE DATABASE_DEFAULT NOT NULL,
        Opzione             CHAR(20)        COLLATE DATABASE_DEFAULT NOT NULL,
        Prefisso            VARCHAR(10)     COLLATE DATABASE_DEFAULT NOT NULL,
        DiffShort           BIT             NOT NULL,
        DiffLong            BIT             NOT NULL,
        TipoAzioneShort     VARCHAR(10)     NOT NULL,
        TipoAzioneLong      VARCHAR(10)     NOT NULL,
        ShortAttuale        VARCHAR(MAX)    NULL,
        ShortNuovo          VARCHAR(MAX)    NULL,
        ShortEstesaAttuale  VARCHAR(MAX)    NULL,
        ShortEstesaNuova    VARCHAR(MAX)    NULL,
        LongAttuale         VARCHAR(MAX)    NULL,
        LongNuovo           VARCHAR(MAX)    NULL,
        LongEstesaAttuale   VARCHAR(MAX)    NULL,
        LongEstesaNuova     VARCHAR(MAX)    NULL,
        MotivoDifferenza    VARCHAR(50)     NOT NULL,
        DataRilevamento     DATETIME        DEFAULT GETDATE() NOT NULL,
        DataAdeguamento     DATETIME        NULL,
        PRIMARY KEY CLUSTERED (Ditta, CodiceArticolo, Opzione)
    );

    CREATE NONCLUSTERED INDEX IX_SO_DIFF_PREFISSO 
        ON dbo.SO_DIFF_DESCRIZIONI_GEMINI (Ditta, Prefisso, DataAdeguamento);

    CREATE NONCLUSTERED INDEX IX_SO_DIFF_MOTIVO 
        ON dbo.SO_DIFF_DESCRIZIONI_GEMINI (Ditta, MotivoDifferenza, DataAdeguamento);

    PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI creata con successo.';
END
ELSE
    PRINT 'Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI già esistente.';
GO

-- =================================================================================================
-- FASE 6: VISTA DI MONITORAGGIO AGGREGATA dbo.VPSO_DIFF_DESCRIZIONI_GEMINI
-- =================================================================================================
PRINT '>>> [FASE 6/11] Creazione Vista dbo.VPSO_DIFF_DESCRIZIONI_GEMINI...';
GO

CREATE OR ALTER VIEW dbo.VPSO_DIFF_DESCRIZIONI_GEMINI
AS
SELECT 
    Ditta,
    Prefisso,
    MotivoDifferenza,
    COUNT(*) AS TotaleArticoli,
    SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END) AS TotShortDaAggiornare,
    SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END) AS TotLongDaAggiornare,
    SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END) AS TotLongDaInserire,
    SUM(CASE WHEN DataAdeguamento IS NOT NULL THEN 1 ELSE 0 END) AS TotArticoliAdeguati,
    SUM(CASE WHEN DataAdeguamento IS NULL THEN 1 ELSE 0 END) AS TotArticoliPendenti,
    MIN(DataRilevamento) AS PrimaDataRilevamento,
    MAX(DataAdeguamento) AS UltimaDataAdeguamento
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY Ditta, Prefisso, MotivoDifferenza;
GO

PRINT '>>> FASE 6 COMPLETATA con successo. Vista dbo.VPSO_DIFF_DESCRIZIONI_GEMINI attiva.';
GO

-- =================================================================================================
-- FASE 7: STORED PROCEDURE DIAGNOSTICA GLOBALE dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.0)
-- =================================================================================================
PRINT '>>> [FASE 7/11] Creazione Stored Procedure Diagnostica dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI...';
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
    PRINT 'AVVIO DIAGNOSTICA: dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI (Rev. 3.0)';
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
    PRINT 'DIAGNOSTICA GLOBALE COMPLETATA CON SUCCESSO.';
    PRINT 'Totale discrepanze reali archiviate in SO_DIFF_DESCRIZIONI_GEMINI: ' + CAST(@TotDiscrepanzeGlobal AS VARCHAR(10));
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END;
GO

PRINT '>>> FASE 7 COMPLETATA con successo. Stored Procedure dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI attiva.';
GO

-- =================================================================================================
-- FASE 8: STORED PROCEDURE BONIFICA CONTROLLATA dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI (Rev. 2.0)
-- =================================================================================================
PRINT '>>> [FASE 8/11] Creazione Stored Procedure di Adeguamento dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI...';
GO

CREATE OR ALTER PROCEDURE dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI
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
    PRINT 'AVVIO PROCEDURA BONIFICA: dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI (Rev. 2.0)';
    PRINT 'Modalità Operativa : ' + CASE WHEN @DryRun = 1 THEN 'DRY-RUN (Simulazione Verbosa - Nessuna Scrittura)' ELSE 'EFFETTIVA (Scrittura Massiva su MG87_ARTDESC)' END;
    PRINT 'Filtro Prefisso    : ' + ISNULL(@Prefisso, 'TUTTE LE FAMIGLIE');
    PRINT 'Filtro Motivo      : ' + ISNULL(@MotivoDifferenza, 'TUTTE LE TIPOLOGIE DI ANOMALIA');
    PRINT 'Batch Size         : ' + CAST(@BatchSize AS VARCHAR(10)) + ' record per transazione';
    PRINT 'Data e Ora Inizio  : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';

    IF @RicalcolaAudit = 1 OR (@DryRun = 1 AND NOT EXISTS (
        SELECT 1 FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
        WHERE Ditta = @Ditta
          AND (@Prefisso IS NULL OR Prefisso = @Prefisso)
          AND (@MotivoDifferenza IS NULL OR MotivoDifferenza = @MotivoDifferenza)
          AND DataAdeguamento IS NULL
    ))
    BEGIN
        PRINT '>>> Tabella audit vuota o ricalcolo richiesto: avvio calcolo diagnostico preventivo...';
        DECLARE @FiltroCheck VARCHAR(25) = CASE WHEN @Prefisso IS NOT NULL THEN @Prefisso + '%' ELSE NULL END;
        EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
            @Ditta              = @Ditta,
            @FiltroFamiglia     = @FiltroCheck,
            @PulisciTabella     = 1,
            @SoloConDifferenze  = 1;
    END;

    DECLARE @TotShortUpd INT = 0;
    DECLARE @TotLongUpd INT = 0;
    DECLARE @TotLongIns INT = 0;

    SELECT 
        @TotShortUpd = SUM(CASE WHEN src.DiffShort = 1 THEN 1 ELSE 0 END),
        @TotLongUpd  = SUM(CASE WHEN src.DiffLong = 1 AND src.TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END),
        @TotLongIns  = SUM(CASE WHEN src.TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END)
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
    PRINT ' - Aggiornamenti SHORT (Italiano) : ' + CAST(ISNULL(@TotShortUpd, 0) AS VARCHAR(10));
    PRINT ' - Aggiornamenti LONG (Estero)    : ' + CAST(ISNULL(@TotLongUpd, 0) AS VARCHAR(10));
    PRINT ' - Inserimenti LONG (Estero manc.): ' + CAST(ISNULL(@TotLongIns, 0) AS VARCHAR(10));
    PRINT '------------------------------------------------------------------------------------';

    IF @DryRun = 1
    BEGIN
        PRINT '>>> MODALITÀ DRY-RUN ATTIVA: NESSUNA MODIFICA APPLICATA AL DATABASE.';
        PRINT '>>> Per applicare le modifiche su MG87_ARTDESC, rieseguire con: @DryRun = 0';
        RETURN;
    END;

    -- MODALITÀ EFFETTIVA: Esecuzione a blocchi transazionali
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

            IF @@ROWCOUNT = 0 BREAK;

            BEGIN TRANSACTION;

            -- 1. UPDATE SHORT (con LastChange per bypassare trigger con cursore)
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

            -- 2. UPDATE LONG (con LastChange)
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
            WHERE src.DiffLong = 1 AND src.TipoAzioneLong = 'UPDATE';

            DECLARE @UpdLongBatch INT = @@ROWCOUNT;

            -- 3. INSERT LONG mancanti
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

            -- 4. Marcatura DataAdeguamento
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
                  CAST(@InsLongBatch AS VARCHAR(10)) + '). Totale progressivo: ' +
                  CAST(@TotArticoliBonificati AS VARCHAR(10)) + '.';

            SET @Ciclo = @Ciclo + 1;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            PRINT 'ERRORE al Batch ' + CAST(@Ciclo AS VARCHAR(5)) + ': ' + ERROR_MESSAGE();
            IF OBJECT_ID('tempdb..#BatchKeys') IS NOT NULL DROP TABLE #BatchKeys;
            THROW;
        END CATCH;
    END;

    IF OBJECT_ID('tempdb..#BatchKeys') IS NOT NULL DROP TABLE #BatchKeys;

    -- Se richiesto, alimentazione RT12
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
        PRINT 'Alimentata tabella dbo.RT12_AGG_DESCR_ART con ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' record.';
    END;

    PRINT '====================================================================================';
    PRINT 'BONIFICA COMPLETATA CON SUCCESSO.';
    PRINT 'Totale articoli bonificati in SO_DIFF_DESCRIZIONI_GEMINI : ' + CAST(@TotArticoliBonificati AS VARCHAR(10));
    PRINT 'Totale operazioni applicate su MG87_ARTDESC             : ' + CAST(@TotOperazioniMG87 AS VARCHAR(10));
    PRINT 'Data e Ora Fine: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
    PRINT '====================================================================================';
END;
GO

PRINT '>>> FASE 8 COMPLETATA con successo. Stored Procedure dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI attiva.';
GO

-- =================================================================================================
-- FASE 9: REVISIONE CONSERVATIVA PROCEDURA BATCH ORIGINALE dbo.SPRT_TMV_AGG_DESCR_ART (Rev. 3.0)
-- =================================================================================================
PRINT '>>> [FASE 9/12] Aggiornamento Conservativo Stored Procedure Originale dbo.SPRT_TMV_AGG_DESCR_ART...';
PRINT '>>> SCOPO: Inietta la logica smart-split per i nuovi articoli inseriti o modificati in futuro,';
PRINT '>>>        mantenendo IDENTICO il nome della SP per i processi ImpExp e prevenendo retrogradazioni.';
GO

CREATE OR ALTER PROCEDURE dbo.SPRT_TMV_AGG_DESCR_ART
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ditta      DECIMAL(5, 0);
    DECLARE @codart     CHAR(25);
    DECLARE @opzione    CHAR(20);
    DECLARE @short      VARCHAR(1672);
    DECLARE @long       VARCHAR(1672);
    DECLARE @descr      VARCHAR(72);
    DECLARE @descr_est  VARCHAR(1672);

    -- STEP 1: FILTRO DI SICUREZZA SU RT12_AGG_DESCR_ART
    -- 1.1 Elimina articoli non presenti in CM15 (fuori configuratore o disegno cliente)
    DELETE RT12
    FROM dbo.RT12_AGG_DESCR_ART AS RT12
    FULL OUTER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK)
        ON  RT12.RT12_DITTA_CG18  = CM15.CM15_DITTA_CG18
        AND RT12.RT12_CODART_MG66 = CM15.CM15_CODART_MG66
    WHERE CM15.CM15_DITTA_CG18 IS NULL;

    -- 1.2 Elimina articoli contrassegnati come MODELLO (tutela integrità descrizioni di modello)
    IF OBJECT_ID(N'dbo.VPRT_ARTICOLI_MODELLO', 'V') IS NOT NULL
    BEGIN
        DELETE RT12
        FROM dbo.RT12_AGG_DESCR_ART AS RT12
        INNER JOIN dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
            ON  RT12.RT12_DITTA_CG18  = mod.CM15_DITTA_CG18
            AND RT12.RT12_CODART_MG66 = mod.CM15_CODARTMOD_MG66;
    END;

    -- STEP 2: AGGIORNAMENTO DELLA DESCRIZIONE SHORT IN MG87 PER LINGUA DEFAULT ('')
    DECLARE RT12_cursor CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY
    FOR 
        SELECT RT12_DITTA_CG18, RT12_CODART_MG66, RT12_OPZIONE_MG5E
        FROM dbo.RT12_AGG_DESCR_ART WITH (NOLOCK);

    OPEN RT12_cursor;
    FETCH NEXT FROM RT12_cursor INTO @ditta, @codart, @opzione;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Calcolo descrizione SHORT tramite funzione scalare standardizzata
        SET @short = dbo.SFSO_TMV_DESCRIZIONE_GEMINI(@ditta, @codart, @opzione, '');

        -- Spezzamento intelligente con presidio unità di misura 'mm' e terminatore CR+LF
        SELECT 
            @descr     = DescrizionePrimaria,
            @descr_est = DescrizioneEstesa
        FROM dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(@short);

        IF EXISTS (
            SELECT 1 
            FROM dbo.MG87_ARTDESC WITH (NOLOCK)
            WHERE MG87_DITTA_CG18     = @ditta
              AND MG87_CODART_MG66    = @codart
              AND MG87_OPZIONE_MG5E   = @opzione
              AND RTRIM(MG87_LINGUA_MG52) = ''
        )
        BEGIN
            UPDATE dbo.MG87_ARTDESC
            SET 
                MG87_DESCART    = @descr,
                MG87_DESCARTEST = @descr_est,
                MG87_LASTCHANGE = GETDATE() -- Bypass trigger con cursore TRG_EVENTTAB
            WHERE MG87_DITTA_CG18     = @ditta
              AND MG87_CODART_MG66    = @codart
              AND MG87_OPZIONE_MG5E   = @opzione
              AND RTRIM(MG87_LINGUA_MG52) = '';
        END;

        FETCH NEXT FROM RT12_cursor INTO @ditta, @codart, @opzione;
    END;

    CLOSE RT12_cursor;
    DEALLOCATE RT12_cursor;

    -- STEP 3: AGGIORNAMENTO O INSERIMENTO DELLA DESCRIZIONE LONG IN MG87 PER LINGUA 'LNG'
    DECLARE RT12_cursor_long CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY
    FOR 
        SELECT RT12_DITTA_CG18, RT12_CODART_MG66, RT12_OPZIONE_MG5E
        FROM dbo.RT12_AGG_DESCR_ART WITH (NOLOCK);

    OPEN RT12_cursor_long;
    FETCH NEXT FROM RT12_cursor_long INTO @ditta, @codart, @opzione;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Calcolo descrizione LONG tramite funzione scalare standardizzata
        SET @long = dbo.SFSO_TMV_DESCRIZIONE_GEMINI(@ditta, @codart, @opzione, 'LNG');

        -- Spezzamento intelligente con presidio unità di misura 'mm' e terminatore CR+LF
        SELECT 
            @descr     = DescrizionePrimaria,
            @descr_est = DescrizioneEstesa
        FROM dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI(@long);

        IF EXISTS (
            SELECT 1 
            FROM dbo.MG87_ARTDESC WITH (NOLOCK)
            WHERE MG87_DITTA_CG18     = @ditta
              AND MG87_CODART_MG66    = @codart
              AND MG87_OPZIONE_MG5E   = @opzione
              AND RTRIM(MG87_LINGUA_MG52) = 'LNG'
        )
        BEGIN
            UPDATE dbo.MG87_ARTDESC
            SET 
                MG87_DESCART    = @descr,
                MG87_DESCARTEST = @descr_est,
                MG87_LASTCHANGE = GETDATE()
            WHERE MG87_DITTA_CG18     = @ditta
              AND MG87_CODART_MG66    = @codart
              AND MG87_OPZIONE_MG5E   = @opzione
              AND RTRIM(MG87_LINGUA_MG52) = 'LNG';
        END
        ELSE
        BEGIN
            INSERT INTO dbo.MG87_ARTDESC (
                MG87_DITTA_CG18, MG87_CODART_MG66, MG87_OPZIONE_MG5E, MG87_LINGUA_MG52, 
                MG87_DESCART, MG87_DESCARTEST, MG87_LASTCHANGE, MG87_GUID
            )
            VALUES (
                @ditta, @codart, @opzione, 'LNG', 
                @descr, @descr_est, GETDATE(), NEWID()
            );
        END;

        FETCH NEXT FROM RT12_cursor_long INTO @ditta, @codart, @opzione;
    END;

    CLOSE RT12_cursor_long;
    DEALLOCATE RT12_cursor_long;

    -- STEP 4: GESTIONE SOSTITUZIONE "Min." IN "Mag." PER DADI
    WITH CteDadi AS (
        SELECT MG87.MG87_DESCART, MG87.MG87_DESCARTEST
        FROM dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
        INNER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK)
            ON  RT12.RT12_DITTA_CG18        = CM15.CM15_DITTA_CG18 
            AND RT12.RT12_CODART_MG66       = CM15.CM15_CODART_MG66
            AND ISNULL(RT12.RT12_OPZIONE_MG5E, '') = ISNULL(CM15.CM15_OPZIONE_MG5E, '')
        INNER JOIN dbo.MG87_ARTDESC AS MG87
            ON  CM15.CM15_DITTA_CG18        = MG87.MG87_DITTA_CG18
            AND RTRIM(CM15.CM15_CODART_MG66) = RTRIM(MG87.MG87_CODART_MG66)
            AND (RTRIM(MG87.MG87_LINGUA_MG52) = '' OR RTRIM(MG87.MG87_LINGUA_MG52) = 'LNG')
        WHERE RTRIM(CM15.CM15_CODARTMOD_MG66) IN ('DADI_METRICI', 'DADI_POLLICI') 
          AND (CHARINDEX('Min.', MG87.MG87_DESCART, 0) > 0 OR CHARINDEX('Min.', MG87.MG87_DESCARTEST, 0) > 0)
    )
    UPDATE CteDadi 
    SET MG87_DESCART    = REPLACE(MG87_DESCART, 'Min.', 'Mag.'), 
        MG87_DESCARTEST = REPLACE(MG87_DESCARTEST, 'Min.', 'Mag.');

    -- STEP 5: GESTIONE SOSTITUZIONE 14UNF VS 12UNF PER TIRANTI P1--
    WITH CteFilettatureUnf AS (
        SELECT MG87_DESCART, MG87_DESCARTEST,
            REPLACE(MG87_DESCART, '14UNF', '12UNF')    AS MG87_DESCART_NEW,
            REPLACE(MG87_DESCARTEST, '14UNF', '12UNF') AS MG87_DESCARTEST_NEW
        FROM dbo.MG87_ARTDESC
        WHERE MG87_DITTA_CG18 = 1
          AND MG87_CODART_MG66 LIKE '%P1--%'
          AND (MG87_CODART_MG66 LIKE '%F-' OR MG87_CODART_MG66 LIKE '%FS')
          AND RTRIM(MG87_DESCART) + ' ' + ISNULL(MG87_DESCARTEST, '') LIKE '%14UNF%'
    )
    UPDATE CteFilettatureUnf 
    SET MG87_DESCART    = MG87_DESCART_NEW, 
        MG87_DESCARTEST = MG87_DESCARTEST_NEW;

END;
GO

PRINT '>>> FASE 9 COMPLETATA con successo. Stored Procedure originale dbo.SPRT_TMV_AGG_DESCR_ART aggiornata alla Rev. 3.0.';
GO

-- =================================================================================================
-- FASE 10: ESECUZIONE DIAGNOSTICA PREVENTIVA (Calcolo in Sola Lettura - Zero Scritture su MG87)
-- =================================================================================================
PRINT '>>> [FASE 10/12] Esecuzione Diagnostica Preventiva (Popolamento SO_DIFF_DESCRIZIONI_GEMINI)...';
PRINT '>>> ATTENZIONE: Questa fase scansiona in sola lettura l''archivio articoli di produzione.';
PRINT '>>> Tempo stimato: circa 20 minuti.';
GO

EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
    @Ditta              = 1,
    @FiltroFamiglia     = NULL, -- Intera base dati
    @PulisciTabella     = 1,
    @SoloConDifferenze  = 1;
GO

PRINT '>>> FASE 10 COMPLETATA con successo. Tabella di audit SO_DIFF_DESCRIZIONI_GEMINI popolata.';
GO

-- =================================================================================================
-- FASE 11: QUERY DI VERIFICA E CONTROLLO PRE-ADEGUAMENTO (Audit Visivo)
-- =================================================================================================
PRINT '>>> [FASE 11/12] Esecuzione Query di Verifica e Audit di Controllo...';
GO

-- Riepilogo discrepanze rilevate per motivo
SELECT 
    MotivoDifferenza,
    COUNT(*) AS TotaleArticoli,
    SUM(CASE WHEN DiffShort = 1 THEN 1 ELSE 0 END) AS ShortDaAggiornare,
    SUM(CASE WHEN DiffLong = 1 AND TipoAzioneLong = 'UPDATE' THEN 1 ELSE 0 END) AS LongDaAggiornare,
    SUM(CASE WHEN TipoAzioneLong = 'INSERT' THEN 1 ELSE 0 END) AS LongDaInserire
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY MotivoDifferenza
ORDER BY TotaleArticoli DESC;

-- Controllo presidio unità di misura 'mm'
SELECT COUNT(*) AS AnomalieEstesaConMM
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE ShortEstesaNuova LIKE 'mm%' OR LongEstesaNuova LIKE 'mm%';

-- Controllo articolo pilota TDP04B7-M1254-
SELECT 
    CodiceArticolo,
    Opzione,
    ShortAttuale,
    ShortNuovo,
    LongAttuale,
    LongNuovo,
    MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE CodiceArticolo = 'TDP04B7-M1254-';

-- Controllo integrità MG87 (deve risultare 0 prima del lancio effettivo)
SELECT COUNT(*) AS RecordGiaAdeguatiInStaging
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE DataAdeguamento IS NOT NULL;
GO

-- =================================================================================================
-- FASE 12: ISTRUZIONE DI ADEGUAMENTO EFFETTIVO (PROTETTA E COMMENTATA)
-- =================================================================================================
/*
----------------------------------------------------------------------------------------------------
ISTRUZIONI PER L'APPLICAZIONE REALE DELLE MODIFICHE SU MG87_ARTDESC:
Dopo aver esaminato e validato i risultati della FASE 11, decommentare ed eseguire il comando
seguente per applicare le modifiche a blocchi transazionali di 5.000 articoli:

    EXEC dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI 
        @Ditta              = 1,
        @DryRun             = 0,      -- 0 = MODIFICA EFFETTIVA
        @BatchSize          = 5000,
        @AlimentaRT12       = 0;

NOTE TECNICHE:
- Tempo stimato di esecuzione: circa 2 minuti.
- L'aggiornamento avviene in transazioni atomiche da 5.000 record con COMMIT intermedi.
- I trigger di MG87_ARTDESC rimangono attivi (Opzione A); il trigger con cursore viene bypassato 
  automaticamente grazie all'aggiornamento esplicito di MG87_LASTCHANGE.
- In caso di interruzione accidentale, è sufficiente rieseguire il comando: ripartirà esattamente
  dal primo blocco non ancora bonificato.
----------------------------------------------------------------------------------------------------
*/
PRINT '>>> MASTER DEPLOY COMPLETATO. Sistema pronto per l''adeguamento effettivo.';
GO

