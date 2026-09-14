USE [DBTMV]
GO

/****** Object:  StoredProcedure [dbo].[SPSO_AGGIORNA_STATI_RIGA_GEMINI]    Script Date: 14/09/2026 13:10:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[SPSO_AGGIORNA_STATI_RIGA_GEMINI]
/*
========================================================================================================================
1 - DATA E ORA REVISIONE: 2026-09-14 13:10
2 - AUTORE              : SOLVERIS - Bandera Marco
3 - OGGETTO             : Stored Procedure [dbo].[SPSO_AGGIORNA_STATI_RIGA_GEMINI]
4 - AMBIENTE DI TARGET  : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database DBTMV
------------------------------------------------------------------------------------------------------------------------
5 - DESCRIZIONE AD ALTISSIMO DETTAGLIO (CONTESTO AZIENDALE, LOGICO E ARCHITETTURALE):
    Questa Stored Procedure costituisce il MOTORE CENTRALE (CORE ENGINE) per il monitoraggio, il ricalcolo e
    l'aggiornamento transazionale dello stato di avanzamento delle singole righe di Impegno/Ordine Cliente (CO4H)
    all'interno del sistema ERP/MES aziendale di TMV.

    Nel contesto operativo aziendale, un Impegno Cliente (TipoDoc = 21) attraversa un ciclo di vita complesso, articolato
    e fortemente distribuito, che coinvolge molteplici reparti e sistemi eterogenei:
      a) L'Ufficio Tecnico e Programmazione della Produzione, che analizza la Distinta Base (DIBA) ed emette l'Ordine
         di Lavoro interno (ODL, TipoDoc = 24).
      b) L'Officina Meccanica e i Centri di Lavoro MES interni, che registrano in tempo reale gli avanzamenti intermedi
         sulle singole fasi tecnologiche (tornitura, fresatura, rettifica, rullatura, ecc.) mediante terminali a bordo macchina.
      c) I Reparti di Collaudo e Controllo Qualità (Fase 4031), deputati alla certificazione dimensionale e conformità.
      d) La Logistica Esterna per le lavorazioni speciali affidate a Fornitori/Terzisti (Trattamenti Termici, Galvanica,
         Verniciatura), monitorata mediante DDT di Conto Lavoro (TipoDoc = 25, STipoDoc = 13) e relative fasi di rientro/smistamento.
      e) Il Reparto Imballo e Versamento (Fase 6000 - RTP / Ready To Package), che sancisce il completamento della produzione.
      f) Il Magazzino Spedizioni, che effettua il prelievo fisico tramite Packing List (PKL, TipoDoc = 9, STipoDoc = 1),
         l'eventuale emissione dell'Avviso di Merce Pronta (AMP, TipoDoc = 2) per comunicare al cliente o spedizioniere la merce pronta,
         e infine la Spedizione definitiva tramite DDT (TipoDoc = 1) o Fattura Accompagnatoria (TipoDoc = 5, STipoDoc = 2).

    La principale criticità risolta da questa procedura risiede nel disallineamento temporale e logico tra gli eventi:
    in una fabbrica reale accadono avanzamenti tardivi, inserimenti retrodatati da parte degli operatori MES, rettifiche,
    cancellazioni di documenti logistici intermedi, gestioni particolari con transito a magazzini di deposito (DDT collegati)
    e articoli fittizi/descrittivi che non hanno un proprio ciclo produttivo ma seguono "a rimorchio" le righe principali.

    ARCHITETTURA DEL MOTORE DI CALCOLO IN 4 FASI:
      - FASE 1 (Target & Protezioni): Isola le righe d'ordine attive da analizzare escludendo a monte gli stati "terminali"
        e i "Porti Sicuri" (Safe Harbors come 10055 - DIBA Non Necessaria), pre-materializzando i dati ODL e DDT in tabelle
        temporanee indicizzate per garantire tempi di risposta fulminei anche su archivi storici massivi.
      - FASE 2 (Matrice dei Candidati): Applica in modo parallelo e non esclusivo le 14 Regole di Business (Regole 01-13B e 99).
        Ogni regola valuta le evidenze documentali (ODL, avanzamenti MES DO57, DDT c/lavoro, versamenti RTP, PKL, AMP, DDT di vendita)
        e propone uno o più "Stati Candidati", corredati ciascuno da una precisa DataEvento e da un indice di Priorità.
      - FASE 3 (Ranking e Risoluzione Conflitti): Risolve ogni ambiguità applicando una funzione analitica di finestra:
            ROW_NUMBER() OVER (PARTITION BY DO30_GUID ORDER BY DataEvento DESC, PrioritaSequenza DESC)
        In questo modo vince sempre l'evento cronologicamente più recente. Nel caso in cui due eventi si verifichino nella
        stessa identica data, il pareggio viene sciolto determinando quale fase si trovi più a valle nel flusso logico (Priorità).
      - FASE 4 (DryOut Verboso vs Scrittura Transazionale): Consente sia una simulazione verbosa trasparente (Dry-Run per
        diagnostica su singola riga o massiva senza sporcare il DB), sia l'aggiornamento transazionale atomico (BEGIN TRAN/COMMIT)
        protetto da vincoli di concorrenza e blocchi tramite l'uso diffuso di letture senza lock (WITH (NOLOCK)).

------------------------------------------------------------------------------------------------------------------------
6 - STORICO COMPLETO DELLE REVISIONI (CHANGE LOG NARRATIVO SENZA TRONCAMENTI):
    - Rev. 1-13 : Versioni iniziali consolidate. Ottimizzazione FASE 1 di materializzazione, introduzione del CROSS APPLY
                  per la navigazione gerarchica dell'albero documentale, eliminazione cursori lenti, introduzione di RAISERROR
                  WITH NOWAIT per feedback a terminale in streaming.
    - Rev. 14   : RISOLUZIONE PRODOTTO CARTESIANO. Ristrutturazione radicale delle logiche di evasione multi-livello su DO33.
                  La moltiplicazione di righe causata da evasioni parziali multiple generava conteggi errati di quantità e date;
                  l'introduzione di aggregazioni esplicite raggruppate per riga d'ordine ha eliminato duplicazioni e colli di bottiglia.
    - Rev. 15   : STESURA DOCUMENTAZIONE IN-CODE. Inserimento delle sintesi tecniche e prime guide all'handover per manutentori.
    - Rev. 16   : GESTIONE FAKE ODL PROCESS. Integrazione della Regola 09B. Nel modello produttivo aziendale, per alcune tipologie
                  di articoli viene creata una sequenza transitoria virtuale nello storico (10046 -> 10079 -> 10052) senza la
                  presenza di un ODL fisico con fase 6000. Introdotto il riconoscimento preventivo di questo pattern per non
                  declassare la riga e mantenerla stabilmente a 10052.
    - Rev. 17   : GESTIONE SPEDITO PARZIALE (10084). Evoluzione della Regola 13. Quando un DDT evade solo una quota della riga
                  ordine (Qta DDT < Qta Riga), lo stato non può essere considerato Spedito Totale (10053), bensì deve assumere
                  lo stato distinto 10084 per consentire al reparto commerciale di monitorare i residui inevasi.
    - Rev. 18   : GESTIONE ROLLBACK (PARACADUTE ORFANI). Aggiunta prima bozza di ripristino per righe il cui documento a valle
                  (es. ODL o DDT) era stato cancellato o eliminato dall'utente senza ripulire la tabella CO4H.
    - Rev. 19   : DATA RANKING FASI INTERNE. Modificata la valorizzazione temporale per la Regola 02 (In Produzione), 03 (Collaudo),
                  04 (Attesa C/Lav), 07 (Rientro) e 08 (Smistato). In precedenza veniva assunta la data dell'ODL; introdotto l'uso
                  di MAX(ADV.DO57_DATAMOV) per allineare l'istante dell'evento alla data reale dell'avanzamento registrato dal MES.
    - Rev. 20   : DATA RANKING RTP E FAKE ODL. Estesa la rilevazione di DO57_DATAMOV anche per la Regola 09 (RTP / Fase 6000) e
                  per il Fake ODL, garantendo coerenza cronologica nel ranking finale.
    - Rev. 21   : UNIVERSAL ROLLBACK (SAFETY NET). Consolidamento della Regola 99 come "paracadute universale": per qualsiasi riga
                  orfana che non soddisfi più alcuna regola documentale attiva, la procedura esamina lo storico CO4I e ripristina
                  l'ultimo stato valido conosciuto antecedente.
    - Rev. 22   : FIX ROLLBACK RTP (PORTO SICURO 10052). Risolto un effetto collaterale della Regola 99: le righe in stato 10052
                  (RTP) prive di movimenti recenti venivano impropriamente retrocesse dalla Regola 99. Stato 10052 blindato
                  come porto sicuro non retrocedibile in assenza di regole vincenti.
    - Rev. 23   : FIX ARTICOLI FITTIZI E NOTE SU PKL. Riscrizione della Regola 11 mediante CROSS APPLY referenziale a tre livelli
                  su DO33_DOCCORPORIF, consentendo agli articoli descrittivi e fittizi (spese trasporto, imballi speciali) privi di
                  ODL di ereditare lo stato di Packing List (10063) dalla riga madre dell'impegno cliente.
    - Rev. 24   : ESCLUSIONI AVANZATE E SAFE HARBORS (10079, 10054, 10068). Estensione della blindatura della Regola 99 agli stati
                  di conto lavoro esterno e ordini fornitore, prevenendo regressioni spurie causate da disallineamenti di date.
    - Rev. 25   : ENGINE DIAGNOSTICO DI DROPOUT (FASE 1). Inserimento di un blocco di controllo diagnostico verboso: quando la SP
                  viene eseguita con parametri di debug per una specifica riga che viene scartata a monte nella FASE 1, il sistema
                  stampa a video le motivazioni puntuali dello scarto (es. tipo riga descrittiva pura, stato terminale, tipo doc errato).
    - Rev. 26   : INTEGRAZIONE SAFE HARBOR 10055 (DIBA NON NECESSARIA). Esclusione esplicita e totale dello stato 10055 dall'elaborazione
                  di Fase 1, censimento dell'esclusione nella diagnostica di Dropout e blindatura nella Regola 99.
    - Rev. 27   : ANTI-REGRESSIONE MES E DDT DA DEPOSITO (INTERVENTO CORRENTE).
                  * Problema Risolto 1 (Avanzamenti MES Tardivi): Intercettato il caso in cui operatori MES inseriscano avancamenti
                    tardivi su fasi intermedie (es. rullatura) dopo che l'ODL è già stato versato a magazzino (Fase 6000 consolidata)
                    o la riga d'ordine cliente è già stata completamente evasa e spedita. Inserite nella Regola 02 (In Produzione)
                    quattro stringenti clausole di salvaguardia che inibiscono l'assegnazione dello stato 10073 se la riga è già
                    avanzata (>= 10063), se l'impegno è evaso (DO72_FLGEVASO = 1), se la fase 6000 è completata, o se l'ODL è chiuso.
                  * Problema Risolto 2 (Catena DDT da Magazzino Deposito): Estese le Regole 13 e 13B con un quarto ramo UNION ALL
                    in grado di navigare la catena documentale generata da Fatture Accompagnatorie collegate a Buoni Carico Deposito
                    (DC-DDTCARDEPCL) tramite DO11_NUMREGCOL_CO99 e da questi ai DDT definitivi di spedizione (DC-DDTCLIDC). Inserita
                    clausola NOT EXISTS nel ramo fattura per neutralizzare duplicazioni di quantità e assumere la data di consegna effettiva.
========================================================================================================================
*/
    @ModalitaDryRun BIT = 0,            -- PARAMETRO DI SICUREZZA: 1 = Solo simulazione diagnostica (DryOut), 0 = Scrittura reale a DB
    @DebugDitta INT = NULL,             -- PARAMETRO DI FOCUS: ID Ditta dell'Impegno Cliente da analizzare (es. 1)
    @DebugNumReg VARCHAR(30) = NULL,    -- PARAMETRO DI FOCUS: Numero Registrazione ERP dell'Impegno Cliente (DO30_NUMREG_CO99)
    @DebugRiga INT = NULL               -- PARAMETRO DI FOCUS: Progressivo Riga interno dell'Impegno Cliente (DO30_PROGRIGA)
