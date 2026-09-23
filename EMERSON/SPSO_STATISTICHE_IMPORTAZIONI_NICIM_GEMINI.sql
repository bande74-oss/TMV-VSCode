-- ==============================================================================
-- Cartiglio Narrativo Obbligatorio (Standard SOLVERIS)
-- ==============================================================================
-- Data e Ora Creazione : 23/09/2026 12:00:00
-- Autore               : SOLVERIS - Bandera Marco
-- Progetto             : TMV - Tracciabilità di Produzione e Integrazione MES / Plugin Avanzamenti
-- Nome Oggetto         : dbo.SPSO_STATISTICHE_IMPORTAZIONI_NICIM_GEMINI
-- Tipo Oggetto         : Stored Procedure
-- Versione DBMS Target : MSSQL 14.0.2120.1 (SQL Server 2017)
--
-- CONTESTO AZIENDALE E TECNICO DI APPARTENENZA:
-- ------------------------------------------------------------------------------
-- Nella complessa architettura di fabbrica di TMV, il flusso "fisiologico" delle
-- registrazioni di fabbrica prevede che le dichiarazioni di avanzamento delle fasi
-- produttive e il consumo reale delle materie prime (barre, forgiati, viteria, dadi)
-- vengano acquisiti dagli operatori a bordo macchina attraverso il MES OVERONE.
-- Il MES trasmette tali eventi verso l'ERP Alyante popolando due tabelle di
-- interscambio primarie:
--   1) dbo.RT15_OVERONE_AVANZAMENTI (avanzamento temporale e pezzi per fase/macchina)
--   2) dbo.RT16_OVERONE_CONSUMI     (scarico effettivo dei lotti/barre consumati)
--
-- Tramite i tracciati di importazione standard dell'ERP (gestiti dal modulo IE25):
--   - "TMV-NICIM-AVANZ" (da RT15)
--   - "TMV-NICIM-CONSM" (da RT16)
-- tali dati confluiscono normalmente nelle due tabelle operative del Plugin
-- Avanzamenti di TeamSystem:
--   - dbo.NICIM_AVANZ   (testate/fasi di avanzamento produzione e versamenti)
--   - dbo.NICIM_CONSMAT (componenti e lotti consumati abbinati all'avanzamento)
--
-- LA CRITICITÀ STORICA E IL MECCANISMO DI FORZATURA / FALLBACK (Circa 5 anni fa):
-- ------------------------------------------------------------------------------
-- Per vincoli organizzativi e prassi storiche, si riscontravano frequentemente casi
-- in cui l'ordine cliente risultava già evaso e pronto alla spedizione, ma gli ODL
-- di produzione su Alyante rimanevano aperti, non congrui o incompleti a causa di:
--   - Mancata o parziale dichiarazione a bordo macchina su Overone.
--   - Fasi o consumi mai esportati o rimasti in errore (es. RT16_DATA_ELAB IS NULL).
-- Per risolvere l'impasse e consentire la fatturazione/scarico contabile, venne
-- introdotto un meccanismo automatico alternativo basato su due tracciati specifici:
--
-- A) TRACCIATO "TMV-NICIM-AVAN2" (Sorgente: dbo.VPMES_RT15_RT16_ALYANTE):
--    Intercetta gli ODL collegati a ordini clienti evasi ma privi di registrazione
--    in NICIM_AVANZ (condizione: GAMMA_ID IS NULL). Per tali ODL genera "a tavolino"
--    le righe di avanzamento in NICIM_AVANZ marcandole in modo inequivocabile con:
--      - CODICE_RISORSA = 'XXXX' (risorsa fittizia di versamento contabile)
--      - ORE_MACCHINA = 0
--      - ATTIVITA = 'L', TIPO_TEMPO = 'L'
--      - DESCRIZIONE_OPERAZIONE = 'Versamento'
--
-- B) TRACCIATO "TMV-NICIM-CONS2" (Sorgente: dbo.VPMES_RT15_RT16_ALYANTE_SCAR):
--    Preceduto dall'esecuzione della procedura dbo.SPRT_NICIM_CONS2 (che resetta
--    PROCESSATO = 0 e DATA_PROC = NULL per le righe di fase 1000 in NICIM_AVANZ),
--    questo tracciato genera forzatamente i consumi componenti in NICIM_CONSMAT:
--      - Assegna CODICE_FASE = 1000 e NUMERO_FASE = 10.
--      - Recupera lotti da giacenze con certificato o assegna il LOTTO FITTIZIO 'LT-2403-999'.
--      - Sostituisce la viteria/dadi con regole di stock (prefisso 'D--' o RT00_TEMP_DADI_POLITICA).
--
-- SCOPO DELLA PRESENTE STORED PROCEDURE:
-- ------------------------------------------------------------------------------
-- Fino ad oggi non era mai stata redatta una quantificazione statistica precisa
-- dell'impatto di questo impianto di forzatura. La presente procedura assolve
-- a questo compito critico di governance, estraendo con cadenza mensile:
--   1) Il volume e la percentuale di avanzamenti reali (MES) vs fittizi (Alyante 'XXXX').
--   2) Il volume e la percentuale di consumi reali (RT16 MES) vs forzati da Alyante.
--   3) La ripartizione per tipologia di materiale trattato forzatamente
--      (Minuteria/Dadi 'D--', Stampati/Forgiati 'KB', Barre/Tubi 'TDR/TDP', Lotti fittizi).
--   4) Il dettaglio per codice fase delle lavorazioni forzate (Versamento 1000,
--      Chiusura ODL 6000, Fasi intermedie di lavorazione).
--
-- REGOLE DI SICUREZZA E MODALITÀ DRY-RUN:
-- ------------------------------------------------------------------------------
-- La procedura implementa per default la modalità sicura (@DryRun = 1).
-- Trattandosi di una procedura di analisi e reporting statistico (esclusivamente
-- query di lettura con direttiva WITH (NOLOCK) per non causare lock sulle tabelle
-- transazionali di produzione), la modalità DryRun espone un set di informazioni
-- diagnostiche descrittive e i KPI preliminari prima dell'erogazione dei prospetti.
--
-- STORICO REVISIONI (Change Log Narrativo):
-- ------------------------------------------------------------------------------
-- Rev. 1 [23/09/2026 - SOLVERIS (Bandera Marco)]:
--   - Creazione iniziale della stored procedure su specifiche aziendali e analisi
--     dei tracciati IE25 (TMV-NICIM-AVAN2 e TMV-NICIM-CONS2).
--   - Implementazione della doppia aggregazione a base mese (Avanzamenti e Consumi).
--   - Implementazione della decodifica merceologica dei componenti consumati da Alyante.
--   - Adozione di tabelle temporanee con COLLATION DATABASE_DEFAULT per massime performance.
-- ==============================================================================

