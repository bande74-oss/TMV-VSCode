-- =================================================================================================================================
-- Cartiglio Narrativo Obbligatorio (Standard di Codifica SOLVERIS - Progetto TMV)
-- =================================================================================================================================
-- Data e Ora Creazione : 2026-10-23 12:20
-- Autore               : SOLVERIS - Bandera Marco
-- Oggetto SQL          : [dbo].[SPSO_NKE_SCHED_GEMINI]
-- Tipologia Oggetto    : Stored Procedure (Dispatcher / Coda Consumatore)
-- Versione Compatibile : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1)
-- Ambiente Target      : DBTMV (Produzione / Staging)
--
-- STORIA E CONTESTO DI BUSINESS:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Questa procedura rappresenta l'evoluzione ingegnerizzata e risanata della precedente stored procedure 'SPRT_NKE_SCHED'
-- (sviluppata originariamente da Francesco Coria e manutenuta nel tempo con interventi correttivi).
--
-- Il suo scopo è agire da motore di dispatching (consumatore) della coda tecnica RT13_NKE:
-- 1. Viene invocata a ciclo continuo ogni 30 secondi dal Job SQL Server Agent 'TMV.NKE - Genera disegni'.
-- 2. Alimenta il robot CAD NKE inviando al massimo una richiesta alla volta tramite l'endpoint HTTP POST
--    governato da SPRT_NKE_POST ('http://192.168.1.138:7171/configure').
-- 3. Cadenza e distanzia le chiamate per evitare di saturare il server di modellazione 3D e il motore iLogic di Autodesk Inventor.
--
-- ANOMALIE SANATE RISPETTO A SPRT_NKE_SCHED:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- 1. Bug del Delay Temporale (dateadd futuro):
--    Nella vecchia procedura, il parametro @SecondiTraChiamate letto dalla tabella RT14_VARIABILI_READYTEC (valore +30)
--    veniva sommato a GETDATE() anziché sottratto (dateadd(SECOND, @SecondiTraChiamate, GETDATE())). Poiché una data futura
--    è sempre maggiore di qualsiasi data passata, la clausola di cooldown risultava perennemente vera, vanificando
--    la protezione sul tempo minimo di attesa tra tentativi.
--    La nuova procedura adotta tassativamente: DATEADD(SECOND, -ABS(@SecondiTraChiamate), GETDATE()).
-- 2. Supporto Nativo Modalità Dry-Run:
--    Aggiunto il parametro @ModalitaDryRun = 1 per default (Standard TMV), consentendo il debug sicuro
--    della coda e del payload inviato senza generare traffico HTTP effettivo verso NKE.
-- 3. Pulizia e Archiviazione Atomica:
--    Mantenuto e consolidato il meccanismo per cui, al raggiungimento della soglia tentativi, la riga viene
--    cancellata da RT13_NKE, scatenando il trigger di sistema RT13_AFTER_DELETE che storicizza deterministicamente
--    l'evento nella tabella RT13_NKE_LOG.
--
-- STORICO REVISIONI:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Rev. 0 | 2026-10-23 | SOLVERIS - Bandera Marco
-- Reingegnerizzazione di SPRT_NKE_SCHED con correzione bug delay, standard SOLVERIS, dry-run e commenti esplicativi.
-- =================================================================================================================================

