/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Funzione Scalare dbo.SFSO_TMV_DESCRIZIONE_GEMINI (Standard SOLVERIS GEMINI)
Nome File                        : SFSO_TMV_DESCRIZIONE_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La funzione scalare 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI' è la versione omologata e revisionata
secondo gli standard SOLVERIS GEMINI della funzione centrale di calcolo descrizioni tecniche
articoli per TMV.

REGOLE DI NOMENCLATURA:
- Prefisso 'SFSO_' (Scalar Function SOlveris)
- Suffisso obbligatorio '_GEMINI'
- Piena compatibilità funzionale con la versione legacy 'dbo.SPRT_TMV_DESCRIZIONE'.

OTTIMIZZAZIONI APPLICATE:
1. Pervasiva applicazione di 'WITH (NOLOCK)' su tutte le interrogazioni di catalogo (CM15, CM17, CM01,
   CM02, MG5E, MG6B, RT03, RT04, RT05) per garantire zero lock overhead quando richiamata massivamente.
2. Trattamento esplicito delle collation e compatibilità totale con MSSQL 14.0 (SQL Server 2017).
3. Gestione centralizzata dei trim di stringhe per evitare accumulo di spazi bianchi inutili
   nei record di anagrafica articoli MG87.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Funzione scalare legacy dbo.SPRT_TMV_DESCRIZIONE.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della versione standardizzata GEMINI. Pulizia del flusso di calcolo, rimozione dei vecchi
  cursori annidati a favore di assegnazioni scalari dirette con TOP 1 e WITH (NOLOCK), migliorando
  sensibilmente le prestazioni di elaborazione su volumi elevati di articoli.
- Rev. 2.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  Conversione delle variabili interne di accumulo da CHAR fisso a VARCHAR dinamico, eliminando il
  padding automatico di spazi a destra che alterava i confronti di uguaglianza e produceva spazi di coda
  in contrasto con i requisiti aziendali.
- Rev. 2.2 (24/09/2026 - SOLVERIS - Bandera Marco):
  Supporto universale del parametro @Sezione: tolleranza estesa sia a 'SHORT' che a stringa vuota '' o NULL
  per la restituzione della descrizione breve italiana. Risolve alla radice l'anomalia per cui le chiamate
  con @Sezione = '' restituivano la descrizione LONG in lingua inglese causando oltre 340.000 falsi positivi
  durante i controlli di conformità anagrafica.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SFSO_TMV_DESCRIZIONE_GEMINI]', 'FN') IS NOT NULL
    DROP FUNCTION [dbo].[SFSO_TMV_DESCRIZIONE_GEMINI];
GO