CREATE OR ALTER PROCEDURE dbo.SPSO_STATISTICHE_IMPORTAZIONI_NICIM_GEMINI
(
    @AnnoDa         INT         = NULL,  -- Anno di partenza (default: ultimi 24 mesi)
    @MeseDa         INT         = NULL,  -- Mese di partenza (1-12)
    @AnnoA          INT         = NULL,  -- Anno finale (default: anno corrente)
    @MeseA          INT         = NULL,  -- Mese finale (1-12, default: mese corrente)
    @TipoReport     VARCHAR(30) = 'ALL', -- 'ALL', 'AVANZAMENTI', 'CONSUMI', 'TIPOLOGIE'
    @DryRun         BIT         = 1      -- 1 = Modalità descrittiva verbosa (Default), 0 = Solo dati finali
)
AS
BEGIN
    SET NOCOUNT ON;

    -- ==========================================================================
    -- SEZIONE 1: Normalizzazione e Validazione dei Parametri Temporali
    -- ==========================================================================
    -- Spiegazione di Business:
    -- Se l'utente non specifica l'intervallo temporale, la procedura adotta una
    -- finestra di default sugli ultimi 2 anni, garantendo una visione storica
    -- sufficiente a comprendere il trend di dismissione o adozione del MES.
    -- ==========================================================================
    DECLARE @DataInizioAnalisi DATE;
    DECLARE @DataFineAnalisi   DATE;

    -- Calcolo anno e mese correnti
    DECLARE @AnnoCorrente INT = YEAR(GETDATE());
    DECLARE @MeseCorrente INT = MONTH(GETDATE());

    -- Determinazione estremo superiore (Fine)
    IF @AnnoA IS NULL
        SET @AnnoA = @AnnoCorrente;
    IF @MeseA IS NULL
        SET @MeseA = @MeseCorrente;

    -- Determinazione estremo inferiore (Inizio: default 2 anni prima)
    IF @AnnoDa IS NULL
        SET @AnnoDa = @AnnoA - 2;
    IF @MeseDa IS NULL
        SET @MeseDa = 1;

    -- Costruzione date formali di delimitazione temporale
    SET @DataInizioAnalisi = DATEFROMPARTS(@AnnoDa, @MeseDa, 1);
    -- Fine mese: primo giorno del mese successivo meno un giorno
    SET @DataFineAnalisi   = EOMONTH(DATEFROMPARTS(@AnnoA, @MeseA, 1));

    -- ==========================================================================
    -- SEZIONE 2: Output Diagnostico Verboso (Modalità Dry-Run)
    -- ==========================================================================
    IF @DryRun = 1
    BEGIN
        SELECT 
            'MODALITA_DRY_RUN_ATTIVA' AS StatoEsecuzione,
            'Procedura di consultazione statistica eseguita in modalita sicura e verbosa. Nessuna operazione di modifica dati (DML) verra eseguita sul database.' AS AvvertenzaSicurezza,
            @DataInizioAnalisi AS DataInizioFiltro,
            @DataFineAnalisi   AS DataFineFiltro,
            @TipoReport        AS AmbitoRichiesto,
            'I dati estratti confrontano le dichiarazioni canoniche del MES Overone con i meccanismi di forzatura gestiti dai tracciati Alyante TMV-NICIM-AVAN2 (risorsa XXXX) e TMV-NICIM-CONS2 (consumi forzati/lotto fittizio).' AS SpiegazioneContesto;
    END

    -- ==========================================================================
    -- SEZIONE 3: Indicizzazione Temporanea dei Consumi Reali MES (RT16)
    -- ==========================================================================
    -- Spiegazione di Business e Ottimizzazione Tecnica:
    -- La tabella dbo.NICIM_CONSMAT contiene oltre 150.000 record ed e priva di indici.
    -- Per identificare con precisione chirurgica se un consumo registrato in NICIM_CONSMAT
    -- provenga dal MES reale o dal tracciato di forzatura Alyante (TMV-NICIM-CONS2),
    -- carichiamo in una tabella temporanea con indice clusterizzato univoco le coppie
    -- (Codice Ordine ODL + Lotto Scaricato) presenti in RT16_OVERONE_CONSUMI.
    -- Viene applicata la clausola COLLATE DATABASE_DEFAULT per rispettare la regola
    -- di assoluta compatibilita di Collation del progetto TMV.
    -- ==========================================================================
    IF @TipoReport IN ('ALL', 'CONSUMI', 'TIPOLOGIE')
    BEGIN
        IF OBJECT_ID('tempdb..#RT16_MES_REALE') IS NOT NULL
            DROP TABLE #RT16_MES_REALE;

        CREATE TABLE #RT16_MES_REALE
        (
            CODICE_ORDINE VARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL,
            LOTTO         VARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL,
            PRIMARY KEY CLUSTERED (CODICE_ORDINE, LOTTO)
        );

        INSERT INTO #RT16_MES_REALE (CODICE_ORDINE, LOTTO)
        SELECT DISTINCT
            RTRIM(RT16_NUMREG_CO99) + '/' + RTRIM(FORMAT(RT16_PROGRIGA, '####')) AS CODICE_ORDINE,
            RTRIM(RT16_CODICE_BATCH) AS LOTTO
        FROM dbo.RT16_OVERONE_CONSUMI WITH (NOLOCK)
        WHERE RT16_DITTA_CG18 = 1
          AND ISNULL(RT16_CODICE_BATCH, '') <> '';
    END

    -- ==========================================================================
    -- SEZIONE 4: REPORT 1 - Statistica Mensile Avanzamenti (NICIM_AVANZ)
    -- ==========================================================================
    -- Spiegazione di Business:
    -- Il tracciato TMV-NICIM-AVAN2 inserisce in NICIM_AVANZ record con CODICE_RISORSA = 'XXXX'.
    -- Tutte le righe provenienti dal MES Overone hanno invece il codice risorsa reale della
    -- macchina utensile o della linea (es. CL1, TA7, SM1, RU2, CE3, ecc.).
    -- Questa query ripartisce per anno e mese il volume totale di avanzamenti,
    -- distinguendo la quota parte fisiologica dal carico artificiale generato da Alyante.
    -- ==========================================================================
    IF @TipoReport IN ('ALL', 'AVANZAMENTI')
    BEGIN
        SELECT 
            YEAR(A.DATA)                                                    AS Anno,
            MONTH(A.DATA)                                                   AS Mese,
            FORMAT(A.DATA, 'yyyy-MM')                                       AS Periodo,
            
            -- Volumi Complessivi
            COUNT(*)                                                        AS Totale_Righe_Avanzamenti,
            
            -- Ripartizione Sorgente (MES Reale vs Fallback Alyante)
            COUNT(CASE WHEN A.CODICE_RISORSA <> 'XXXX' THEN 1 END)          AS Avanzamenti_MES_Reali,
            CAST(ROUND(100.0 * COUNT(CASE WHEN A.CODICE_RISORSA <> 'XXXX' THEN 1 END) / NULLIF(COUNT(*), 0), 2) AS NUMERIC(5,2)) AS Perc_MES_Reale,
            
            COUNT(CASE WHEN A.CODICE_RISORSA = 'XXXX' THEN 1 END)           AS Avanzamenti_Alyante_XXXX,
            CAST(ROUND(100.0 * COUNT(CASE WHEN A.CODICE_RISORSA = 'XXXX' THEN 1 END) / NULLIF(COUNT(*), 0), 2) AS NUMERIC(5,2)) AS Perc_Alyante_XXXX,
            
            -- Dettaglio delle Fasi Oggetto di Trattamento da Alyante
            COUNT(CASE WHEN A.CODICE_RISORSA = 'XXXX' AND A.CODICE_FASE = 1000 THEN 1 END)  AS Alyante_Versamento_Fase_1000,
            COUNT(CASE WHEN A.CODICE_RISORSA = 'XXXX' AND A.CODICE_FASE = 6000 THEN 1 END)  AS Alyante_Chiusura_Fase_6000,
            COUNT(CASE WHEN A.CODICE_RISORSA = 'XXXX' AND A.CODICE_FASE NOT IN (1000, 6000) THEN 1 END) AS Alyante_Fasi_Intermedie

        FROM dbo.NICIM_AVANZ A WITH (NOLOCK)
        WHERE A.DATA >= @DataInizioAnalisi
          AND A.DATA <= @DataFineAnalisi
        GROUP BY YEAR(A.DATA), MONTH(A.DATA), FORMAT(A.DATA, 'yyyy-MM')
        ORDER BY Anno, Mese;
    END

    -- ==========================================================================
    -- SEZIONE 5: REPORT 2 - Statistica Mensile Consumi Componenti (NICIM_CONSMAT)
    -- ==========================================================================
    -- Spiegazione di Business:
    -- I consumi registrati in NICIM_CONSMAT possono derivare da:
    --   1) Tracciato TMV-NICIM-CONSM (dichiarati su Overone ed esistenti in RT16_OVERONE_CONSUMI)
    --   2) Tracciato TMV-NICIM-CONS2 (forzati da Alyante tramite VPMES_RT15_RT16_ALYANTE_SCAR)
    -- Questa query rileva mensilmente quante righe di consumo sono state generate
    -- forzatamente, specificando l'impiego del lotto fittizio di emergenza 'LT-2403-999'
    -- e la categoria merceologica del materiale scaricato.
    -- ==========================================================================
    IF @TipoReport IN ('ALL', 'CONSUMI')
    BEGIN
        SELECT 
            YEAR(C.DATA)                                                    AS Anno,
            MONTH(C.DATA)                                                   AS Mese,
            FORMAT(C.DATA, 'yyyy-MM')                                       AS Periodo,
            
            -- Volumi Complessivi
            COUNT(*)                                                        AS Totale_Righe_Consumi,
            
            -- Consumi Reali MES (Presenza esatta in RT16)
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NOT NULL THEN 1 END)       AS Consumi_MES_Reali,
            CAST(ROUND(100.0 * COUNT(CASE WHEN R16.CODICE_ORDINE IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) AS NUMERIC(5,2)) AS Perc_Consumi_MES,
            
            -- Consumi Forzati / Fallback Alyante (Non presenti in RT16)
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL THEN 1 END)           AS Consumi_Alyante_Trattati,
            CAST(ROUND(100.0 * COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) AS NUMERIC(5,2)) AS Perc_Consumi_Alyante,
            
            -- Focus sul Lotto Convenzionale Fittizio
            COUNT(CASE WHEN C.LOTTO LIKE '%LT-2403-999%' THEN 1 END)        AS Consumi_Lotto_Fittizio_LT2403999,
            
            -- Dettaglio per Famiglia di Componenti Forzati da Alyante
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL AND (C.CODICE_PARTE LIKE 'D--%' OR C.CODICE_PARTE LIKE 'DADI%') THEN 1 END) AS Alyante_Minuteria_Dadi_D,
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL AND C.CODICE_PARTE LIKE 'KB_%' THEN 1 END)                                 AS Alyante_Forgiati_Stampati_KB,
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL AND (C.CODICE_PARTE LIKE 'TDR%' OR C.CODICE_PARTE LIKE 'TDP%') THEN 1 END) AS Alyante_Barre_Tubi_TDR,
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL AND NOT (C.CODICE_PARTE LIKE 'D--%' OR C.CODICE_PARTE LIKE 'DADI%' OR C.CODICE_PARTE LIKE 'KB_%' OR C.CODICE_PARTE LIKE 'TDR%' OR C.CODICE_PARTE LIKE 'TDP%') THEN 1 END) AS Alyante_Altri_Materiali

        FROM dbo.NICIM_CONSMAT C WITH (NOLOCK)
        LEFT JOIN #RT16_MES_REALE R16
            ON R16.CODICE_ORDINE = RTRIM(C.CODICE_ORDINE)
            AND R16.LOTTO         = RTRIM(C.LOTTO)
        WHERE C.DATA >= @DataInizioAnalisi
          AND C.DATA <= @DataFineAnalisi
        GROUP BY YEAR(C.DATA), MONTH(C.DATA), FORMAT(C.DATA, 'yyyy-MM')
        ORDER BY Anno, Mese;
    END

    -- ==========================================================================
    -- SEZIONE 6: REPORT 3 - Dettaglio Tipologie e KPI Complessivi del Periodo
    -- ==========================================================================
    -- Spiegazione di Business:
    -- Fornisce un quadro sinottico aggregato sull'intero intervallo temporale
    -- selezionato, utile per presentazioni direzionali e per quantificare
    -- il livello di affidabilità o scostamento del MES rispetto al gestionale.
    -- ==========================================================================
    IF @TipoReport IN ('ALL', 'TIPOLOGIE')
    BEGIN
        SELECT 
            'SINOTTICO_CONSUMI_PER_TIPOLOGIA' AS CategoriaReport,
            CASE 
                WHEN C.LOTTO LIKE '%LT-2403-999%' THEN 'Lotto Fittizio di Emergenza (LT-2403-999)'
                WHEN C.CODICE_PARTE LIKE 'D--%' OR C.CODICE_PARTE LIKE 'DADI%' THEN 'Minuteria / Dadi Stock (Prefisso D--)'
                WHEN C.CODICE_PARTE LIKE 'KB_%' THEN 'Forgiati / Stampati (Prefisso KB_)'
                WHEN C.CODICE_PARTE LIKE 'TDR%' OR C.CODICE_PARTE LIKE 'TDP%' THEN 'Barre / Tubi da Taglio (Prefisso TDR/TDP)'
                ELSE 'Altri Semilavorati / Componenti Diversi'
            END AS TipologiaMateriale,
            COUNT(*)                                                        AS Totale_Righe,
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NOT NULL THEN 1 END)       AS Gestite_Da_MES,
            COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL THEN 1 END)           AS Forzate_Da_Alyante,
            CAST(ROUND(100.0 * COUNT(CASE WHEN R16.CODICE_ORDINE IS NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) AS NUMERIC(5,2)) AS Perc_Forzatura_Alyante
        FROM dbo.NICIM_CONSMAT C WITH (NOLOCK)
        LEFT JOIN #RT16_MES_REALE R16
            ON R16.CODICE_ORDINE = RTRIM(C.CODICE_ORDINE)
            AND R16.LOTTO         = RTRIM(C.LOTTO)
        WHERE C.DATA >= @DataInizioAnalisi
          AND C.DATA <= @DataFineAnalisi
        GROUP BY 
            CASE 
                WHEN C.LOTTO LIKE '%LT-2403-999%' THEN 'Lotto Fittizio di Emergenza (LT-2403-999)'
                WHEN C.CODICE_PARTE LIKE 'D--%' OR C.CODICE_PARTE LIKE 'DADI%' THEN 'Minuteria / Dadi Stock (Prefisso D--)'
                WHEN C.CODICE_PARTE LIKE 'KB_%' THEN 'Forgiati / Stampati (Prefisso KB_)'
                WHEN C.CODICE_PARTE LIKE 'TDR%' OR C.CODICE_PARTE LIKE 'TDP%' THEN 'Barre / Tubi da Taglio (Prefisso TDR/TDP)'
                ELSE 'Altri Semilavorati / Componenti Diversi'
            END
        ORDER BY Totale_Righe DESC;
    END

    -- Pulizia finale della tabella temporanea
    IF OBJECT_ID('tempdb..#RT16_MES_REALE') IS NOT NULL
        DROP TABLE #RT16_MES_REALE;

END;
GO