AS
BEGIN
    -- Disattivazione dell'invio dei messaggi DONE_IN_PROC per ogni singola istruzione, riducendo l'overhead di rete
    SET NOCOUNT ON;
    
    -- XACT_ABORT ON garantisce che, in caso di errore di runtime a livello di istruzione T-SQL, l'intera transazione venga abortita e rolltata
    SET XACT_ABORT ON;

    DECLARE @ErroreMessaggio NVARCHAR(4000);
    DECLARE @InizioEsecuzione DATETIME2 = SYSDATETIME();
    DECLARE @FineEsecuzione DATETIME2;
    DECLARE @TargetGUID UNIQUEIDENTIFIER = NULL;

    -- =================================================================================================================
    -- INTERCETTAZIONE DEI PARAMETRI DI DEBUG E DETERMINAZIONE DEL TARGET
    -- =================================================================================================================
    -- Se l'utente ha passato una specifica tripletta (Ditta, NumReg, ProgRiga), la procedura entra in modalità FOCUS:
    -- invece di elaborare l'intero parco ordini a sistema, materializza il GUID univoco della riga e circoscrive l'analisi,
    -- consentendo di tracciare con precisione chirurgica le singole regole scattate e i punteggi del ranking.
    IF @DebugDitta IS NOT NULL AND @DebugNumReg IS NOT NULL AND @DebugRiga IS NOT NULL
    BEGIN
        SELECT @TargetGUID = DO30_GUID 
        FROM dbo.DO30_DOCCORPO WITH (NOLOCK)
        WHERE DO30_DITTA_CG18 = @DebugDitta 
          AND DO30_NUMREG_CO99 = @DebugNumReg 
          AND DO30_PROGRIGA = @DebugRiga;

        IF @TargetGUID IS NULL
        BEGIN
            PRINT 'ATTENZIONE [DIAGNOSTICA]: Riga di test non trovata in DO30_DOCCORPO. Verificare Ditta/NumReg/Riga.';
            RETURN;
        END
        RAISERROR('--- MODALITA FOCUS ATTIVA SULLA RIGA SELEZIONATA ---', 10, 1) WITH NOWAIT;
    END

    BEGIN TRY
        -- =============================================================================================================
        -- FASE 1: MATERIALIZZAZIONE TARGET, APPLICAZIONE DEI FILTRI DI INCLUSIONE/ESCLUSIONE E PRE-COMPUTAZIONI
        -- =============================================================================================================
        -- Questa fase è progettata per massimizzare le performance ed eliminare a monte i ricalcoli inutili.
        -- Seleziona le sole righe d'ordine che necessitano di avanzamento o rettifica, applicando rigorose regole di
        -- salvaguardia per gli stati terminali e i porti sicuri.
        RAISERROR('>> Inizio FASE 1: Materializzazione #TargetGUIDs ed estrazione base dati...', 10, 1) WITH NOWAIT;

        -- Tabella temporanea per i GUID target da elaborare
        CREATE TABLE #TargetGUIDs (
            CO4H_GUID UNIQUEIDENTIFIER PRIMARY KEY,
            CO4H_IDSTATO_CO4C INT
        );

        -- Inserimento delle righe ordini escludendo gli stati terminali consolidati:
        -- - 10053: Spedito Totale (fatte salve le eccezioni con residuo inevaso gestite sotto)
        -- - 10068: Riga Annullata (stato terminale irreversibile da processo gestionale)
        -- - 10055: DIBA NON NECESSARIA (Porto Sicuro: la riga non deve generare produzione, non va alterata)
        INSERT INTO #TargetGUIDs (CO4H_GUID, CO4H_IDSTATO_CO4C)
        SELECT CO4H_GUID, CO4H_IDSTATO_CO4C
        FROM dbo.CO4H_STATIATTUALI WITH (NOLOCK)
        WHERE CO4H_IDSTATO_CO4C NOT IN (10053, 10068, 10055); 

        -- Inserimento condizionale di salvaguardia per righe attualmente marcate a 10053 (Spedito Totale),
        -- ma che presentano un residuo logico o gestionale ancora aperto:
        -- 1) Righe con tipologia speciale (kit, spese, descrittive collegate: tipi 2, 4, 6, 8)
        -- 2) Righe che in DO72_DOCCORPOSTATO risultano ancora con flag da evadere acceso (DO72_FLGDAEVADERE = 1)
        INSERT INTO #TargetGUIDs (CO4H_GUID, CO4H_IDSTATO_CO4C)
        SELECT A.CO4H_GUID, A.CO4H_IDSTATO_CO4C
        FROM dbo.CO4H_STATIATTUALI A WITH (NOLOCK)
        INNER JOIN dbo.DO30_DOCCORPO C WITH (NOLOCK) ON A.CO4H_GUID = C.DO30_GUID
        WHERE A.CO4H_IDSTATO_CO4C = 10053 
          AND NOT EXISTS (SELECT 1 FROM #TargetGUIDs T WITH (NOLOCK) WHERE T.CO4H_GUID = A.CO4H_GUID) 
          AND (
               C.DO30_INDTIPORIGA IN (2, 4, 6, 8) 
               OR EXISTS (
                   SELECT 1 FROM dbo.DO72_DOCCORPOSTATO S WITH (NOLOCK)
                   WHERE S.DO72_DITTA_CG18 = C.DO30_DITTA_CG18 
                     AND S.DO72_NUMREG_CO99 = C.DO30_NUMREG_CO99 
                     AND S.DO72_PROGRIGA = C.DO30_PROGRIGA
                     AND S.DO72_FLGDAEVADERE = 1
               )
          );

        -- Identificazione preventiva dei casi speciali "Fake ODL Process" (Regola 09B / Rev. 16):
        -- Per alcuni codici articolo gestiti con flussi produttivi virtuali, nello storico (CO4I) si riscontra
        -- la sequenza esatta: 10046 (Inserito) -> 10079 (C/Lav virtuale) -> 10052 (RTP).
        -- Identifichiamo questi GUID in una temp table per bypassare l'assenza della fase 6000 fisica.
        CREATE TABLE #HistoryBypass (CO4I_GUID UNIQUEIDENTIFIER PRIMARY KEY);
        
        ;WITH HistoryRank AS (
            SELECT S.CO4I_GUID, S.CO4I_IDSTATO_CO4C,
                   LEAD(S.CO4I_IDSTATO_CO4C, 1) OVER (PARTITION BY S.CO4I_GUID ORDER BY S.CO4I_ID) as S_Next1,
                   LEAD(S.CO4I_IDSTATO_CO4C, 2) OVER (PARTITION BY S.CO4I_GUID ORDER BY S.CO4I_ID) as S_Next2
            FROM dbo.CO4I_STATISTORICO S WITH (NOLOCK)
            INNER JOIN #TargetGUIDs TG ON S.CO4I_GUID = TG.CO4H_GUID
        )
        INSERT INTO #HistoryBypass (CO4I_GUID)
        SELECT DISTINCT CO4I_GUID
        FROM HistoryRank
        WHERE CO4I_IDSTATO_CO4C = 10046 AND S_Next1 = 10079 AND S_Next2 = 10052;

        -- Materializzazione della struttura dati centrale della riga (#BaseDatiRiga):
        -- Contiene tutti gli attributi identificativi dell'Impegno Cliente (OC) e, se presente, dell'Ordine di Lavoro (ODL)
        -- ad esso associato. L'ODL viene agganciato tramite OUTER APPLY gerarchico escludendo rigorosamente ODL annullati
        -- (DO31_INDSTATOCONS = 9) e privilegiando l'ODL con data più recente.
        CREATE TABLE #BaseDatiRiga (
            DO30_GUID UNIQUEIDENTIFIER NOT NULL, 
            DO30_DITTA_CG18_OC INT, 
            DO30_NUMREG_CO99_OC VARCHAR(30) COLLATE DATABASE_DEFAULT, 
            DO30_PROGRIGA_OC INT,
            DO11_NUMDOC_OC INT, 
            DO11_SEZDOC_OC VARCHAR(10) COLLATE DATABASE_DEFAULT, 
            DO30_PROGVISUASTA_OC INT,
            DO11_DATADOC_OC DATETIME, 
            CO4H_IDSTATO_CO4C_ATTUALE INT,
            DO30_DITTA_CG18_ODL INT, 
            DO30_NUMREG_CO99_ODL VARCHAR(30) COLLATE DATABASE_DEFAULT, 
            DO30_PROGRIGA_ODL INT,
            DO11_DOCUM_MG36_ODL VARCHAR(50) COLLATE DATABASE_DEFAULT, 
            DO11_DATADOC_ODL DATETIME,
            FLG_FAKE_ODL BIT DEFAULT 0
        );

        INSERT INTO #BaseDatiRiga
        SELECT 
            C.DO30_GUID, C.DO30_DITTA_CG18, C.DO30_NUMREG_CO99, C.DO30_PROGRIGA,
            T.DO11_NUMDOC, T.DO11_SEZDOC, C.DO30_PROGVISUASTA, T.DO11_DATADOC,
            TG.CO4H_IDSTATO_CO4C,
            ODL.DO30_DITTA_CG18, ODL.DO30_NUMREG_CO99, ODL.DO30_PROGRIGA,
            ODL.DO11_DOCUM_MG36, ODL.DO11_DATADOC,
            CASE WHEN HB.CO4I_GUID IS NOT NULL THEN 1 ELSE 0 END
        FROM #TargetGUIDs TG
        INNER JOIN dbo.DO30_DOCCORPO C WITH (NOLOCK) ON TG.CO4H_GUID = C.DO30_GUID
        INNER JOIN dbo.DO11_DOCTESTATA T WITH (NOLOCK) ON T.DO11_DITTA_CG18 = C.DO30_DITTA_CG18 AND T.DO11_NUMREG_CO99 = C.DO30_NUMREG_CO99
        LEFT JOIN #HistoryBypass HB ON HB.CO4I_GUID = C.DO30_GUID
        OUTER APPLY (
            SELECT TOP 1 
                C_ODL.DO30_DITTA_CG18, C_ODL.DO30_NUMREG_CO99, C_ODL.DO30_PROGRIGA,
                T_ODL.DO11_DOCUM_MG36, T_ODL.DO11_DATADOC
            FROM dbo.DO33_DOCCORPORIF R WITH (NOLOCK)
            INNER JOIN dbo.DO30_DOCCORPO C_ODL WITH (NOLOCK) ON R.DO33_DITTA_CG18 = C_ODL.DO30_DITTA_CG18 AND R.DO33_NUMREG_CO99 = C_ODL.DO30_NUMREG_CO99 AND R.DO33_PROGRIGA = C_ODL.DO30_PROGRIGA
            INNER JOIN dbo.DO31_DOCCORPOORD O_ODL WITH (NOLOCK) ON C_ODL.DO30_DITTA_CG18 = O_ODL.DO31_DITTA_CG18 AND C_ODL.DO30_NUMREG_CO99 = O_ODL.DO31_NUMREG_CO99 AND C_ODL.DO30_PROGRIGA = O_ODL.DO31_PROGRIGA
            INNER JOIN dbo.DO11_DOCTESTATA T_ODL WITH (NOLOCK) ON C_ODL.DO30_DITTA_CG18 = T_ODL.DO11_DITTA_CG18 AND C_ODL.DO30_NUMREG_CO99 = T_ODL.DO11_NUMREG_CO99
            WHERE R.DO33_DITTA_CG18 = C.DO30_DITTA_CG18 
              AND R.DO33_NUMREGRIF_CO99 = C.DO30_NUMREG_CO99 
              AND R.DO33_PROGRIGARIF_DO30 = C.DO30_PROGRIGA
              AND O_ODL.DO31_INDSTATOCONS <> 9 -- Scarto ODL Annullato
              AND T_ODL.DO11_TIPODOC = 24       -- Ordine di Lavoro Produzione
            ORDER BY T_ODL.DO11_DATADOC DESC, T_ODL.DO11_NUMDOC DESC
        ) AS ODL
        WHERE T.DO11_TIPODOC = 21                -- Solo Impegni Clienti
          AND C.DO30_INDTIPORIGA IN (0, 2, 4, 6, 8) -- Solo righe merce, kit o descrittive con valore contabile
          AND (@TargetGUID IS NULL OR C.DO30_GUID = @TargetGUID)
        OPTION (FORCE ORDER);

        -- =============================================================================================================
        -- ENGINE DIAGNOSTICO DI DROPOUT (Rev. 25 & 26)
        -- =============================================================================================================
        -- Se l'operatore esegue la procedura in modalità DEBUG puntando ad una riga specifica che viene scartata
        -- dai filtri iniziali della FASE 1, questo blocco esegue una diagnosi in tempo reale ed elenca con precisione
        -- il motivo gestionale dello scarto, evitando perdite di tempo e disorientamento per chi collauda.
        IF @TargetGUID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #BaseDatiRiga WHERE DO30_GUID = @TargetGUID)
        BEGIN
            PRINT '-----------------------------------------------------------------------------------------------------';
            PRINT 'ATTENZIONE [DIAGNOSTICA]: La riga target è presente a DB ma SCARTATA dai criteri di inclusione FASE 1.';
            PRINT 'Dettaglio analitico delle cause di esclusione rilevate:';
            PRINT '-----------------------------------------------------------------------------------------------------';

            SELECT 
                C.DO30_GUID,
                T.DO11_TIPODOC AS [Tipo Doc (Atteso 21)],
                C.DO30_INDTIPORIGA AS [Tipo Riga (Attesi 0,2,4,6,8)],
                STATI.CO4H_IDSTATO_CO4C AS [Stato Attuale],
                CASE 
                    WHEN STATI.CO4H_GUID IS NULL THEN 'Riga mancante nella tabella CO4H_STATIATTUALI (Non ancora inizializzata)'
                    WHEN STATI.CO4H_IDSTATO_CO4C = 10068 THEN 'Esclusa: Stato 10068 (Riga Annullata) - Stato terminale non modificabile'
                    WHEN STATI.CO4H_IDSTATO_CO4C = 10055 THEN 'Esclusa: Stato 10055 (DIBA NON NECESSARIA) - Porto Sicuro da non ricalcolare'
                    WHEN STATI.CO4H_IDSTATO_CO4C = 10053 AND C.DO30_INDTIPORIGA NOT IN (2,4,6,8) 
                         AND NOT EXISTS (SELECT 1 FROM dbo.DO72_DOCCORPOSTATO S WITH (NOLOCK) WHERE S.DO72_DITTA_CG18 = C.DO30_DITTA_CG18 AND S.DO72_NUMREG_CO99 = C.DO30_NUMREG_CO99 AND S.DO72_PROGRIGA = C.DO30_PROGRIGA AND S.DO72_FLGDAEVADERE = 1)
                         THEN 'Esclusa: Stato 10053 (Spedito Totale) consolidato senza quote inevase residue in DO72'
                    WHEN T.DO11_TIPODOC <> 21 THEN 'Esclusa: Il documento di testata non è un Impegno Cliente (TipoDoc <> 21)'
                    WHEN C.DO30_INDTIPORIGA NOT IN (0, 2, 4, 6, 8) THEN 'Esclusa: Tipo Riga puramente descrittivo/nota senza rilevanza logistica'
                    ELSE 'Esclusione generica: verificare integrità referenziale tra DO11 e DO30'
                END AS MotivoEsclusioneFase1
            FROM dbo.DO30_DOCCORPO C WITH (NOLOCK)
            INNER JOIN dbo.DO11_DOCTESTATA T WITH (NOLOCK) ON T.DO11_DITTA_CG18 = C.DO30_DITTA_CG18 AND T.DO11_NUMREG_CO99 = C.DO30_NUMREG_CO99
            LEFT JOIN dbo.CO4H_STATIATTUALI STATI WITH (NOLOCK) ON STATI.CO4H_GUID = C.DO30_GUID
            WHERE C.DO30_GUID = @TargetGUID;

            -- Cleanup preventivo e interruzione controllata del flusso diagnostico
            IF OBJECT_ID('tempdb..#TargetGUIDs') IS NOT NULL DROP TABLE #TargetGUIDs;
            IF OBJECT_ID('tempdb..#HistoryBypass') IS NOT NULL DROP TABLE #HistoryBypass;
            IF OBJECT_ID('tempdb..#BaseDatiRiga') IS NOT NULL DROP TABLE #BaseDatiRiga;
            RETURN;
        END

        -- Creazione dell'indice cluster per accelerare le join nelle successive regole della Fase 2
        CREATE CLUSTERED INDEX IX_BaseDati_GUID ON #BaseDatiRiga (DO30_GUID);

        -- Pre-materializzazione e indicizzazione delle date dei DDT di Conto Lavoro (TipoDoc = 25, STipoDoc = 13):
        -- Raccoglie la data di emissione del documento di uscita per lavorazione esterna attraversando l'albero
        -- referenziale ODL -> Ordine Fornitore -> DDT Conto Lavoro. L'estrazione anticipata evita scansioni ripetute
        -- nelle Regole 05 e 06.
        CREATE TABLE #DateDDT (
            DO30_DITTA_CG18_OC INT, 
            DO30_NUMREG_CO99_OC VARCHAR(30) COLLATE DATABASE_DEFAULT, 
            DO30_PROGRIGA_OC INT, 
            DATA_DDT DATETIME
        );
        INSERT INTO #DateDDT
        SELECT C_OC.DO30_DITTA_CG18, C_OC.DO30_NUMREG_CO99, C_OC.DO30_PROGRIGA, MAX(T_DDT.DO11_DATADOC)
        FROM dbo.DO30_DOCCORPO C_OC WITH (NOLOCK)
        INNER JOIN dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) ON C_OC.DO30_DITTA_CG18 = R1.DO33_DITTA_CG18 AND C_OC.DO30_NUMREG_CO99 = R1.DO33_NUMREGRIF_CO99 AND C_OC.DO30_PROGRIGA = R1.DO33_PROGRIGARIF_DO30
        INNER JOIN dbo.DO30_DOCCORPO C_ODL WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = C_ODL.DO30_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = C_ODL.DO30_NUMREG_CO99 AND R1.DO33_PROGRIGA = C_ODL.DO30_PROGRIGA
        INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON C_ODL.DO30_DITTA_CG18 = R2.DO33_DITTA_CG18 AND C_ODL.DO30_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND C_ODL.DO30_PROGRIGA = R2.DO33_PROGRIGARIF_DO30
        INNER JOIN dbo.DO30_DOCCORPO C_ORD WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = C_ORD.DO30_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = C_ORD.DO30_NUMREG_CO99 AND R2.DO33_PROGRIGA = C_ORD.DO30_PROGRIGA
        INNER JOIN dbo.DO33_DOCCORPORIF R3 WITH (NOLOCK) ON C_ORD.DO30_DITTA_CG18 = R3.DO33_DITTA_CG18 AND C_ORD.DO30_NUMREG_CO99 = R3.DO33_NUMREGRIF_CO99 AND C_ORD.DO30_PROGRIGA = R3.DO33_PROGRIGARIF_DO30
        INNER JOIN dbo.DO30_DOCCORPO C_DDT WITH (NOLOCK) ON R3.DO33_DITTA_CG18 = C_DDT.DO30_DITTA_CG18 AND R3.DO33_NUMREG_CO99 = C_DDT.DO30_NUMREG_CO99 AND R3.DO33_PROGRIGA = C_DDT.DO30_PROGRIGA
        INNER JOIN dbo.DO11_DOCTESTATA T_DDT WITH (NOLOCK) ON C_DDT.DO30_DITTA_CG18 = T_DDT.DO11_DITTA_CG18 AND C_DDT.DO30_NUMREG_CO99 = T_DDT.DO11_NUMREG_CO99
        WHERE T_DDT.DO11_TIPODOC = 25 AND T_DDT.DO11_STIPODOC = 13
        GROUP BY C_OC.DO30_DITTA_CG18, C_OC.DO30_NUMREG_CO99, C_OC.DO30_PROGRIGA;

        CREATE CLUSTERED INDEX IX_DateDDT ON #DateDDT (DO30_DITTA_CG18_OC, DO30_NUMREG_CO99_OC, DO30_PROGRIGA_OC);

        -- Tabella temporanea collettore per tutti i candidati proposti dalle singole regole
        CREATE TABLE #CandidatiStato (
            DO30_GUID UNIQUEIDENTIFIER NOT NULL, 
            DO11_NUMDOC INT NULL, 
            DO11_SEZDOC VARCHAR(10) COLLATE DATABASE_DEFAULT, 
            DO30_NUMREG_CO99 VARCHAR(30) COLLATE DATABASE_DEFAULT, 
            DO30_PROGRIGA INT NULL, 
            DO30_PROGVISUASTA INT NULL,
            CO4H_IDSTATO_CO4C_ATTUALE INT NOT NULL, 
            CO4H_IDSTATO_CO4C_NEW INT NOT NULL, 
            DataEvento DATETIME NOT NULL,
            OrigineRegola VARCHAR(100) COLLATE DATABASE_DEFAULT, 
            PrioritaSequenza INT DEFAULT 0
        );

        -- =============================================================================================================
        -- FASE 2: MOTORE DELLE REGOLE DI BUSINESS (GENERAZIONE CANDIDATI AL RANKING)
        -- =============================================================================================================
        -- Ogni blocco esamina le evidenze documentali sul database. Più regole possono essere soddisfatte contemporaneamente
        -- per una medesima riga d'ordine (es. una riga ha sia l'ODL generato che il Collaudo eseguito che il DDT finale).
        -- Tutte le regole inseriscono i candidati in #CandidatiStato; sarà la FASE 3 a decretare il vincitore.
        RAISERROR('>> Inizio FASE 2: Analisi ed esecuzione delle Regole di Punteggio...', 10, 1) WITH NOWAIT;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 01: ODL GENERATO (Stato 10051 - Priorita 1)
        -- Business Logic: Quando la programmazione della produzione lancia l'ODL (TipoDoc 24), la riga d'ordine
        -- cessa di essere una semplice richiesta commerciale ed entra ufficialmente nel ciclo operativo di fabbrica.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT DO30_GUID, DO11_NUMDOC_OC, DO11_SEZDOC_OC, DO30_NUMREG_CO99_OC, DO30_PROGRIGA_OC, DO30_PROGVISUASTA_OC, 
               CO4H_IDSTATO_CO4C_ATTUALE, 10051, ISNULL(DO11_DATADOC_ODL, DO11_DATADOC_OC), 'Regola 01 - ODL Generato', 1
        FROM #BaseDatiRiga 
        WHERE DO11_DOCUM_MG36_ODL IS NOT NULL; 

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 02: IN PRODUZIONE (Stato 10073 - Priorita 2)
        -- Business Logic: Rileva l'avanzamento fisico del pezzo sulle macchine utensili (centri di lavoro interni,
        -- PD12_INDTIPOPROV = 0) per qualsiasi fase di sequenza tecnologica inferiore alla fase di Collaudo (4031).
        --
        -- PROTEZIONI ANTI-REGRESSIONE (Svolta Architetturale Rev. 27):
        -- Nel flusso reale di fabbrica, capita frequentemente che un operatore a bordo macchina (es. per dimenticanza,
        -- correzione ore, rilavorazione postuma o allineamento ritardato delle quantità) registri un movimento MES
        -- in data odierna (DO57_DATAMOV) su una fase iniziale (es. rullatura o sgrossatura), anche se l'ODL è già stato
        -- completato da tempo o se l'articolo è già stato collaudato, imballato e consegnato al cliente.
        -- Se la Regola 02 valutasse semplicemente MAX(DO57_DATAMOV), tale data recente supererebbe nel ranking la data
        -- della spedizione o del collaudo, facendo erroneamente REGREDIRE una riga già spedita a "In Produzione".
        --
        -- Per impedire questa regressione spuria, la Regola 02 viene categoricamente INIBITA al verificarsi di anche
        -- una sola delle seguenti 4 condizioni aziendali:
        --   a) STATO LOGISTICO GIA AVANZATO: Se lo stato attuale della riga è già arrivato a Packing List (10063/10076),
        --      Merce Pronta AMP (10062), Spedito (10053/10084), Annullato (10068), Diba non necessaria (10055) o Fornitore (10054).
        --   b) RIGA D'ORDINE TOTALMENTE EVASA: Se in DO72_DOCCORPOSTATO la riga risulta con Flag Evaso = 1 e Da Evadere = 0.
        --   c) ODL VERSATO A MAGAZZINO: Se la Fase 6000 (RTP/Versamento Magazzino) presenta già una quantità consolidata
        --      pari o superiore alla quantità ordinata (DO46_QTA1CONSOLID >= DO46_QTA1ORD).
        --   d) ODL FORMALMENTE CHIUSO: Se la testata dell'ordine di lavoro in DO31 ha assunto lo stato consolidato di
        --      chiusura definitiva (DO31_INDSTATOCONS = 3).
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10073, 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 02 - In Produzione', 2
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            CROSS APPLY (
                SELECT ISNULL(MAX(CASE WHEN L.DO46_CODFASE = 4031 THEN L.DO46_CODSEQFASE END), MAX(L.DO46_CODSEQFASE)) AS SEQ_LIMITE 
                FROM dbo.DO46_DOCCORORDDET L WITH (NOLOCK) 
                WHERE L.DO46_DITTA_CG18 = D.DO46_DITTA_CG18 AND L.DO46_NUMREG_CO99 = D.DO46_NUMREG_CO99 AND L.DO46_PROGRIGA = D.DO46_PROGRIGA
            ) AS LIM
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODSEQFASE < LIM.SEQ_LIMITE 
              AND ISNULL(D.DO46_QTA1CONSOLID, 0) > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA
        WHERE B.CO4H_IDSTATO_CO4C_ATTUALE NOT IN (10063, 10076, 10062, 10053, 10084, 10068, 10055, 10054) -- Salvaguardia (a)
          AND NOT EXISTS (                                                                                   -- Salvaguardia (b)
              SELECT 1 FROM dbo.DO72_DOCCORPOSTATO S WITH (NOLOCK)
              WHERE S.DO72_DITTA_CG18 = B.DO30_DITTA_CG18_OC 
                AND S.DO72_NUMREG_CO99 = B.DO30_NUMREG_CO99_OC 
                AND S.DO72_PROGRIGA = B.DO30_PROGRIGA_OC
                AND S.DO72_FLGEVASO = 1 AND S.DO72_FLGDAEVADERE = 0
          )
          AND NOT EXISTS (                                                                                   -- Salvaguardia (c)
              SELECT 1 FROM dbo.DO46_DOCCORORDDET D_RTP WITH (NOLOCK)
              WHERE D_RTP.DO46_DITTA_CG18 = B.DO30_DITTA_CG18_ODL 
                AND D_RTP.DO46_NUMREG_CO99 = B.DO30_NUMREG_CO99_ODL 
                AND D_RTP.DO46_PROGRIGA = B.DO30_PROGRIGA_ODL
                AND D_RTP.DO46_CODFASE = 6000 
                AND D_RTP.DO46_QTA1CONSOLID >= D_RTP.DO46_QTA1ORD
          )
          AND NOT EXISTS (                                                                                   -- Salvaguardia (d)
              SELECT 1 FROM dbo.DO31_DOCCORPOORD O_CHIUSO WITH (NOLOCK)
              WHERE O_CHIUSO.DO31_DITTA_CG18 = B.DO30_DITTA_CG18_ODL
                AND O_CHIUSO.DO31_NUMREG_CO99 = B.DO30_NUMREG_CO99_ODL
                AND O_CHIUSO.DO31_PROGRIGA = B.DO30_PROGRIGA_ODL
                AND O_CHIUSO.DO31_INDSTATOCONS = 3
          );

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 03: COLLAUDO (Stato 10080 - Priorita 3)
        -- Business Logic: Rileva l'avanzamento consolidato sulla fase tecnologica speciale 4031 (Collaudo Finale).
        -- Il materiale ha terminato le lavorazioni meccaniche ed è in fase di certificazione metrologica/qualità.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10080, 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 03 - Collaudo', 3
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODFASE = 4031 
              AND D.DO46_QTA1CONSOLID > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 04: ATTESA INVIO C/LAVORO (Stati 10069 / 10081 - Priorita 4)
        -- Business Logic: Rileva l'avanzamento sulla fase preparatoria interna per invio a terzista esterno:
        -- - Fase 4001: Trattamento Termico/Galvanico 1 -> Stato 10069
        -- - Fase 4002: Trattamento Termico/Galvanico 2 -> Stato 10081
        -- Il lotto è pronto in banchina in attesa dell'emissione del DDT di Conto Lavoro.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 
               IIF(FASI.DO46_CODFASE = 4001, 10069, 10081), 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               IIF(FASI.DO46_CODFASE = 4001, 'Regola 04 - Attesa Invio C/Lav (Tratt. 1)', 'Regola 04 - Attesa Invio C/Lav (Tratt. 2)'), 4
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODFASE IN (4001, 4002) 
              AND D.DO46_QTA1CONSOLID > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 05: TERZISTA 1 (Stato 10070 - Priorita 5)
        -- Business Logic: Certifica che il materiale è fisicamente uscito dallo stabilimento ed è presso il Terzista 1
        -- (Fase 4001 consolidata ed emissione verificata del DDT di Conto Lavoro tramite funzione SPRT_TMV_MPS_DDT_CLA_ESTREMI).
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10070, 
               ISNULL(DDT.DATA_DDT, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 05 - Terzista 1', 5
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT DISTINCT DO46_DITTA_CG18, DO46_NUMREG_CO99, DO46_PROGRIGA 
            FROM dbo.DO46_DOCCORORDDET WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO WITH (NOLOCK) ON DO46_DITTA_CG18 = PD12_DITTA_CG18 AND DO46_CODFASE = PD12_CODFASE
            WHERE PD12_INDTIPOPROV = 0 AND DO46_CODFASE = 4001 AND DO46_QTA1CONSOLID > 0
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA
        LEFT JOIN #DateDDT DDT ON B.DO30_DITTA_CG18_OC = DDT.DO30_DITTA_CG18_OC AND B.DO30_NUMREG_CO99_OC = DDT.DO30_NUMREG_CO99_OC AND B.DO30_PROGRIGA_OC = DDT.DO30_PROGRIGA_OC
        WHERE ISNULL(RTRIM(dbo.SPRT_TMV_MPS_DDT_CLA_ESTREMI(B.DO30_DITTA_CG18_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, 1)), '') <> '';

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 06: TERZISTA 2 (Stato 10071 - Priorita 6)
        -- Business Logic: Certifica che il materiale è fisicamente presso il Terzista 2 (Fase 4002 consolidata
        -- ed emissione accertata del DDT di Conto Lavoro associato).
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10071, 
               ISNULL(DDT.DATA_DDT, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 06 - Terzista 2', 6
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT DISTINCT DO46_DITTA_CG18, DO46_NUMREG_CO99, DO46_PROGRIGA 
            FROM dbo.DO46_DOCCORORDDET WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO WITH (NOLOCK) ON DO46_DITTA_CG18 = PD12_DITTA_CG18 AND DO46_CODFASE = PD12_CODFASE
            WHERE PD12_INDTIPOPROV = 0 AND DO46_CODFASE = 4002 AND DO46_QTA1CONSOLID > 0
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA
        LEFT JOIN #DateDDT DDT ON B.DO30_DITTA_CG18_OC = DDT.DO30_DITTA_CG18_OC AND B.DO30_NUMREG_CO99_OC = DDT.DO30_NUMREG_CO99_OC AND B.DO30_PROGRIGA_OC = DDT.DO30_PROGRIGA_OC
        WHERE ISNULL(RTRIM(dbo.SPRT_TMV_MPS_DDT_CLA_ESTREMI(B.DO30_DITTA_CG18_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, 1)), '') <> '';

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 07: RIENTRO C/LAVORO (Stati 10074 / 10082 - Priorita 7)
        -- Business Logic: Rileva il rientro fisico della merce dal fornitore esterno allo stabilimento TMV:
        -- - Fase 4011: Rientro da Trattamento 1 -> Stato 10074
        -- - Fase 4012: Rientro da Trattamento 2 -> Stato 10082
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 
               IIF(FASI.DO46_CODFASE = 4011, 10074, 10082), 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               IIF(FASI.DO46_CODFASE = 4011, 'Regola 07 - Rientro C/Lav (Tratt. 1)', 'Regola 07 - Rientro C/Lav (Tratt. 2)'), 7
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODFASE IN (4011, 4012) 
              AND D.DO46_QTA1CONSOLID > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 08: SMISTATO C/LAVORO (Stati 10075 / 10083 - Priorita 8)
        -- Business Logic: Rileva l'avvenuto controllo, pulizia e smistamento interno dei pezzi rientrati dal terzista:
        -- - Fase 4021: Smistato dopo Trattamento 1 -> Stato 10075
        -- - Fase 4022: Smistato dopo Trattamento 2 -> Stato 10083
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 
               IIF(FASI.DO46_CODFASE = 4021, 10075, 10083), 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               IIF(FASI.DO46_CODFASE = 4021, 'Regola 08 - Smistato C/Lav (Tratt. 1)', 'Regola 08 - Smistato C/Lav (Tratt. 2)'), 8
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODFASE IN (4021, 4022) 
              AND D.DO46_QTA1CONSOLID > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, D.DO46_CODFASE
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 09: RTP / VERSAMENTO FINALE A MAGAZZINO (Stato 10052 - Priorita 9)
        -- Business Logic: Rileva l'avanzamento sulla Fase 6000 (RTP - Ready To Package / Versamento a Magazzino).
        -- Rappresenta il traguardo produttivo: il pezzo è fisicamente completato, collaudato e versato a magazzino,
        -- pronto per essere prelevato dalla logistica di spedizione.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10052, 
               ISNULL(FASI.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 09 - RTP', 9
        FROM #BaseDatiRiga B
        INNER JOIN (
            SELECT D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA, MAX(ADV.DO57_DATAMOV) AS DATA_AVANZAMENTO
            FROM dbo.DO46_DOCCORORDDET D WITH (NOLOCK)
            INNER JOIN dbo.PD12_FASILAVORO P WITH (NOLOCK) ON D.DO46_DITTA_CG18 = P.PD12_DITTA_CG18 AND D.DO46_CODFASE = P.PD12_CODFASE
            LEFT JOIN dbo.DO57_DETAVANZ ADV WITH (NOLOCK) ON D.DO46_DITTA_CG18 = ADV.DO57_DITTA_CG18 AND D.DO46_NUMREG_CO99 = ADV.DO57_NUMREG_CO99 AND D.DO46_PROGRIGA = ADV.DO57_PROGRIGA_DO46 AND D.DO46_PROGDET = ADV.DO57_PROGDET_DO46
            WHERE P.PD12_INDTIPOPROV = 0 
              AND D.DO46_CODFASE = 6000 
              AND D.DO46_QTA1CONSOLID > 0
            GROUP BY D.DO46_DITTA_CG18, D.DO46_NUMREG_CO99, D.DO46_PROGRIGA
        ) AS FASI ON B.DO30_DITTA_CG18_ODL = FASI.DO46_DITTA_CG18 AND B.DO30_NUMREG_CO99_ODL = FASI.DO46_NUMREG_CO99 AND B.DO30_PROGRIGA_ODL = FASI.DO46_PROGRIGA;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 09B: SALVAGUARDIA RTP PER FAKE ODL PROCESS (Stato 10052 - Priorita 99)
        -- Business Logic (Rev. 16): Per i cicli di articoli virtuali identificati in FASE 1 (#HistoryBypass),
        -- preserva lo stato 10052 (RTP) assegnando priorità alta (99) per impedire retrocessioni spurie.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10052, 
               ISNULL(ADV.DATA_AVANZAMENTO, ISNULL(B.DO11_DATADOC_ODL, B.DO11_DATADOC_OC)), 
               'Regola 09B - Salvaguardia RTP (Fake ODL Process)', 99 
        FROM #BaseDatiRiga B
        OUTER APPLY (
            SELECT MAX(A.DO57_DATAMOV) AS DATA_AVANZAMENTO 
            FROM dbo.DO57_DETAVANZ A WITH (NOLOCK)
            WHERE A.DO57_DITTA_CG18 = B.DO30_DITTA_CG18_ODL 
              AND A.DO57_NUMREG_CO99 = B.DO30_NUMREG_CO99_ODL 
              AND A.DO57_PROGRIGA_DO46 = B.DO30_PROGRIGA_ODL
        ) AS ADV
        WHERE B.FLG_FAKE_ODL = 1 AND B.DO11_DOCUM_MG36_ODL IS NOT NULL;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 10: PACKING LIST (PKL) PARZIALE O TOTALE (Stati 10076 / 10063 - Priorita 10)
        -- Business Logic: Rileva l'emissione del documento di prelievo logico a magazzino (Packing List: TipoDoc 9, STipoDoc 1).
        -- Confronta la somma delle quantità prelevate in PKL rispetto alla quantità ordinata nella riga d'ordine cliente (DO30_QTA1):
        -- - Se la quantità in PKL è inferiore alla quantità ordinata: assegna lo stato 10076 (PKL Parziale)
        -- - Se la quantità in PKL copre interamente l'ordine: assegna lo stato 10063 (PKL Totale / Chiuso)
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 
               IIF(DO30_OC.DO30_QTA1 > ISNULL(PKL.DO30_QTA1_PKL, 0), 10076, 10063), 
               PKL.DATA_PKL, 
               IIF(DO30_OC.DO30_QTA1 > ISNULL(PKL.DO30_QTA1_PKL, 0), 'Regola 10 - PKL Parziale', 'Regola 10 - PKL Totale (Chiuso)'), 10
        FROM #BaseDatiRiga B
        INNER JOIN dbo.DO30_DOCCORPO DO30_OC WITH (NOLOCK) ON B.DO30_DITTA_CG18_OC = DO30_OC.DO30_DITTA_CG18 AND B.DO30_NUMREG_CO99_OC = DO30_OC.DO30_NUMREG_CO99 AND B.DO30_PROGRIGA_OC = DO30_OC.DO30_PROGRIGA
        INNER JOIN ( 
            SELECT DO33.DO33_DITTA_CG18, DO33.DO33_NUMREGRIF_CO99, DO33.DO33_PROGRIGARIF_DO30, 
                   SUM(DO30_PKL.DO30_QTA1) AS DO30_QTA1_PKL, MAX(DO11_PKL.DO11_DATADOC) AS DATA_PKL
            FROM dbo.DO11_DOCTESTATA DO11_PKL WITH (NOLOCK)
            INNER JOIN dbo.DO30_DOCCORPO DO30_PKL WITH (NOLOCK) ON DO11_PKL.DO11_DITTA_CG18 = DO30_PKL.DO30_DITTA_CG18 AND DO11_PKL.DO11_NUMREG_CO99 = DO30_PKL.DO30_NUMREG_CO99
            INNER JOIN dbo.DO33_DOCCORPORIF DO33 WITH (NOLOCK) ON DO30_PKL.DO30_DITTA_CG18 = DO30_PKL.DO30_DITTA_CG18 AND DO30_PKL.DO30_NUMREG_CO99 = DO33.DO33_NUMREG_CO99 AND DO30_PKL.DO30_PROGRIGA = DO33.DO33_PROGRIGA
            WHERE DO11_PKL.DO11_TIPODOC = 9 AND DO11_PKL.DO11_STIPODOC = 1 
            GROUP BY DO33.DO33_DITTA_CG18, DO33.DO33_NUMREGRIF_CO99, DO33.DO33_PROGRIGARIF_DO30
        ) AS PKL ON PKL.DO33_DITTA_CG18 = B.DO30_DITTA_CG18_OC AND PKL.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND PKL.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 11: ARTICOLI FITTIZI / NOTE / DESCRITTIVE A RIMORCHIO PKL (Stato 10063 - Priorita 11)
        -- Business Logic (Rev. 23): Gestisce le righe non fisiche (righe descrittive speciali DO30_INDTIPORIGA <> 0
        -- o articoli con flag fittizio MG66_INDFITTIZIO <> 0, come spese accessorie o certificazioni).
        -- Tali righe non hanno un avanzamento fisico proprio, ma devono avanzare a PKL a rimorchio dell'ordine,
        -- scansionando fino a tre livelli gerarchici di referenza documentale su DO33_DOCCORPORIF.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10063, 
               ISNULL(PKL.DATA_PKL, B.DO11_DATADOC_OC), 
               'Regola 11 - Articoli Fittizi / Descrittive (PKL)', 11
        FROM #BaseDatiRiga B
        INNER JOIN dbo.DO30_DOCCORPO DO30_OC WITH (NOLOCK) ON B.DO30_DITTA_CG18_OC = DO30_OC.DO30_DITTA_CG18 AND B.DO30_NUMREG_CO99_OC = DO30_OC.DO30_NUMREG_CO99 AND B.DO30_PROGRIGA_OC = DO30_OC.DO30_PROGRIGA
        LEFT JOIN dbo.MG66_ANAGRART MG66 WITH (NOLOCK) ON DO30_OC.DO30_DITTA_CG18 = MG66.MG66_DITTA_CG18 AND DO30_OC.DO30_CODART_MG66 = MG66.MG66_CODART
        CROSS APPLY (
            SELECT MAX(DATA_PKL) AS DATA_PKL
            FROM (
                -- Livello 1: Riferimento diretto a PKL
                SELECT T1.DO11_DATADOC AS DATA_PKL 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO11_DOCTESTATA T1 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = T1.DO11_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = T1.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND T1.DO11_TIPODOC = 9
                UNION ALL
                -- Livello 2: Riferimento indiretto tramite documento intermedio
                SELECT T2.DO11_DATADOC AS DATA_PKL 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = T2.DO11_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = T2.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND T2.DO11_TIPODOC = 9
                UNION ALL
                -- Livello 3: Riferimento a 3 salti su DO33
                SELECT T3.DO11_DATADOC AS DATA_PKL 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO33_DOCCORPORIF R3 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = R3.DO33_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = R3.DO33_NUMREGRIF_CO99 AND R2.DO33_PROGRIGA = R3.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T3 WITH (NOLOCK) ON R3.DO33_DITTA_CG18 = T3.DO11_DITTA_CG18 AND R3.DO33_NUMREG_CO99 = T3.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND T3.DO11_TIPODOC = 9
            ) AS X
        ) AS PKL 
        WHERE (DO30_OC.DO30_INDTIPORIGA <> 0 OR ISNULL(MG66.MG66_INDFITTIZIO, 0) <> 0) 
          AND PKL.DATA_PKL IS NOT NULL;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 12: READY TO DELIVERY / AVVISO MERCE PRONTA (AMP) PER RIGHE FISICHE (Stato 10062 - Priorita 12)
        -- Business Logic: Rileva l'emissione del documento AMP (TipoDoc = 2). La merce è imballata e pronta sul piazzale,
        -- ed è stata inviata la comunicazione formale di merce pronta al cliente/spedizioniere.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10062, 
               ISNULL(AMP.DATA_AMP, B.DO11_DATADOC_OC), 
               'Regola 12 - Ready to Delivery (AMP)', 12
        FROM #BaseDatiRiga B
        CROSS APPLY (
            SELECT MAX(T.DO11_DATADOC) AS DATA_AMP 
            FROM dbo.DO33_DOCCORPORIF R WITH (NOLOCK) 
            INNER JOIN dbo.DO11_DOCTESTATA T WITH (NOLOCK) ON R.DO33_DITTA_CG18 = T.DO11_DITTA_CG18 AND R.DO33_NUMREG_CO99 = T.DO11_NUMREG_CO99 
            WHERE R.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
              AND R.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC 
              AND T.DO11_TIPODOC = 2
        ) AS AMP
        WHERE AMP.DATA_AMP IS NOT NULL;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 12B: READY TO DELIVERY PER DESCRITTIVE / SPESE A RIMORCHIO (Stato 10062 - Priorita 12)
        -- Business Logic: Eredità a rimorchio dello stato 10062 (AMP) per righe descrittive, fittizie o spese accessorie
        -- collegate all'Impegno Cliente quando esiste almeno un Avviso Merce Pronta emesso per l'ordine.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10062, 
               ISNULL(AMP.DATA_AMP, B.DO11_DATADOC_OC), 
               'Regola 12B - Ready to Delivery (Descrittive/Spese)', 12
        FROM #BaseDatiRiga B
        INNER JOIN dbo.DO30_DOCCORPO DO30_OC WITH (NOLOCK) ON B.DO30_DITTA_CG18_OC = DO30_OC.DO30_DITTA_CG18 AND B.DO30_NUMREG_CO99_OC = DO30_OC.DO30_NUMREG_CO99 AND B.DO30_PROGRIGA_OC = DO30_OC.DO30_PROGRIGA
        LEFT JOIN dbo.MG66_ANAGRART MG66 WITH (NOLOCK) ON DO30_OC.DO30_DITTA_CG18 = MG66.MG66_DITTA_CG18 AND DO30_OC.DO30_CODART_MG66 = MG66.MG66_CODART
        CROSS APPLY (
            SELECT MAX(T.DO11_DATADOC) AS DATA_AMP 
            FROM dbo.DO33_DOCCORPORIF R WITH (NOLOCK) 
            INNER JOIN dbo.DO11_DOCTESTATA T WITH (NOLOCK) ON R.DO33_DITTA_CG18 = T.DO11_DITTA_CG18 AND R.DO33_NUMREG_CO99 = T.DO11_NUMREG_CO99 
            WHERE R.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
              AND T.DO11_TIPODOC = 2
        ) AS AMP
        WHERE (DO30_OC.DO30_INDTIPORIGA <> 0 OR ISNULL(MG66.MG66_INDFITTIZIO, 0) <> 0) 
          AND AMP.DATA_AMP IS NOT NULL;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 13: SPEDITO PARZIALE O TOTALE (Stati 10084 / 10053 - Priorita 13)
        -- Business Logic: Rileva l'avvenuta spedizione fisica e fatturazione della merce mediante scansione dei DDT di vendita
        -- (TipoDoc = 1) o Fatture Accompagnatorie (TipoDoc = 5, STipoDoc = 2).
        --
        -- MODELLO DI NAVIGAZIONE A 4 RAMI (Aggiornato e Perfezionato nella Rev. 27):
        --   1) Ramo Diretto (Livello 1): DDT/Fattura emesso direttamente a fronte della riga di Impegno Cliente.
        --   2) Ramo Indiretto (Livello 2): DDT emesso a fronte di un documento intermedio (es. PKL).
        --      * Clausola di esclusione speciale NOT EXISTS: se la Fattura Accompagnatoria ha generato a sua volta
        --        un Buono di Carico Deposito con successivo DDT definitivo di consegna al cliente, il Ramo 2 NON conta
        --        la quantità né la data della fattura, delegando il calcolo al Ramo 4 downstream, per evitare duplicazioni
        --        di quantità e per registrare la reale data di consegna al cliente.
        --   3) Ramo a 3 Livelli: Navigazione profonda attraverso catene complesse di evasione a tre passaggi su DO33.
        --   4) Ramo Deposito Collegato da Testata (Rev. 27): Intercetta i casi in cui tra la Fattura/Bolla e il DDT finale
        --      il legame non è registrato a livello riga (DO33) ma a livello di testata documento tramite il campo
        --      DO11_NUMREGCOL_CO99 (es. Fattura Accompagnatoria -> Buono Carico Deposito DC-DDTCARDEPCL -> DDT finale DC-DDTCLIDC).
        --
        -- DISCRIMINAZIONE QUANTITA PARZIALE / TOTALE:
        -- - Se la quantità complessivamente spedita (TOT_QTA_DDT) è inferiore alla quantità ordinata (DO30_QTA1):
        --   assegna lo stato 10084 (Spedito Parziale).
        -- - Se la quantità spedita copre interamente l'ordine: assegna lo stato 10053 (Spedito Totale).
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 
               IIF(DO30_OC.DO30_QTA1 > ISNULL(DDT.TOT_QTA_DDT, 0), 10084, 10053), 
               ISNULL(DDT.DATA_DDT, B.DO11_DATADOC_OC), 
               IIF(DO30_OC.DO30_QTA1 > ISNULL(DDT.TOT_QTA_DDT, 0), 'Regola 13 - Spedito Parziale (DDT)', 'Regola 13 - Spedito Totale (DDT)'), 13
        FROM #BaseDatiRiga B
        INNER JOIN dbo.DO30_DOCCORPO DO30_OC WITH (NOLOCK) ON B.DO30_DITTA_CG18_OC = DO30_OC.DO30_DITTA_CG18 AND B.DO30_NUMREG_CO99_OC = DO30_OC.DO30_NUMREG_CO99 AND B.DO30_PROGRIGA_OC = DO30_OC.DO30_PROGRIGA
        CROSS APPLY (
            SELECT MAX(DATA_DDT) AS DATA_DDT, SUM(QTA_DDT) AS TOT_QTA_DDT
            FROM (
                -- Ramo 1: DDT/Fattura diretto da Impegno Cliente (Livello 1)
                SELECT T1.DO11_DATADOC AS DATA_DDT, C1.DO30_QTA1 AS QTA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO11_DOCTESTATA T1 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = T1.DO11_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = T1.DO11_NUMREG_CO99 
                INNER JOIN dbo.DO30_DOCCORPO C1 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = C1.DO30_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = C1.DO30_NUMREG_CO99 AND R1.DO33_PROGRIGA = C1.DO30_PROGRIGA 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
                  AND R1.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC 
                  AND (T1.DO11_TIPODOC = 1 OR (T1.DO11_TIPODOC = 5 AND T1.DO11_STIPODOC = 2))
                UNION ALL
                -- Ramo 2: DDT/Fattura a 2 livelli (es. tramite PKL intermedia)
                SELECT T2.DO11_DATADOC AS DATA_DDT, C2.DO30_QTA1 AS QTA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = T2.DO11_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = T2.DO11_NUMREG_CO99 
                INNER JOIN dbo.DO30_DOCCORPO C2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = C2.DO30_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = C2.DO30_NUMREG_CO99 AND R2.DO33_PROGRIGA = C2.DO30_PROGRIGA 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
                  AND R1.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC 
                  AND (T2.DO11_TIPODOC = 1 OR (T2.DO11_TIPODOC = 5 AND T2.DO11_STIPODOC = 2))
                  AND NOT EXISTS (
                      -- Se la fattura ha generato un Buono Deposito collegato con successivo DDT di consegna, il calcolo è demandato al Ramo 4
                      SELECT 1 FROM dbo.DO11_DOCTESTATA T_DEP WITH (NOLOCK)
                      INNER JOIN dbo.DO33_DOCCORPORIF R_DEP WITH (NOLOCK) ON T_DEP.DO11_DITTA_CG18 = R_DEP.DO33_DITTA_CG18 AND T_DEP.DO11_NUMREG_CO99 = R_DEP.DO33_NUMREGRIF_CO99 AND R2.DO33_PROGRIGA = R_DEP.DO33_PROGRIGARIF_DO30
                      INNER JOIN dbo.DO11_DOCTESTATA T_FINAL WITH (NOLOCK) ON R_DEP.DO33_DITTA_CG18 = T_FINAL.DO11_DITTA_CG18 AND R_DEP.DO33_NUMREG_CO99 = T_FINAL.DO11_NUMREG_CO99
                      WHERE T_DEP.DO11_DITTA_CG18 = T2.DO11_DITTA_CG18 
                        AND T_DEP.DO11_NUMREG_CO99 = T2.DO11_NUMREGCOL_CO99 
                        AND T_FINAL.DO11_TIPODOC = 1
                  )
                UNION ALL
                -- Ramo 3: DDT a 3 livelli su DO33
                SELECT T3.DO11_DATADOC AS DATA_DDT, C3.DO30_QTA1 AS QTA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO33_DOCCORPORIF R3 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = R3.DO33_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = R3.DO33_NUMREGRIF_CO99 AND R2.DO33_PROGRIGA = R3.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T3 WITH (NOLOCK) ON R3.DO33_DITTA_CG18 = T3.DO11_DITTA_CG18 AND R3.DO33_NUMREG_CO99 = T3.DO11_NUMREG_CO99 
                INNER JOIN dbo.DO30_DOCCORPO C3 WITH (NOLOCK) ON R3.DO33_DITTA_CG18 = C3.DO30_DITTA_CG18 AND R3.DO33_NUMREG_CO99 = C3.DO30_NUMREG_CO99 AND R3.DO33_PROGRIGA = C3.DO30_PROGRIGA 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
                  AND R1.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC 
                  AND (T3.DO11_TIPODOC = 1 OR (T3.DO11_TIPODOC = 5 AND T3.DO11_STIPODOC = 2))
                UNION ALL
                -- Ramo 4 (Rev. 27): Transito da Documenti Collegati di Testata (Fattura Accompagnatoria -> Buono Deposito -> DDT Finale)
                SELECT T_COL_DDT.DO11_DATADOC AS DATA_DDT, C_COL_DDT.DO30_QTA1 AS QTA_DDT
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK)
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30
                INNER JOIN dbo.DO11_DOCTESTATA T2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = T2.DO11_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = T2.DO11_NUMREG_CO99
                INNER JOIN dbo.DO11_DOCTESTATA T_DEP WITH (NOLOCK) ON T2.DO11_DITTA_CG18 = T_DEP.DO11_DITTA_CG18 AND T2.DO11_NUMREGCOL_CO99 = T_DEP.DO11_NUMREG_CO99
                INNER JOIN dbo.DO33_DOCCORPORIF R_COL WITH (NOLOCK) ON T_DEP.DO11_DITTA_CG18 = R_COL.DO33_DITTA_CG18 AND T_DEP.DO11_NUMREG_CO99 = R_COL.DO33_NUMREGRIF_CO99 AND R2.DO33_PROGRIGA = R_COL.DO33_PROGRIGARIF_DO30
                INNER JOIN dbo.DO11_DOCTESTATA T_COL_DDT WITH (NOLOCK) ON R_COL.DO33_DITTA_CG18 = T_COL_DDT.DO11_DITTA_CG18 AND R_COL.DO33_NUMREG_CO99 = T_COL_DDT.DO11_NUMREG_CO99
                INNER JOIN dbo.DO30_DOCCORPO C_COL_DDT WITH (NOLOCK) ON R_COL.DO33_DITTA_CG18 = C_COL_DDT.DO30_DITTA_CG18 AND R_COL.DO33_NUMREG_CO99 = C_COL_DDT.DO30_NUMREG_CO99 AND R_COL.DO33_PROGRIGA = C_COL_DDT.DO30_PROGRIGA
                WHERE R1.DO33_DITTA_CG18 = B.DO30_DITTA_CG18_OC 
                  AND R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
                  AND R1.DO33_PROGRIGARIF_DO30 = B.DO30_PROGRIGA_OC 
                  AND (T_COL_DDT.DO11_TIPODOC = 1 OR (T_COL_DDT.DO11_TIPODOC = 5 AND T_COL_DDT.DO11_STIPODOC = 2))
            ) AS X
        ) AS DDT 
        WHERE DDT.DATA_DDT IS NOT NULL 
          AND NOT (DO30_OC.DO30_QTA1 > ISNULL(DDT.TOT_QTA_DDT, 0) AND B.DO11_DOCUM_MG36_ODL IS NOT NULL);

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 13B: SPEDITO PER DESCRITTIVE / SPESE A RIMORCHIO DDT (Stato 10053 - Priorita 13)
        -- Business Logic: Eredità dello stato 10053 per righe puramente descrittive, note spese o articoli fittizi
        -- collegate all'Impegno Cliente quando esiste almeno una spedizione a valle dell'ordine.
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
               B.CO4H_IDSTATO_CO4C_ATTUALE, 10053, 
               ISNULL(DDT.DATA_DDT, B.DO11_DATADOC_OC), 
               'Regola 13B - Spedito (Descrittive/Spese)', 13
        FROM #BaseDatiRiga B
        INNER JOIN dbo.DO30_DOCCORPO DO30_OC WITH (NOLOCK) ON B.DO30_DITTA_CG18_OC = DO30_OC.DO30_DITTA_CG18 AND B.DO30_NUMREG_CO99_OC = DO30_OC.DO30_NUMREG_CO99 AND B.DO30_PROGRIGA_OC = DO30_OC.DO30_PROGRIGA
        LEFT JOIN dbo.MG66_ANAGRART MG66 WITH (NOLOCK) ON DO30_OC.DO30_DITTA_CG18 = MG66.MG66_DITTA_CG18 AND DO30_OC.DO30_CODART_MG66 = MG66.MG66_CODART
        CROSS APPLY (
            SELECT MAX(DATA_DDT) AS DATA_DDT
            FROM (
                -- Livello 1
                SELECT T1.DO11_DATADOC AS DATA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO11_DOCTESTATA T1 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = T1.DO11_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = T1.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND (T1.DO11_TIPODOC = 1 OR (T1.DO11_TIPODOC = 5 AND T1.DO11_STIPODOC = 2))
                UNION ALL
                -- Livello 2
                SELECT T2.DO11_DATADOC AS DATA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = T2.DO11_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = T2.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND (T2.DO11_TIPODOC = 1 OR (T2.DO11_TIPODOC = 5 AND T2.DO11_STIPODOC = 2))
                UNION ALL
                -- Livello 3
                SELECT T3.DO11_DATADOC AS DATA_DDT 
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK) 
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO33_DOCCORPORIF R3 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = R3.DO33_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = R3.DO33_NUMREGRIF_CO99 AND R2.DO33_PROGRIGA = R3.DO33_PROGRIGARIF_DO30 
                INNER JOIN dbo.DO11_DOCTESTATA T3 WITH (NOLOCK) ON R3.DO33_DITTA_CG18 = T3.DO11_DITTA_CG18 AND R3.DO33_NUMREG_CO99 = T3.DO11_NUMREG_CO99 
                WHERE R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC AND (T3.DO11_TIPODOC = 1 OR (T3.DO11_TIPODOC = 5 AND T3.DO11_STIPODOC = 2))
                UNION ALL
                -- Livello 2 da Documenti Collegati di Testata (Rev. 27)
                SELECT T_COL_DDT.DO11_DATADOC AS DATA_DDT
                FROM dbo.DO33_DOCCORPORIF R1 WITH (NOLOCK)
                INNER JOIN dbo.DO33_DOCCORPORIF R2 WITH (NOLOCK) ON R1.DO33_DITTA_CG18 = R2.DO33_DITTA_CG18 AND R1.DO33_NUMREG_CO99 = R2.DO33_NUMREGRIF_CO99 AND R1.DO33_PROGRIGA = R2.DO33_PROGRIGARIF_DO30
                INNER JOIN dbo.DO11_DOCTESTATA T2 WITH (NOLOCK) ON R2.DO33_DITTA_CG18 = T2.DO11_DITTA_CG18 AND R2.DO33_NUMREG_CO99 = T2.DO11_NUMREG_CO99
                INNER JOIN dbo.DO11_DOCTESTATA T_DEP WITH (NOLOCK) ON T2.DO11_DITTA_CG18 = T_DEP.DO11_DITTA_CG18 AND T2.DO11_NUMREGCOL_CO99 = T_DEP.DO11_NUMREG_CO99
                INNER JOIN dbo.DO33_DOCCORPORIF R_COL WITH (NOLOCK) ON T_DEP.DO11_DITTA_CG18 = R_COL.DO33_DITTA_CG18 AND T_DEP.DO11_NUMREG_CO99 = R_COL.DO33_NUMREGRIF_CO99
                INNER JOIN dbo.DO11_DOCTESTATA T_COL_DDT WITH (NOLOCK) ON R_COL.DO33_DITTA_CG18 = T_COL_DDT.DO11_DITTA_CG18 AND R_COL.DO33_NUMREG_CO99 = T_COL_DDT.DO11_NUMREG_CO99
                WHERE R1.DO33_DITTA_CG18 = B.DO30_DITTA_CG18_OC 
                  AND R1.DO33_NUMREGRIF_CO99 = B.DO30_NUMREG_CO99_OC 
                  AND (T_COL_DDT.DO11_TIPODOC = 1 OR (T_COL_DDT.DO11_TIPODOC = 5 AND T_COL_DDT.DO11_STIPODOC = 2))
            ) AS X
        ) AS DDT 
        WHERE (DO30_OC.DO30_INDTIPORIGA <> 0 OR ISNULL(MG66.MG66_INDFITTIZIO, 0) <> 0) 
          AND DDT.DATA_DDT IS NOT NULL;

        -- -------------------------------------------------------------------------------------------------------------
        -- REGOLA 99: UNIVERSAL ROLLBACK / PARACADUTE RIGA ORFANA (Stato Storico - Priorita 0)
        -- Business Logic (Rev. 21, 22, 24, 26): Funziona come "rete di sicurezza" per righe orfane.
        -- Se una riga d'ordine in passato ha raggiunto uno stato avanzato (es. 10051 ODL o 10063 PKL), ma l'utente ha
        -- successivamente cancellato fisicamente il documento a valle (es. eliminato l'ODL o eliminata la Packing List),
        -- la riga non soddisferà più nessuna delle Regole 01-13.
        -- In assenza di regole vincenti, la Regola 99 interroga lo storico cronologico CO4I_STATISTORICO e ripristina
        -- l'ultimo stato valido conosciuto precedente alla cancellazione.
        --
        -- PROTEZIONE DEI PORTI SICURI (SAFE HARBORS):
        -- La Regola 99 NON deve assolutamente toccare né retrocedere righe che si trovano nei seguenti 5 Porti Sicuri:
        --   - 10052: RTP (Versamento Finale a Magazzino)
        --   - 10079: C/Lavoro Esterno Virtuale
        --   - 10054: Ordine a Fornitore
        --   - 10068: Riga Annullata
        --   - 10055: DIBA Non Necessaria (Introdotto nella Rev. 26)
        -- -------------------------------------------------------------------------------------------------------------
        INSERT INTO #CandidatiStato 
        SELECT 
            B.DO30_GUID, B.DO11_NUMDOC_OC, B.DO11_SEZDOC_OC, B.DO30_NUMREG_CO99_OC, B.DO30_PROGRIGA_OC, B.DO30_PROGVISUASTA_OC, 
            B.CO4H_IDSTATO_CO4C_ATTUALE, 
            HIST.CO4I_IDSTATO_CO4C, 
            HIST.CO4I_DATAGG, 
            'Regola 99 - Ripristino stato (Documento orfano/cancellato)', 0 
        FROM #BaseDatiRiga B
        CROSS APPLY (
            SELECT TOP 1 S.CO4I_IDSTATO_CO4C, S.CO4I_DATAGG
            FROM dbo.CO4I_STATISTORICO S WITH (NOLOCK)
            WHERE S.CO4I_GUID = B.DO30_GUID 
              AND S.CO4I_IDSTATO_CO4C <> B.CO4H_IDSTATO_CO4C_ATTUALE
              AND S.CO4I_IDSTATO_CO4C NOT IN (10051, 10073, 10072, 10080, 10069, 10081, 10070, 10071, 10074, 10082, 10075, 10083) 
            ORDER BY S.CO4I_ID DESC
        ) AS HIST
        WHERE B.CO4H_IDSTATO_CO4C_ATTUALE >= 10051
          AND B.CO4H_IDSTATO_CO4C_ATTUALE NOT IN (10052, 10079, 10054, 10068, 10055) -- Blindatura dei 5 Porti Sicuri
          AND NOT EXISTS (SELECT 1 FROM #CandidatiStato C WHERE C.DO30_GUID = B.DO30_GUID);

        -- =============================================================================================================
        -- FASE 3: MOTORE DI RANKING E RISOLUZIONE DEI CONFLITTI (CLASSIFICA STATI)
        -- =============================================================================================================
        -- Questa fase aggrega tutti i candidati generati per ciascun DO30_GUID e calcola la classifica deterministica.
        -- La clausola fondamentale:
        --     ROW_NUMBER() OVER (PARTITION BY DO30_GUID ORDER BY DataEvento DESC, PrioritaSequenza DESC) AS Rn
        -- garantisce che:
        --   1) Prevale l'evento con DataEvento più recente (cronologia reale degli eventi).
        --   2) A parità di data (stesso giorno), prevale l'evento con PrioritaSequenza più alta (stato più a valle).
        -- Il candidato con Rn = 1 è eletto "Vincitore Assoluto" e rappresenta il nuovo stato valido per la riga.
        RAISERROR('>> Inizio FASE 3: Risoluzione conflitti e calcolo Classifica Ranking (Rn = 1)...', 10, 1) WITH NOWAIT;
        
        WITH ClassificaStati AS (
            SELECT DO30_GUID, DO11_NUMDOC, DO11_SEZDOC, DO30_NUMREG_CO99, DO30_PROGRIGA, DO30_PROGVISUASTA, 
                   CO4H_IDSTATO_CO4C_ATTUALE, CO4H_IDSTATO_CO4C_NEW, OrigineRegola, DataEvento, PrioritaSequenza,
                   ROW_NUMBER() OVER (PARTITION BY DO30_GUID ORDER BY DataEvento DESC, PrioritaSequenza DESC) AS Rn
            FROM #CandidatiStato
        )
        SELECT * INTO #ClassificaStati FROM ClassificaStati;
        
        -- =============================================================================================================
        -- FASE 4: OUTPUT DIAGNOSTICO VERBOSO (DRYOUT) O SCRITTURA TRANSAZIONALE COMMIT/ROLLBACK
        -- =============================================================================================================
        -- Aderendo rigorosamente alla Regola 3 di GEMINI.MD:
        -- - Se @ModalitaDryRun = 1: NESSUNA modifica viene scritta nel database. Viene invece prodotto un output
        --   verboso e tabellare che elenca esattamente le regole valutate, le date e le transizioni di stato proposte.
        -- - Se @ModalitaDryRun = 0: L'aggiornamento viene eseguito all'interno di una transazione esplicita protetta.
        RAISERROR('>> Inizio FASE 4: Generazione Output DryOut o Esecuzione Transazionale Scrittura...', 10, 1) WITH NOWAIT;
        
        IF @ModalitaDryRun = 1
        BEGIN
            -- ---------------------------------------------------------------------------------------------------------
            -- RAMO A: MODALITA DRYOUT VERBOSA (SIMULAZIONE NON DISTRUTTIVA)
            -- ---------------------------------------------------------------------------------------------------------
            IF @TargetGUID IS NOT NULL
            BEGIN
                -- Sotto-caso A1: Focus su singola riga di DEBUG.
                -- Mostra TUTTI i candidati che hanno concorso al ranking, ordinati per Rn, permettendo di capire
                -- esattamente quale regola si è classificata al 1° posto, quale al 2°, e perché.
                SELECT 
                    DO30_GUID AS [GUID Riga], 
                    Rn AS [Ranking], 
                    DO11_NUMDOC AS [Num. Doc. OC], 
                    DO11_SEZDOC AS [Sez. Doc.], 
                    DO30_NUMREG_CO99 AS [Num. Reg. OC], 
                    DO30_PROGRIGA AS [Prog. Riga Int.], 
                    DO30_PROGVISUASTA AS [Prog. Vis. OC], 
                    OrigineRegola AS [Regola Valutata], 
                    DataEvento AS [Data Evento Calcolata], 
                    CO4H_IDSTATO_CO4C_ATTUALE AS [Stato Attuale], 
                    CO4H_IDSTATO_CO4C_NEW AS [Nuovo Stato Proposto]
                FROM #ClassificaStati WITH (NOLOCK) 
                ORDER BY Rn;
            END
            ELSE
            BEGIN
                -- Sotto-caso A2: Esecuzione Massiva Dry-Run.
                -- Mostra l'elenco complessivo di tutte le righe a sistema che cambierebbero stato (Rn = 1 e StatoAttuale <> NuovoStato).
                SELECT 
                    OrigineRegola AS [Regola Vincente], 
                    DO11_NUMDOC AS [Num. Doc. OC], 
                    DO11_SEZDOC AS [Sez. Doc.], 
                    DO30_NUMREG_CO99 AS [Num. Reg. OC], 
                    DO30_PROGRIGA AS [Prog. Riga Int.], 
                    DO30_PROGVISUASTA AS [Prog. Vis. OC], 
                    DataEvento AS [Data Evento], 
                    CO4H_IDSTATO_CO4C_ATTUALE AS [Stato Attuale], 
                    CO4H_IDSTATO_CO4C_NEW AS [Nuovo Stato Proposto]
                FROM #ClassificaStati WITH (NOLOCK) 
                WHERE Rn = 1 AND CO4H_IDSTATO_CO4C_ATTUALE <> CO4H_IDSTATO_CO4C_NEW 
                ORDER BY DataEvento DESC, [Num. Doc. OC], [Prog. Vis. OC];
            END
        END
        ELSE
        BEGIN
            -- ---------------------------------------------------------------------------------------------------------
            -- RAMO B: SCRITTURA REALE TRANSAZIONALE (COMMIT / ROLLBACK)
            -- ---------------------------------------------------------------------------------------------------------
            IF @TargetGUID IS NOT NULL 
            BEGIN
                -- Blocco di salvaguardia: impedisce scritture reali accidentali se l'operatore ha lasciato valorizzati
                -- i filtri di debug, costringendolo a rimuovere esplicitamente i filtri o confermare l'intento.
                PRINT 'Esecuzione Reale bloccata cautelativamente: Parametri di DEBUG attivi. Disabilitare i filtri riga per scrivere.';
            END
            ELSE
            BEGIN
                BEGIN TRANSACTION;
                
                -- Aggiornamento atomico della tabella CO4H_STATIATTUALI per le sole righe dove lo stato vincente è mutato
                UPDATE ATTUALI 
                SET ATTUALI.CO4H_IDSTATO_CO4C = WINNER.CO4H_IDSTATO_CO4C_NEW 
                FROM dbo.CO4H_STATIATTUALI AS ATTUALI 
                INNER JOIN #ClassificaStati AS WINNER ON ATTUALI.CO4H_GUID = WINNER.DO30_GUID 
                WHERE WINNER.Rn = 1 
                  AND ATTUALI.CO4H_IDSTATO_CO4C <> WINNER.CO4H_IDSTATO_CO4C_NEW;
                
                COMMIT TRANSACTION;
                RAISERROR('>> Transazione completata con successo: modifiche salvate a Database.', 10, 1) WITH NOWAIT;
            END
        END

        SET @FineEsecuzione = SYSDATETIME();
        PRINT 'Elaborazione completata in: ' + CAST(DATEDIFF(MILLISECOND, @InizioEsecuzione, @FineEsecuzione) AS VARCHAR) + ' ms.';

    END TRY
    BEGIN CATCH
        -- Gestione Rollback sicuro: se una transazione è rimasta aperta in caso di errore, esegue il rollback immediato
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErroreMessaggio = ERROR_MESSAGE();
        PRINT '!!! ERRORE CRITICO RILEVATO IN ESECUZIONE: ' + @ErroreMessaggio;
        THROW;
    END CATCH
    
    -- Cleanup controllato delle tabelle temporanee allocate in tempdb
    IF OBJECT_ID('tempdb..#TargetGUIDs') IS NOT NULL DROP TABLE #TargetGUIDs;
    IF OBJECT_ID('tempdb..#HistoryBypass') IS NOT NULL DROP TABLE #HistoryBypass;
    IF OBJECT_ID('tempdb..#BaseDatiRiga') IS NOT NULL DROP TABLE #BaseDatiRiga;
    IF OBJECT_ID('tempdb..#DateDDT') IS NOT NULL DROP TABLE #DateDDT;
    IF OBJECT_ID('tempdb..#CandidatiStato') IS NOT NULL DROP TABLE #CandidatiStato;
    IF OBJECT_ID('tempdb..#ClassificaStati') IS NOT NULL DROP TABLE #ClassificaStati;
END;
GO