CREATE OR ALTER PROCEDURE [dbo].[SPSO_NKE_SCHED_GEMINI]
    @ModalitaDryRun     BIT = 1         -- 1 = Simulazione Verbosa (Dry-Run / DryOut), 0 = Esecuzione Reale Chiamata HTTP
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Variabili di controllo operativo
    DECLARE @Eseguo                 BIT = 0;
    DECLARE @CURRENT_GUID           UNIQUEIDENTIFIER = NULL;
    DECLARE @CODICE_ART_VAR_NKE     VARCHAR(31) = NULL;
    DECLARE @CodiceArticolo         CHAR(25) = NULL;
    DECLARE @OpzioneVariante        CHAR(20) = NULL;
    DECLARE @SecondiTraChiamate     INT = 30;
    DECLARE @RC                     INT = 0;

    -- =============================================================================================================================
    -- SEZIONE 1: Recupero Parametri di Configurazione da RT14_VARIABILI_READYTEC
    -- =============================================================================================================================
    SELECT @SecondiTraChiamate = ISNULL(RT14_NUMBER_VALUE, 30)
    FROM dbo.RT14_VARIABILI_READYTEC WITH (NOLOCK)
    WHERE RT14_VARNAME = 'SPRT_NKE_SCHED' 
      AND RT14_DITTA_CG18 = 1;

    IF @SecondiTraChiamate IS NULL OR @SecondiTraChiamate <= 0
        SET @SecondiTraChiamate = 30;

    -- =============================================================================================================================
    -- SEZIONE 2: Deduplicazione Preventiva della Coda RT13_NKE
    -- =============================================================================================================================
    -- Se per qualsiasi anomalia sono entrate righe con lo stesso MG87_GUID, si mantiene solo la più anziana
    -- per non sovraccaricare il robot CAD con chiamate ridondanti.
    IF @ModalitaDryRun = 0
    BEGIN
        WITH RIGHE_DOPPIE AS (
            SELECT 
                MG87_GUID,
                ROW_NUMBER() OVER (PARTITION BY MG87_GUID ORDER BY RT13_INSERT_DATETIME ASC) AS Prog
            FROM dbo.RT13_NKE
        )
        DELETE FROM RIGHE_DOPPIE WHERE Prog > 1;
    END

    -- =============================================================================================================================
    -- SEZIONE 3: Valutazione Condizione di Ingresso ed Eleggibilità alla Chiamata
    -- =============================================================================================================================
    -- Si esegue la call se:
    -- A) Abbiamo almeno una richiesta nuova (RT13_CALL_DATETIME IS NULL) e nessuna chiamata in corso;
    -- OPPURE
    -- B) Sono trascorsi almeno @SecondiTraChiamate dall'ultima chiamata inviata per permettere al server NKE di elaborare.
    -- NOTA BENE: Utilizzo mandatorio di -ABS(@SecondiTraChiamate) per sanare il bug storico dell'addizione futura.
    IF (
        ((SELECT COUNT(*) FROM dbo.RT13_NKE WITH (NOLOCK) WHERE RT13_CALL_DATETIME IS NOT NULL) = 0 
         AND (SELECT COUNT(*) FROM dbo.RT13_NKE WITH (NOLOCK) WHERE RT13_CALL_DATETIME IS NULL) > 0)
        OR
        ((SELECT ISNULL(MAX(RT13_CALL_DATETIME), '1900-01-01') 
          FROM dbo.RT13_NKE WITH (NOLOCK) 
          WHERE RT13_CALL_DATETIME IS NOT NULL AND RT13_FILE_GENERATO = 0) < DATEADD(SECOND, -ABS(@SecondiTraChiamate), GETDATE()))
    )
    BEGIN
        SET @Eseguo = 1;
    END

    -- Se non sussistono le condizioni temporali o di coda, si esce senza eseguire nulla
    IF @Eseguo = 0
    BEGIN
        IF @ModalitaDryRun = 1
        BEGIN
            SELECT 
                'DISPATCHER IN ATTESA (COOLDOWN O CODA VUOTA)' AS [STATO OPERATIVO],
                (SELECT COUNT(*) FROM dbo.RT13_NKE WITH (NOLOCK)) AS [Totale Elementi in Coda],
                (SELECT COUNT(*) FROM dbo.RT13_NKE WITH (NOLOCK) WHERE RT13_CALL_DATETIME IS NULL) AS [Elementi Mai Chiamati],
                (SELECT MAX(RT13_CALL_DATETIME) FROM dbo.RT13_NKE WITH (NOLOCK)) AS [Ultima Chiamata Effettuata],
                @SecondiTraChiamate AS [Secondi Cooldown Richiesti];
        END
        RETURN;
    END

    -- =============================================================================================================================
    -- SEZIONE 4: Individuazione del Prossimo Articolo da Inviare a NKE
    -- =============================================================================================================================
    -- Priorità 1: Record con RT13_CALL_DATETIME NULL (richieste vergini mai tentate prima), ordinati per data inserimento.
    SELECT TOP 1 
        @CURRENT_GUID       = MG87_GUID,
        @CodiceArticolo     = RT13_CODART_MG66,
        @OpzioneVariante    = RT13_OPZIONE_MG5E,
        @CODICE_ART_VAR_NKE = CONCAT(
            LEFT(TRIM(RT13_CODART_MG66), 5), '---', RIGHT(TRIM(RT13_CODART_MG66), 6),
            LEFT(REPLACE(RT13_OPZIONE_MG5E + '-----------------', ' ', '-'), 5), '------',
            RIGHT(LEFT(REPLACE(RT13_OPZIONE_MG5E + '-----------------', ' ', '-'), 17), 6)
        )
    FROM dbo.RT13_NKE WITH (NOLOCK)
    WHERE RT13_CALL_DATETIME IS NULL
    ORDER BY RT13_INSERT_DATETIME ASC, MG87_GUID;

    -- Priorità 2: Se non vi sono record vergini, si ricercano record con chiamata pregressa o flag sovrascrittura
    IF @CURRENT_GUID IS NULL
    BEGIN
        SELECT TOP 1 
            @CURRENT_GUID       = MG87_GUID,
            @CodiceArticolo     = RT13_CODART_MG66,
            @OpzioneVariante    = RT13_OPZIONE_MG5E,
            @CODICE_ART_VAR_NKE = CONCAT(
                LEFT(TRIM(RT13_CODART_MG66), 5), '---', RIGHT(TRIM(RT13_CODART_MG66), 6),
                LEFT(REPLACE(RT13_OPZIONE_MG5E + '-----------------', ' ', '-'), 5), '------',
                RIGHT(LEFT(REPLACE(RT13_OPZIONE_MG5E + '-----------------', ' ', '-'), 17), 6)
            )
        FROM dbo.RT13_NKE WITH (NOLOCK)
        WHERE (RT13_CALL_DATETIME IS NOT NULL AND RT13_FILE_GENERATO = 0) 
           OR RT13_SOVRASCRIVI = 1
        ORDER BY RT13_INSERT_DATETIME ASC, MG87_GUID;
    END

    -- Se non è stato individuato alcun articolo idoneo, si arresta il flusso
    IF @CURRENT_GUID IS NULL
    BEGIN
        IF @ModalitaDryRun = 1
        BEGIN
            SELECT 'NESSUN ARTICOLO DA INVIARE IN CODA RT13_NKE' AS [STATO OPERATIVO];
        END
        RETURN;
    END

    -- =============================================================================================================================
    -- SEZIONE 5: Modalità Dry-Run vs Esecuzione Reale
    -- =============================================================================================================================
    IF @ModalitaDryRun = 1
    BEGIN
        SELECT 
            'DRYOUT VERBOSO - PROSSIMO ARTICOLO DA SPEDIRE A NKE' AS [STATO OPERATIVO],
            @CURRENT_GUID           AS [MG87_GUID],
            @CodiceArticolo         AS [Codice Articolo],
            @OpzioneVariante        AS [Opzione / Variante],
            @CODICE_ART_VAR_NKE     AS [Codice Formattato NKE (Master)],
            SUBSTRING(@CODICE_ART_VAR_NKE, 1, 3) AS [Typology NKE],
            'http://192.168.1.138:7171/configure' AS [Endpoint Target NKE],
            CONCAT(
                '{"Id":"', @CURRENT_GUID,
                '","MasterDataArray":[{"Master":"', @CODICE_ART_VAR_NKE,
                '","Typology":"', SUBSTRING(@CODICE_ART_VAR_NKE, 1, 3),
                '","Rules":[]}],"ParametersArray":[{}]}'
            ) AS [Payload JSON Simulato];

        RETURN;
    END

    -- =============================================================================================================================
    -- SEZIONE 6: Esecuzione Reale Chiamata HTTP verso NKE e Avanzamento Stato Coda
    -- =============================================================================================================================
    -- Invocazione della procedura preposta all'invio HTTP POST via MSXML2.ServerXMLHTTP
    EXECUTE @RC = dbo.SPRT_NKE_POST 
        @CURRENT_GUID   = @CURRENT_GUID,
        @CODICE_ART_VAR = @CODICE_ART_VAR_NKE;

    -- Aggiornamento timestamp di chiamata e incremento tentativi
    UPDATE dbo.RT13_NKE
    SET 
        RT13_CALL_DATETIME = GETDATE(),
        RT13_NUM_TENTATIVI = RT13_NUM_TENTATIVI + 1
    WHERE MG87_GUID = @CURRENT_GUID;

    -- Al superamento del numero massimo tentativi (tentativi > 1), la riga viene rimossa da RT13_NKE.
    -- La cancellazione attiva automaticamente il trigger [dbo].[RT13_AFTER_DELETE]
    -- che provvede a registrare la transazione storica nella tabella [dbo].[RT13_NKE_LOG].
    DELETE FROM dbo.RT13_NKE 
    WHERE RT13_NUM_TENTATIVI > 1;

END;
GO

