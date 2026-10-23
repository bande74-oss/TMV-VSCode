-- =================================================================================================================================
-- Cartiglio Narrativo Obbligatorio (Standard di Codifica SOLVERIS - Progetto TMV)
-- =================================================================================================================================
-- Data e Ora Creazione : 2026-10-23 12:15
-- Data Ultima Modifica : 2026-10-23 13:50
-- Autore               : SOLVERIS - Bandera Marco
-- Oggetto SQL          : [dbo].[SPSO_NKE_ALIMENTA_CODA_GEMINI]
-- Tipologia Oggetto    : Stored Procedure
-- Versione Compatibile : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1)
-- Ambiente Target      : DBTMV (Produzione / Staging)
--
-- STORIA E CONTESTO DI BUSINESS:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Questa procedura nasce dall'esigenza stringente di revisionare e risanare l'intero impianto di integrazione che invia le richieste
-- di creazione dei disegni tecnici CAD dall'ERP Gamma Enterprise verso il software robotizzato di terze parti (fornitore NKE).
-- 
-- Nel sistema preesistente, l'innesco delle richieste era affidato all'Insieme ImpExp 'TMV_NKE', segnatamente al tracciato Documenti
-- 'TMV_NKE_OC' (Struttura 4). Tale tracciato presentava un grave limite architetturale e operativo:
-- 1. Filtrava rigidamente in selezione (IE99_SELEZIONEPRS) le sole righe di ordine con Stato Riga = 10045 ('Generato').
-- 2. Qualsiasi ordine modificato successivamente alla prima immissione (es. posizioni inserite inizialmente come tiranti, poi
--    variate in stud-bolt PDN o corrette dimensionalmente dopo la prima bozza) ed avanzato negli stati di validazione tecnica
--    (10046 - DIBA Localizzata, 10047 - Approv. COM, 10048 - Approv. DIR, 10051 - ODL Generato, ecc.) diventava totalmente
--    invisibile al motore di estrazione ImpExp.
-- 3. Di conseguenza, l'Ufficio Tecnico e i disegnatori si trovavano con 'buchi' sistematici di disegni DWG, costretti a ridisegnare
--    manualmente decine di particolari (come accaduto sull'ordine CO 5519 con circa 50 disegni mancanti/errati).
-- 4. Mancava del tutto la possibilità per gli operatori di forzare il ri-processamento mirato di una specifica conferma d'ordine
--    senza dover manomettere le selezioni globali di sistema.
--
-- LOGICA FUNZIONALE DELLA NUOVA PROCEDURA:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- La presente Stored Procedure sostituisce integralmente il meccanismo di estrazione ImpExp, implementando una logica deterministica:
-- A) Monitora gli ordini di vendita (TipoDoc = 21, Documenti 'DC-ORDINE', 'DC-ORDGAR') e le relative righe corpo (DO30_DOCCORPO).
-- B) Considera le righe che si trovano negli stati di maturazione confermata e post-approvazione pre-produzione definiti
--    dalla Direzione Tecnica: (10046, 10048, 10049, 10050, 10051, 10054, 10055).
-- C) Filtra le famiglie di articoli abilitate alla robotica NKE: lunghezza codice di 14 caratteri e prefisso tipologico di 3 caratteri
--    censito nel configuratore commerciale (CM02_VALORICATCOMM con IDCategoria = 1 e Flag CM02_A = 'NKE').
-- D) Motore Delta Differenziale Resiliente:
--    - Tramite predicati EXISTS ad alte prestazioni, verifica se la specifica coppia univoca (Codice Articolo, Variante) identificata
--      dal suo MG87_GUID sia già presente a storico nella tabella di log RT13_NKE_LOG con generazione confermata (RT13_FILE_GENERATO = 1)
--      oppure sia già attualmente accodata in RT13_NKE.
--    - Se un record in passato è fallito (RT13_FILE_GENERATO = 0), non viene considerato completato e viene riaccodato per non lasciare disegni mancanti.
-- E) Tracciabilità 1-a-Molti (RT13_NKE_DOCS_GEMINI):
--    - Pur deduplicando le chiamate NKE in RT13_NKE per non sovraccaricare il motore CAD Inventor, la procedura popola la tabella ponte
--      RT13_NKE_DOCS_GEMINI associando ad ogni variante tutti i riferimenti di testata (NumDoc, Sez, Anno, Ragione Sociale Cliente)
--      e riga (DO30_PROGRIGA), consentendo al Monitor Intranet di esporre la tracciabilità completa per l'operatore.
-- F) Esecuzione Flessibile:
--    - Modalità Massiva Schedulata: scansiona gli ordini registrati/modificati negli ultimi @GiorniIndietro (default 15 gg).
--    - Modalità Singolo Documento: se valorizzato @NumDoc (es. 5519), processa esclusivamente quella conferma d'ordine.
--    - Forzatura Reinvio: con @ForzaReinvio = 1, scavalca il controllo di storico e riaccoda tutte le righe a disegno dell'ordine
--      impostando il flag RT13_SOVRASCRIVI = 1, ordinando al robot di rigenerare e sovrascrivere il disegno su disco.
-- G) Modalità Sicura di Default:
--    - Supporta @ModalitaDryRun = 1 per default (regola aurea Progetto TMV), visualizzando un output verboso e analitico
--      senza toccare né sporcare il database prima dell'approvazione esplicita.
--
-- STORICO REVISIONI:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Rev. 0 | 2026-10-23 | SOLVERIS - Bandera Marco
-- Creazione iniziale dell'oggetto a seguito della diagnosi del caso CO 5519 e degli accordi tecnici con Direzione Tecnica TMV.
--
-- Rev. 1 | 2026-10-23 | SOLVERIS - Bandera Marco
-- Evoluzione architetturale a supporto del nuovo Servizio Windows e Monitor Intranet TMV_NKE:
-- 1. Resilienza Delta Engine: raffinata la verifica su RT13_NKE_LOG introducendo il filtro mandatorio RT13_FILE_GENERATO = 1,
--    evitando che tentativi falliti o andati in timeout inibiscano permanentemente la successiva rielaborazione automatica.
-- 2. Tracciabilità 1-a-Molti: integrato il popolamento automatico della tabella ponte [dbo].[RT13_NKE_DOCS_GEMINI], conservando
--    i riferimenti a NumDoc, Riga e Ragione Sociale cliente (da CG44_CLIFOR e CG16_ANAGGEN) per ciascun disegno deduplicato in coda.
--
-- Rev. 2 | 2026-10-23 | SOLVERIS - Bandera Marco
-- Hardening post-review:
-- 1. Risoluzione loop infinito Dead-Letter (Critical-02): in scansione massiva schedulata (@NumDoc IS NULL), gli elementi già a log
--    non vengono re-inoltrati automaticamente per non saturare Inventor. Il recupero di righe fallite (RT13_FILE_GENERATO = 0)
--    avviene quando l'operatore interroga o forza la specifica conferma d'ordine (@NumDoc = ...).
-- 2. Protezione anti-duplicazione su RT13_NKE_DOCS_GEMINI: inserito controllo NOT EXISTS per evitare record duplicati in caso di rilanci forzati multipli.
--
-- Rev. 3 | 2026-10-23 15:50 | SOLVERIS - Bandera Marco
-- Perfezionamento filtro merceologico righe d'ordine:
-- Inserito filtro tassativo 'c.DO30_INDTIPORIGA = 0' nella selezione delle righe corpo (DO30_DOCCORPO).
-- Esclude dal flusso di generazione CAD le righe speciali, descrittive, di spesa o di nota tecnica (DO30_INDTIPORIGA <> 0)
-- che possono occasionalmente recare un codice articolo a 14 caratteri ma che non rappresentano articoli fisici normali.
-- =================================================================================================================================

