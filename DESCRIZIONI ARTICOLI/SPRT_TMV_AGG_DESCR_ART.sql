/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 15:55
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPRT_TMV_AGG_DESCR_ART (Revisione Conservativa Produzione)
Nome File                        : SPRT_TMV_AGG_DESCR_ART.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPRT_TMV_AGG_DESCR_ART' costituisce il componente batch originale invocato
dal sottosistema ImpExp di Gamma Enterprise (tracciato 2 'TMV_AGG_DESART2' dell'insieme 'TMV_AGG_DESCR_ART')
per l'aggiornamento automatico delle descrizioni tecniche per gli articoli inseriti o modificati in RT12.

MOTIVAZIONE DELLA REVISIONE 3.0 (PREVENZIONE RETROGRADAZIONE IN PRODUZIONE):
Come evidenziato dall'analisi tecnica, l'esecuzione di una bonifica massiva dello storico su MG87_ARTDESC
risulterebbe vanificata nel tempo se i processi schedulati esistenti continuassero a richiamare la vecchia
versione di questa procedura. La versione precedente infatti:
1. Adottava un algoritmo di spezzamento statico al 73° carattere che troncava le unità di misura ('mm')
   trasferendole isolate all'inizio della descrizione estesa (anomalia riscontrata su 8.294 articoli).
2. Non apponeva il terminatore di riga standard CR+LF e lasciava spazi di coda non conformi.
3. Mancava dell'aggiornamento esplicito del timestamp MG87_LASTCHANGE, innescando il trigger con cursore
   riga-per-riga 'TRG_EVENTTAB_MG87_MG66_UPD' con pesante degrado delle prestazioni.
4. Non escludeva esplicitamente gli articoli modello censiti in VPRT_ARTICOLI_MODELLO.

MIGLIORIE INIETTATE NELLA REV. 3.0 (COMPATIBILITÀ TOTALE SENZA MODIFICHE DI FIRMA):
- Nome della procedura invariato: nessun impatto sui tracciati ImpExp o sui job SQL Server esistenti.
- Calcolo descrizioni tramite la funzione scalare dinamica 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI'.
- Formattazione tramite funzione smart-split 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' (presidio 'mm', 
  terminatore CR+LF garantito, zero spazi di coda residui).
- Tutela automatica degli articoli modello (eliminazione da RT12 degli articoli presenti in VPRT_ARTICOLI_MODELLO).
- Aggiornamento esplicito di MG87_LASTCHANGE = GETDATE(), con disinnesco del trigger con cursore.
- Preservazione integrale delle regole storiche DADI ("Min." -> "Mag.") e UNF (14UNF -> 12UNF).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (13/12/2021 - Coria Francesco): Creazione iniziale procedura batch Gamma.
- Rev. 1.1 (14/09/2022 - Bandera Marco): Correzione dicitura Dadi ("Min." in "Mag.").
- Rev. 1.2 (04/02/2025 - Bandera Marco): Correzione passo tiranti P1-- (14UNF in 12UNF).
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco): Adozione standard narrativo SOLVERIS.
- Rev. 3.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Iniezione della logica smart-split protetta per unità di misura ('mm'), terminatore CR+LF,
  tutela preventiva articoli modello e disinnesco trigger cursori tramite timestamp LASTCHANGE.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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

    -- =============================================================================================
    -- STEP 1: FILTRO DI SICUREZZA SU RT12_AGG_DESCR_ART
    -- =============================================================================================
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

    -- =============================================================================================
    -- STEP 2: AGGIORNAMENTO DELLA DESCRIZIONE SHORT IN MG87 PER LINGUA DEFAULT ('')
    -- =============================================================================================
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

    -- =============================================================================================
    -- STEP 3: AGGIORNAMENTO O INSERIMENTO DELLA DESCRIZIONE LONG IN MG87 PER LINGUA 'LNG'
    -- =============================================================================================
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
                MG87_DITTA_CG18, 
                MG87_CODART_MG66, 
                MG87_OPZIONE_MG5E, 
                MG87_LINGUA_MG52, 
                MG87_DESCART, 
                MG87_DESCARTEST,
                MG87_LASTCHANGE,
                MG87_GUID
            )
            VALUES (
                @ditta, 
                @codart, 
                @opzione, 
                'LNG', 
                @descr, 
                @descr_est,
                GETDATE(),
                NEWID()
            );
        END;

        FETCH NEXT FROM RT12_cursor_long INTO @ditta, @codart, @opzione;
    END;

    CLOSE RT12_cursor_long;
    DEALLOCATE RT12_cursor_long;

    -- =============================================================================================
    -- STEP 4: GESTIONE SOSTITUZIONE "Min." IN "Mag." PER DADI (Rev. 14/09/2022 - Bandera)
    -- =============================================================================================
    WITH CteDadi AS (
        SELECT 
            MG87.MG87_DESCART,
            MG87.MG87_DESCARTEST
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
    SET 
        MG87_DESCART    = REPLACE(MG87_DESCART, 'Min.', 'Mag.'), 
        MG87_DESCARTEST = REPLACE(MG87_DESCARTEST, 'Min.', 'Mag.');

    -- =============================================================================================
    -- STEP 5: GESTIONE SOSTITUZIONE 14UNF VS 12UNF PER TIRANTI P1-- (Rev. 04/02/2025 - Bandera)
    -- =============================================================================================
    WITH CteFilettatureUnf AS (
        SELECT 
            MG87_DESCART,
            MG87_DESCARTEST,
            REPLACE(MG87_DESCART, '14UNF', '12UNF')    AS MG87_DESCART_NEW,
            REPLACE(MG87_DESCARTEST, '14UNF', '12UNF') AS MG87_DESCARTEST_NEW
        FROM dbo.MG87_ARTDESC
        WHERE MG87_DITTA_CG18 = 1
          AND MG87_CODART_MG66 LIKE '%P1--%'
          AND (MG87_CODART_MG66 LIKE '%F-' OR MG87_CODART_MG66 LIKE '%FS')
          AND RTRIM(MG87_DESCART) + ' ' + ISNULL(MG87_DESCARTEST, '') LIKE '%14UNF%'
    )
    UPDATE CteFilettatureUnf 
    SET 
        MG87_DESCART    = MG87_DESCART_NEW, 
        MG87_DESCARTEST = MG87_DESCARTEST_NEW;

END;
GO