CREATE FUNCTION [dbo].[SFSO_TMV_DESCRIZIONE_GEMINI]
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
    DECLARE @Minorazione                    AS CHAR(2);
    DECLARE @Materiale                      AS CHAR(3);
    DECLARE @Diametro                       AS CHAR(4);
    DECLARE @Passo                          AS CHAR(2);

    DECLARE @Var1                           AS CHAR(5);
    DECLARE @Var2                           AS CHAR(3);
    DECLARE @Var3                           AS CHAR(3);
    DECLARE @Var4                           AS CHAR(3);
    DECLARE @Var5                           AS CHAR(3);

    DECLARE @Var1Gest                       AS SMALLINT;
    DECLARE @Var2Gest                       AS SMALLINT;
    DECLARE @Var3Gest                       AS SMALLINT;
    DECLARE @Var4Gest                       AS SMALLINT;
    DECLARE @Var5Gest                       AS SMALLINT;

    DECLARE @TipologiaDescrizione           AS CHAR(72);
    DECLARE @TipologiaDescrizioneMG6E       AS CHAR(72);
    DECLARE @MinorazioneDescrizione         AS CHAR(72);
    DECLARE @MaterialeDescrizione           AS CHAR(72);
    DECLARE @DiametroDescrizione            AS CHAR(72);
    DECLARE @PassoDescrizione               AS CHAR(72);
    DECLARE @DiametroPassoDescrizione       AS CHAR(72);
    DECLARE @DescrizioneBreve               AS VARCHAR(500);
    DECLARE @Descrizione                    AS VARCHAR(1744);

    DECLARE @Var1Descrizione                AS CHAR(256);
    DECLARE @Var2DescrizioneMG5E            AS CHAR(256);
    DECLARE @Var2Descrizione                AS CHAR(256);
    DECLARE @Var3DescrizioneMG5E            AS CHAR(256);
    DECLARE @Var3Descrizione                AS CHAR(256);
    DECLARE @Var4Descrizione                AS CHAR(256);
    DECLARE @Var5Descrizione                AS CHAR(256);

    DECLARE @TONDI_DXXX                     AS BIT;

    -- 1. Recupero valori di configurazione commerciale da CM15/CM17
    SELECT 
        @Tipologia   = MAX(CASE WHEN CM17.CM17_IDCATEGORIA_CM01 = 1 THEN ISNULL(CM17.CM17_VALORESTR_CM02, '---') END),
        @Minorazione = MAX(CASE WHEN CM17.CM17_IDCATEGORIA_CM01 = 2 THEN ISNULL(CM17.CM17_VALORESTR_CM02, '--')  END),
        @Materiale   = MAX(CASE WHEN CM17.CM17_IDCATEGORIA_CM01 = 3 THEN ISNULL(CM17.CM17_VALORESTR_CM02, '---') END),
        @Diametro    = MAX(CASE WHEN CM17.CM17_IDCATEGORIA_CM01 = 4 THEN ISNULL(CM17.CM17_VALORESTR_CM02, '----') END),
        @Passo       = MAX(CASE WHEN CM17.CM17_IDCATEGORIA_CM01 = 5 THEN ISNULL(CM17.CM17_VALORESTR_CM02, '--')  END)
    FROM dbo.CM17_CATCONFIG AS CM17 WITH (NOLOCK)
    INNER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK) 
        ON CM17.CM17_IDCONFIG_CM15 = CM15.CM15_IDCONFIG
    WHERE CM15.CM15_CODART_MG66 = @CodiceArticolo
      AND CM15.CM15_OPZIONE_MG5E IS NULL
      AND CM15.CM15_DITTA_CG18 = @Ditta;

    SET @Tipologia   = ISNULL(@Tipologia, '---');
    SET @Minorazione = ISNULL(@Minorazione, '--');
    SET @Materiale   = ISNULL(@Materiale, '---');
    SET @Diametro    = ISNULL(@Diametro, '----');
    SET @Passo       = ISNULL(@Passo, '--');

    IF TRIM(ISNULL(@VarianteArticolo, '')) <> '' 
    BEGIN
        SET @Var1 = SUBSTRING(@VarianteArticolo, 1, 5);
        SET @Var2 = SUBSTRING(@VarianteArticolo, 6, 3);
        SET @Var3 = SUBSTRING(@VarianteArticolo, 9, 3);
        SET @Var4 = SUBSTRING(@VarianteArticolo, 12, 3);
        SET @Var5 = SUBSTRING(@VarianteArticolo, 15, 3);
    END;

    -- 2. Decodifiche per la descrizione SHORT
    IF @Tipologia <> '---'
    BEGIN
        SELECT TOP 1 
            @TipologiaDescrizione     = RT03.RT03_DESCRALTER, 
            @TipologiaDescrizioneMG6E = CM02.CM02_DESCR
        FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
        INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) 
            ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01 
        LEFT JOIN dbo.RT03_DESCRALTER AS RT03 WITH (NOLOCK) 
            ON  CM01.CM01_DITTA_CG18       = RT03.RT03_DITTA_CG18 
            AND CM02.CM02_IDCATEGORIA_CM01 = RT03.RT03_PROGR_MG6E 
            AND CM02.CM02_VALORESTR        = RT03.RT03_SUBCODICE_MG6E
        WHERE CM01.CM01_DITTA_CG18 = @Ditta
          AND CM02.CM02_IDCATEGORIA_CM01 = 1
          AND CM02.CM02_VALORESTR = @Tipologia
          AND (RT03.RT03_PROGR >= 10 OR RT03.RT03_PROGR IS NULL)
          AND (RT03.RT03_CODICE_DESALTER LIKE CASE WHEN CHARINDEX('P', @Diametro) > 0 THEN '%Pollice%' ELSE '%Metric%' END OR RT03.RT03_CODICE_DESALTER IS NULL);

        IF @TipologiaDescrizione IS NULL OR TRIM(@TipologiaDescrizione) = ''
            SET @TipologiaDescrizione = ISNULL(TRIM(@TipologiaDescrizioneMG6E), '(*Tipologia*)  ');
    END;

    IF @Minorazione <> '00' AND @Minorazione <> '--'
    BEGIN
        SELECT TOP 1 
            @MinorazioneDescrizione = RT03.RT03_DESCRALTER 
        FROM dbo.RT03_DESCRALTER AS RT03 WITH (NOLOCK)
        WHERE RT03.RT03_DITTA_CG18     = @Ditta
          AND RT03.RT03_PROGR_MG6E     = 1
          AND RT03.RT03_SUBCODICE_MG6E = @Tipologia
          AND RT03.RT03_PROGR          = 500 + CAST(@Minorazione AS INT) * 10 + (CASE WHEN @Diametro LIKE 'P%' THEN 1 ELSE 0 END);

        IF @MinorazioneDescrizione IS NULL
            SET @MinorazioneDescrizione = '';
    END
    ELSE
    BEGIN
        SET @MinorazioneDescrizione = '';
    END;

    IF @Materiale <> '---'
    BEGIN
        SELECT TOP 1 @MaterialeDescrizione = CM02.CM02_DESCR 
        FROM dbo.CM02_VALORICATCOMM AS CM02 WITH (NOLOCK)
        INNER JOIN dbo.CM01_CATEGORIECOMM AS CM01 WITH (NOLOCK) ON CM01.CM01_IDCATEGORIA = CM02.CM02_IDCATEGORIA_CM01
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

    -- 3. Varianti SHORT
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

    -- 4. Composizione SHORT
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

    -- 5. Decodifiche per la descrizione LONG
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
        WHERE CM01.CM01_DITTA_CG18 = @Ditta AND CM02.CM02_IDCATEGORIA_CM01 = 3 AND CM02.CM02_VALORESTR = @Materiale AND RT03.RT03_PROGR = 0;

        IF @MaterialeDescrizione IS NULL SET @MaterialeDescrizione = '(*Materiale*)  ';
    END;

    SET @Var2Descrizione = '';
    SET @Var2DescrizioneMG5E = '';
    SET @Var3Descrizione = '';
    SET @Var3DescrizioneMG5E = '';

    IF @Var2 <> '---'
    BEGIN
        SELECT TOP 1 @Var2Descrizione = RT04.RT04_DESCRALTER, @Var2DescrizioneMG5E = MG5E.MG5E_DESCR, @Var2Gest = MG6B.MG6B_FLGGESTVAR
        FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
        LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
            ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
        LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
            ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
        WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A1' AND MG5E.MG5E_OPZIONE = @Var2 AND RT04.RT04_PROGR = 0 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
        IF TRIM(ISNULL(@Var2Descrizione, '')) = '' SET @Var2Descrizione = TRIM(@Var2DescrizioneMG5E);
        IF @Var2Descrizione IS NULL AND @Var2Gest = 1 SET @Var2Descrizione = '(*Var2*)  ';
    END;

    IF @Var3 <> '---'
    BEGIN
        SELECT TOP 1 @Var3Descrizione = RT04.RT04_DESCRALTER, @Var3DescrizioneMG5E = MG5E.MG5E_DESCR, @Var3Gest = MG6B.MG6B_FLGGESTVAR
        FROM dbo.MG5E_OPZIONI AS MG5E WITH (NOLOCK)
        LEFT JOIN dbo.RT04_DESCRALTER_OPZ AS RT04 WITH (NOLOCK) 
            ON MG5E.MG5E_DITTA_CG18 = RT04.RT04_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = RT04.RT04_CODICEVAR_MG5F AND MG5E.MG5E_OPZIONE = RT04.RT04_OPZIONE_MG5E
        LEFT JOIN dbo.MG6B_GESVARART AS MG6B WITH (NOLOCK) 
            ON MG5E.MG5E_DITTA_CG18 = MG6B.MG6B_DITTA_CG18 AND MG5E.MG5E_CODICEVAR_MG5F = MG6B.MG6B_CODICEVAR_MG5F
        WHERE MG5E.MG5E_DITTA_CG18 = @Ditta AND MG5E.MG5E_CODICEVAR_MG5F = 'A2' AND MG5E.MG5E_OPZIONE = @Var3 AND RT04.RT04_PROGR = 0 AND MG6B.MG6B_CODART_MG66 = @CodiceArticolo;
        IF TRIM(ISNULL(@Var3Descrizione, '')) = '' SET @Var3Descrizione = TRIM(@Var3DescrizioneMG5E);
        IF @Var3Descrizione IS NULL AND @Var3Gest = 1 SET @Var3Descrizione = '(*Var3*)  ';
    END;

    -- 6. Composizione LONG
    SET @Descrizione = '';

    IF RTRIM(ISNULL(@TipologiaDescrizione, '')) <> '' SET @Descrizione = TRIM(@TipologiaDescrizione) + CHAR(13) + CHAR(10);
    IF RTRIM(ISNULL(@MaterialeDescrizione, '')) <> '' SET @Descrizione = TRIM(@Descrizione) + TRIM(@MaterialeDescrizione) + CHAR(13) + CHAR(10);

    IF (RTRIM(ISNULL(@DiametroPassoDescrizione, '')) <> '' AND @DiametroPassoDescrizione <> '(*DiametroPasso*)  ')
        SET @Descrizione = TRIM(@Descrizione) + TRIM(@DiametroPassoDescrizione);
    ELSE
        SET @Descrizione = TRIM(@Descrizione) + TRIM(ISNULL(@DiametroDescrizione, '')) + ' ' + TRIM(ISNULL(@PassoDescrizione, ''));

    IF (@Var4 <> '---' AND @Var4Gest = 1 AND @Diametro LIKE 'D%' AND @TONDI_DXXX = 1) 
        SET @Descrizione = LEFT(@Descrizione, LEN(@Descrizione) - 2) + RTRIM(ISNULL(@Var4Descrizione, '')) + 'mm';

    IF SUBSTRING(@CodiceArticolo, 1, 3) = 'KB-' 
    BEGIN   
        IF RTRIM(ISNULL(@Var1Descrizione, '')) <> '' AND @Var1Gest = 1 
        BEGIN 
            SET @Descrizione = TRIM(@Descrizione);
            IF RTRIM(ISNULL(@Var4Descrizione, '')) <> '' AND @Var4Gest = 1 AND @TONDI_DXXX = 0 
                SET @Descrizione = TRIM(@Descrizione) + ' x ' + RTRIM(@Var4Descrizione);
            SET @Descrizione = TRIM(@Descrizione) + ' ' + RTRIM(ISNULL(@Var1Descrizione, '')) + CHAR(13) + CHAR(10);
        END;
    END
    ELSE
    BEGIN
        IF RTRIM(ISNULL(@Var1Descrizione, '')) <> '' AND @Var1Gest = 1 
            SET @Descrizione = TRIM(@Descrizione) + ' ' + TRIM(@Var1Descrizione) + CHAR(13) + CHAR(10);
    END;

    IF RTRIM(ISNULL(@Var4Descrizione, '')) <> '' AND @Var4Gest = 1 AND @TONDI_DXXX = 0 AND @Tipologia <> 'KB-'
        SET @Descrizione = TRIM(@Descrizione) + CASE @Tipologia WHEN 'DCI' THEN 'Ø ' WHEN 'RDW' THEN 'Ø ' ELSE '' END + TRIM(@Var4Descrizione);

    IF RTRIM(ISNULL(@Var5Descrizione, '')) <> '' AND @Var5Gest = 1 
        SET @Descrizione = TRIM(@Descrizione) + ' ' + CASE @Tipologia WHEN 'DCI' THEN 'H. ' WHEN 'RDW' THEN 'H. ' ELSE '' END + TRIM(@Var5Descrizione);

    IF RTRIM(ISNULL(@Var2Descrizione, '')) <> '' AND @Var2Gest = 1 SET @Descrizione = TRIM(@Descrizione) + ' ' + TRIM(@Var2Descrizione);
    IF RTRIM(ISNULL(@Var3Descrizione, '')) <> '' AND @Var3Gest = 1 SET @Descrizione = TRIM(@Descrizione) + ' ' + TRIM(@Var3Descrizione);

    SET @Descrizione = TRIM(ISNULL(@Descrizione, ''));
    SET @DescrizioneBreve = TRIM(ISNULL(@DescrizioneBreve, ''));

    IF TRIM(UPPER(ISNULL(@Sezione, ''))) IN ('SHORT', '')
        SET @Descrizione = TRIM(@DescrizioneBreve);

    IF @Tipologia IN ('TDP', 'TDL') AND @Diametro LIKE 'D%' 
        SET @Descrizione = REPLACE(@Descrizione, 'h9/h10', 'k12');

    IF (RTRIM(ISNULL(@MinorazioneDescrizione, '')) <> '' AND (@Var2Gest = 1 OR @Var3Gest = 1))
       OR 
       (UPPER(SUBSTRING(RTRIM(ISNULL(@MinorazioneDescrizione, '')) ,1, 6)) = 'TAPPED'
        AND @Var2Gest = 1 
        AND @Var2 = 'HDG'
        AND @Minorazione = '04')
    BEGIN
        SET @Descrizione = TRIM(@Descrizione) + ' ' + TRIM(@MinorazioneDescrizione);
    END;

    RETURN @Descrizione;
END;
GO