CREATE OR ALTER PROCEDURE [dbo].[SPSO_NKE_ALIMENTA_CODA_GEMINI]
    @ModalitaDryRun     BIT          = 1,       -- 1 = Simulazione Verbosa (Dry-Run / DryOut), 0 = Scrittura Atomica Reale
    @NumDoc             INT          = NULL,    -- Opzionale: Numero Conferma Ordine da processare (es. 5519). Se NULL, elaborazione massiva
    @AnnoDoc            SMALLINT     = NULL,    -- Opzionale: Anno Documento (se NULL e @NumDoc presente, default anno corrente)
    @SezDoc             VARCHAR(3)   = NULL,    -- Opzionale: Sezionale Documento (se NULL, tutti i sezionali)
    @GiorniIndietro     INT          = 15,      -- Intervallo di lookback temporale (in giorni) per elaborazione massiva schedulata
    @ForzaReinvio       BIT          = 0        -- 1 = Forza riaccodamento anche se già presente in RT13_NKE_LOG (RT13_SOVRASCRIVI = 1)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- =============================================================================================================================
    -- SEZIONE 1: Normalizzazione Parametri di Ingresso e Validazione Contesto
    -- =============================================================================================================================
    IF @AnnoDoc IS NULL AND @NumDoc IS NOT NULL
    BEGIN
        SET @AnnoDoc = YEAR(GETDATE());
    END

    DECLARE @DataLimiteReg DATETIME = DATEADD(DAY, -ABS(@GiorniIndietro), CAST(GETDATE() AS DATE));
    DECLARE @RigheIdentificate INT = 0;
    DECLARE @RigheAccodate INT = 0;

    -- Tabella temporanea per isolare in modo pulito e performante le righe candidate
    IF OBJECT_ID('tempdb..#CandidateNKE') IS NOT NULL
        DROP TABLE #CandidateNKE;

    CREATE TABLE #CandidateNKE (
        IdProg                  INT IDENTITY(1,1) PRIMARY KEY,
        DO11_DITTA_CG18         DECIMAL(18,0) NOT NULL,
        DO11_DOCUM_MG36         VARCHAR(20) NOT NULL,
        DO11_NUMDOC             INT NOT NULL,
        DO11_SEZDOC             VARCHAR(3) NOT NULL,
        DO11_ANNODOC            SMALLINT NOT NULL,
        DO11_DATADOC            DATETIME NOT NULL,
        DO11_CLIFOR_CG44        DECIMAL(18,0) NOT NULL,
        RAGIONE_SOCIALE         VARCHAR(100) NULL,
        DO30_PROGRIGA           INT NOT NULL,
        DO30_GUID               UNIQUEIDENTIFIER NOT NULL,
        DO30_CODART_MG66        CHAR(25) NOT NULL,
        DO30_OPZIONE_MG5E       CHAR(20) NOT NULL,
        MG87_GUID               UNIQUEIDENTIFIER NOT NULL,
        DESCRIZIONE_ART         VARCHAR(1745) NOT NULL,
        CO4C_IDSTATO            INT NOT NULL,
        CO4C_DESCRIZIONE        VARCHAR(100) NOT NULL,
        EsitoDelta              VARCHAR(30) NOT NULL,
        MotivoAzione            VARCHAR(255) NOT NULL
    );

    -- =============================================================================================================================
    -- SEZIONE 2: Estrazione e Isolamento Righe Candidate da Ordini di Vendita
    -- =============================================================================================================================
    -- Si ricercano le righe ordine agganciate a testate attive (TipoDoc = 21: DC-ORDINE / DC-ORDGAR)
    -- il cui stato riga rientra nel ventaglio degli stati confermati / approvati / operativi pre-produzione
    -- concordati con la Direzione Tecnica TMV:
    -- 10046: DIBA Localizzata / Confermato
    -- 10048: Approv.Uff.DIR (Approvazione Direzionale)
    -- 10049: Inviata Mail CLI
    -- 10050: Preso in carico Uff.PRODUZ.
    -- 10051: Ordine di Lavoro Generato
    -- 10054: Mancata Localizzazione DIBA / Ordine a Fornitore
    -- 10055: DIBA Non necessaria
    -- =============================================================================================================================
    INSERT INTO #CandidateNKE (
        DO11_DITTA_CG18,
        DO11_DOCUM_MG36,
        DO11_NUMDOC,
        DO11_SEZDOC,
        DO11_ANNODOC,
        DO11_DATADOC,
        DO11_CLIFOR_CG44,
        RAGIONE_SOCIALE,
        DO30_PROGRIGA,
        DO30_GUID,
        DO30_CODART_MG66,
        DO30_OPZIONE_MG5E,
        MG87_GUID,
        DESCRIZIONE_ART,
        CO4C_IDSTATO,
        CO4C_DESCRIZIONE,
        EsitoDelta,
        MotivoAzione
    )
    SELECT 
        d.DO11_DITTA_CG18,
        d.DO11_DOCUM_MG36,
        d.DO11_NUMDOC,
        d.DO11_SEZDOC,
        d.DO11_ANNODOC,
        d.DO11_DATADOC,
        d.DO11_CLIFOR_CG44,
        anag.CG16_RAGSOANAG,
        c.DO30_PROGRIGA,
        c.DO30_GUID,
        c.DO30_CODART_MG66,
        c.DO30_OPZIONE_MG5E,
        a.MG87_GUID,
        ISNULL(a.MG87_DESCART, '') + ' ' + ISNULL(a.MG87_DESCARTEST, '') AS DESCRIZIONE_ART,
        s.CO4C_IDSTATO,
        s.CO4C_DESCRIZIONE,
        CASE 
            WHEN q.MG87_GUID IS NOT NULL THEN 'IN_CODA'
            -- In scansione massiva schedulata (@NumDoc IS NULL), qualsiasi presenza a log è considerata già gestita
            -- per evitare loop infiniti di righe fallite (Dead-Letter) ogni 10 minuti.
            WHEN l.MG87_GUID IS NOT NULL AND @NumDoc IS NULL THEN 'GIA_A_LOG'
            -- Su singolo ordine mirato (@NumDoc IS NOT NULL):
            -- se già generato con successo (1) e senza forzatura, è ignorato; se fallito in precedenza (0), viene proposto per il reinvio/recupero.
            WHEN l.MG87_GUID IS NOT NULL AND @ForzaReinvio = 0 AND l.RT13_FILE_GENERATO = 1 THEN 'GIA_A_LOG'
            WHEN l.MG87_GUID IS NOT NULL AND @ForzaReinvio = 1 THEN 'DA_REINVIARE_FORZATO'
            ELSE 'DA_INSERIRE_NUOVO'
        END AS EsitoDelta,
        CASE 
            WHEN q.MG87_GUID IS NOT NULL THEN 'Richiesta già presente nella coda di dispatching RT13_NKE'
            WHEN l.MG87_GUID IS NOT NULL AND @NumDoc IS NULL THEN 'Disegno già processato in precedenza (rilevato a log; non re-inoltrato in scansione automatica per prevenire loop)'
            WHEN l.MG87_GUID IS NOT NULL AND @ForzaReinvio = 0 AND l.RT13_FILE_GENERATO = 1 THEN 'Disegno CAD già generato con successo in passato (rilevato in RT13_NKE_LOG con file generato)'
            WHEN l.MG87_GUID IS NOT NULL AND @ForzaReinvio = 1 THEN 'Forzatura operatore: disegno già a log ma re-inoltrato con flag sovrascrittura'
            ELSE 'Nuova combinazione Articolo/Variante mai generata o fallita in precedenza da recuperare'
        END AS MotivoAzione
    FROM dbo.DO11_DOCTESTATA d WITH (NOLOCK)
    INNER JOIN dbo.DO30_DOCCORPO c WITH (NOLOCK)
        ON d.DO11_DITTA_CG18 = c.DO30_DITTA_CG18
        AND d.DO11_NUMREG_CO99 = c.DO30_NUMREG_CO99
    LEFT JOIN dbo.CG44_CLIFOR clifor WITH (NOLOCK)
        ON d.DO11_DITTA_CG18 = clifor.CG44_DITTA_CG18
        AND d.DO11_CLIFOR_CG44 = clifor.CG44_CLIFOR
    LEFT JOIN dbo.CG16_ANAGGEN anag WITH (NOLOCK)
        ON clifor.CG44_CODICE_CG16 = anag.CG16_CODICE
    INNER JOIN dbo.CO4H_STATIATTUALI h WITH (NOLOCK)
        ON c.DO30_GUID = h.CO4H_GUID
    INNER JOIN dbo.CO4C_STATI s WITH (NOLOCK)
        ON h.CO4H_IDSTATO_CO4C = s.CO4C_IDSTATO
        AND s.CO4C_IDENTITA_CO4A = 8  -- Entità 8 = Righe Documenti
    -- Verifica abilitazione tipologia nel configuratore commerciale (CM02_A = 'NKE')
    INNER JOIN dbo.CM02_VALORICATCOMM cat WITH (NOLOCK)
        ON cat.CM02_IDCATEGORIA_CM01 = 1
        AND ISNULL(cat.CM02_A, '') = 'NKE'
        AND SUBSTRING(c.DO30_CODART_MG66, 1, 3) = SUBSTRING(cat.CM02_VALORESTR, 1, 3)
    -- Recupero descriptor univoco articolo/variante (lingua standard '    ')
    INNER JOIN dbo.MG87_ARTDESC a WITH (NOLOCK)
        ON a.MG87_DITTA_CG18 = c.DO30_DITTA_CG18
        AND a.MG87_CODART_MG66 = c.DO30_CODART_MG66
        AND a.MG87_OPZIONE_MG5E = c.DO30_OPZIONE_MG5E
        AND a.MG87_LINGUA_MG52 = '    '
    -- Verifica presenza attiva in coda RT13_NKE
    OUTER APPLY (
        SELECT TOP 1 q1.MG87_GUID
        FROM dbo.RT13_NKE q1 WITH (NOLOCK)
        WHERE q1.MG87_GUID = a.MG87_GUID
    ) q
    -- Verifica storico pregresso in RT13_NKE_LOG (ultimo tentativo registrato)
    OUTER APPLY (
        SELECT TOP 1 l1.MG87_GUID, l1.RT13_FILE_GENERATO
        FROM dbo.RT13_NKE_LOG l1 WITH (NOLOCK)
        WHERE l1.MG87_GUID = a.MG87_GUID
        ORDER BY l1.RT13_DATETIME_LOG DESC
    ) l
    WHERE d.DO11_DITTA_CG18 = 1
      AND d.DO11_DOCUM_MG36 IN ('DC-ORDINE', 'DC-ORDGAR')
      AND d.DO11_TIPODOC = 21
      AND c.DO30_INDTIPORIGA = 0
      AND LEN(TRIM(c.DO30_CODART_MG66)) = 14
      AND s.CO4C_IDSTATO IN (10046, 10048, 10049, 10050, 10051, 10054, 10055)
      AND (
          -- Ramo 1: Esecuzione Mirata su Singolo Documento
          (@NumDoc IS NOT NULL 
           AND d.DO11_NUMDOC = @NumDoc 
           AND (@AnnoDoc IS NULL OR d.DO11_ANNODOC = @AnnoDoc)
           AND (@SezDoc IS NULL OR d.DO11_SEZDOC = @SezDoc))
          OR
          -- Ramo 2: Esecuzione Massiva Schedulata
          (@NumDoc IS NULL 
           AND (d.DO11_DATADOC >= @DataLimiteReg OR d.DO11_LASTCHANGE >= @DataLimiteReg))
      )
    OPTION (RECOMPILE);

    SELECT @RigheIdentificate = COUNT(*) FROM #CandidateNKE;

    -- =============================================================================================================================
    -- SEZIONE 3: Modalità Operativa Dry-Run (Simulazione e Reporting Verboso)
    -- =============================================================================================================================
    IF @ModalitaDryRun = 1
    BEGIN
        SELECT 
            'DRYOUT VERBOSO - SIMULAZIONE ALIMENTAZIONE CODA NKE' AS [STATO OPERATIVO],
            @RigheIdentificate AS [Righe Ordine Analizzate],
            ISNULL(SUM(CASE WHEN EsitoDelta IN ('DA_INSERIRE_NUOVO', 'DA_REINVIARE_FORZATO') THEN 1 ELSE 0 END), 0) AS [Righe da Accodare in RT13_NKE],
            ISNULL(SUM(CASE WHEN EsitoDelta = 'GIA_A_LOG' THEN 1 ELSE 0 END), 0) AS [Righe Già a Log (Ignorate)],
            ISNULL(SUM(CASE WHEN EsitoDelta = 'IN_CODA' THEN 1 ELSE 0 END), 0) AS [Righe Già in Coda Attiva]
        FROM #CandidateNKE;

        -- Dettaglio analitico riga per riga per trasparenza totale verso l'operatore
        SELECT 
            DO11_NUMDOC         AS [Num Ordine],
            DO11_SEZDOC         AS [Sez],
            DO11_ANNODOC        AS [Anno],
            CONVERT(VARCHAR(10), DO11_DATADOC, 103) AS [Data Ordine],
            RAGIONE_SOCIALE     AS [Cliente],
            DO30_PROGRIGA       AS [Prog Riga],
            DO30_CODART_MG66    AS [Codice Articolo],
            DO30_OPZIONE_MG5E   AS [Variante],
            CO4C_IDSTATO        AS [ID Stato],
            CO4C_DESCRIZIONE    AS [Descrizione Stato Riga],
            MG87_GUID           AS [GUID Descriptor Articolo],
            EsitoDelta          AS [Esito Delta],
            MotivoAzione        AS [Motivazione Operativa],
            DESCRIZIONE_ART     AS [Descrizione Estesa]
        FROM #CandidateNKE
        ORDER BY DO11_NUMDOC, DO30_PROGRIGA;

        RETURN;
    END

    -- =============================================================================================================================
    -- SEZIONE 4: Modalità Esecutiva Reale (Scrittura Atomica e Transazionale)
    -- =============================================================================================================================
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Inserimento nella coda RT13_NKE solo delle righe che necessitano di effettivo invio verso il robot
        -- Deduplicazione automatica per MG87_GUID: se lo stesso articolo/variante compare in più righe d'ordine,
        -- viene inserito in coda una sola volta per ottimizzare il carico del robot NKE.
        INSERT INTO dbo.RT13_NKE (
            RT13_GUID,
            RT13_DITTA_CG18,
            RT13_CODART_MG66,
            RT13_OPZIONE_MG5E,
            RT13_LINGUA_MG52,
            MG87_GUID,
            DESCRIZIONE,
            RT13_INSERT_DATETIME,
            RT13_CALL_DATETIME,
            RT13_SOVRASCRIVI,
            RT13_FILE_GENERATO,
            RT13_NUM_TENTATIVI
        )
        SELECT 
            NEWID()                         AS RT13_GUID,
            c.DO11_DITTA_CG18               AS RT13_DITTA_CG18,
            c.DO30_CODART_MG66              AS RT13_CODART_MG66,
            c.DO30_OPZIONE_MG5E             AS RT13_OPZIONE_MG5E,
            '    '                          AS RT13_LINGUA_MG52,
            c.MG87_GUID                     AS MG87_GUID,
            c.DESCRIZIONE_ART               AS DESCRIZIONE,
            GETDATE()                       AS RT13_INSERT_DATETIME,
            NULL                            AS RT13_CALL_DATETIME,
            CASE WHEN c.EsitoDelta = 'DA_REINVIARE_FORZATO' THEN 1 ELSE 0 END AS RT13_SOVRASCRIVI,
            0                               AS RT13_FILE_GENERATO,
            0                               AS RT13_NUM_TENTATIVI
        FROM #CandidateNKE c
        WHERE c.EsitoDelta IN ('DA_INSERIRE_NUOVO', 'DA_REINVIARE_FORZATO')
        GROUP BY 
            c.DO11_DITTA_CG18,
            c.DO30_CODART_MG66,
            c.DO30_OPZIONE_MG5E,
            c.MG87_GUID,
            c.DESCRIZIONE_ART,
            c.EsitoDelta;

        SET @RigheAccodate = @@ROWCOUNT;

        -- Popolamento della tabella di tracciabilità 1-a-Molti RT13_NKE_DOCS_GEMINI
        -- Memorizza la correlazione tra MG87_GUID e ciascuna singola riga d'ordine/cliente da cui origina il disegno
        INSERT INTO dbo.RT13_NKE_DOCS_GEMINI (
            MG87_GUID,
            DO11_DITTA_CG18,
            DO11_DOCUM_MG36,
            DO11_NUMDOC,
            DO11_SEZDOC,
            DO11_ANNODOC,
            DO11_DATADOC,
            DO30_PROGRIGA,
            DO30_CODART_MG66,
            DO30_OPZIONE_MG5E,
            RAGIONE_SOCIALE,
            DATA_INSERIMENTO
        )
        SELECT 
            c.MG87_GUID,
            c.DO11_DITTA_CG18,
            c.DO11_DOCUM_MG36,
            c.DO11_NUMDOC,
            c.DO11_SEZDOC,
            c.DO11_ANNODOC,
            c.DO11_DATADOC,
            c.DO30_PROGRIGA,
            c.DO30_CODART_MG66,
            c.DO30_OPZIONE_MG5E,
            c.RAGIONE_SOCIALE,
            GETDATE()
        FROM #CandidateNKE c
        WHERE c.EsitoDelta IN ('DA_INSERIRE_NUOVO', 'DA_REINVIARE_FORZATO')
          AND NOT EXISTS (
              SELECT 1 FROM dbo.RT13_NKE_DOCS_GEMINI doc WITH (NOLOCK)
              WHERE doc.MG87_GUID = c.MG87_GUID
                AND doc.DO11_NUMDOC = c.DO11_NUMDOC
                AND doc.DO30_PROGRIGA = c.DO30_PROGRIGA
          );

        COMMIT TRANSACTION;

        -- Notifica sintetica di successo
        SELECT 
            'ESECUZIONE COMPLETATA CON SUCCESSO' AS [STATO OPERATIVO],
            @RigheIdentificate AS [Righe Ordine Analizzate],
            @RigheAccodate AS [Nuove Richieste Accodate in RT13_NKE],
            GETDATE() AS [Momento Esecuzione];

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR('Errore critico durante l''alimentazione della coda RT13_NKE: %s', @ErrorSeverity, @ErrorState, @ErrorMessage);
    END CATCH
END;
GO
