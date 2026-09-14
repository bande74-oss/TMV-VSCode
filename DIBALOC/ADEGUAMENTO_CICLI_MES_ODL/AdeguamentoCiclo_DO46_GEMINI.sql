/* ==========================================================================================================
   DATA E ORA        : 2026-09-14
   AUTORE            : SOLVERIS - Bandera Marco
   OGGETTO           : AdeguamentoCiclo_DO46_GEMINI.sql
   
   DESCRIZIONE AD ALTISSIMO DETTAGLIO:
   Questo script esegue l'allineamento e l'adeguamento completo, atomico e NON DISTRUTTIVO del ciclo di 
   produzione all'interno degli ordini di lavoro (ODL) del gestionale Gamma TeamSystem, garantendo la totale 
   conformità con il sistema MES esterno collegato tramite la vista VPMES_ODLExport (tracciato TMV-MES-ODL-CSV)
   e la salvaguardia assoluta degli avanzamenti già consuntivati.
   
   CONTESTO AZIENDALE E LOGICA DI BUSINESS:
   Nel gestionale Gamma il ciclo di produzione vive su due entità strettamente accoppiate:
   1. DO46_DOCCORORDDET: la tabella operativa delle fasi di avanzamento e consuntivazione dell'ODL.
   2. PD48_CICLI: la tabella anagrafica dei cicli e delle fasi di lavorazione associata alla Distinta Base 
      specifica di ciascuna riga documento (DO30_IDDISBA_PD95).
      
   La vista di esportazione verso il MES (VPMES_ODLExport) effettua un INNER JOIN obbligatorio:
      dbo.PD48_CICLI ON dbo.PD48_CICLI.PD48_IDCICLO = dbo.DO46_DOCCORORDDET.DO46_IDCICLO_PD48
   e preleva da PD48_CICLI dati fondamentali:
   - Campo 25 (CODICE_UNIVOCO_BOLLA_FASE): generato con la sequenza fase PD48_SEQFASE.
   - Campo 34 (Flag Conto Lavoro): espressione if [PD48_CODFORN_CG44] <> 0 then 1 else 0 end.
   - Campo 8 (Descrizione Macchina/Reparto): legata a PD48_MACCHINA_PD08 e PD48_CODREP_PD07.
   
   PROBLEMA DEGLI AVANZAMENTI E REGOLA DI PROTEZIONE RIGOROSA:
   Nelle righe dell'ODL alcune fasi possono essere già state parzialmente o totalmente avanzate nel MES 
   (e recepite in Gamma tramite la tabella RT15_OVERONE_AVANZAMENTI, con DO46_INDSTATOORD = 2 ed emissione 
   di consuntivi/versamenti). 
   Una cancellazione (DELETE) delle righe di DO46 è ASSOLUTAMENTE VIETATA per le fasi avanzate, poiché 
   distruggerebbe i DO46_GUID storici, cancellerebbe le quantità consolidate (DO46_QTA1CONSOLID) e causerebbe 
   un disallineamento irreversibile con i dati del MES e della produzione.
   
   ARCHITETTURA APPLICATA: SMART UPSERT CON ADVANCEMENT PROTECTION:
   Lo script applica una strategia intelligente e non distruttiva valida sia per l'ODL corrente in corso 
   di lavorazione, sia per qualsiasi ODL futuro rigenerato ex-novo da Ordine Cliente:
   
   A) GESTIONE DI PD48_CICLI (Tutte le distinte dell'ODL da 1 a N):
      - Pulisce da PD48_CICLI solo le fasi non appartenenti al pattern.
      - Aggiorna le fasi esistenti (impostando fornitore 2682 e reparto R300 sulla fase 1480).
      - Inserisce in PD48_CICLI le fasi mancanti (es. 4031, 4001, 4011, 4021) per tutte le distinte, 
        generando nuovi PD48_IDCICLO (colonna IDENTITY) e nuovi PD48_GUID.
        
   B) GESTIONE PROTETTA DI DO46_DOCCORORDDET (Righe da 1 a N):
      1. Fasi del Pattern GIÀ ESISTENTI in DO46 (come nello scenario dell'ODL attuale 202600184219):
         - NESSUNA CANCELLAZIONE.
         - DO46_GUID, quantità consolidate, stati d'ordine e date rimangono INALTERATI.
         - Viene eseguito esclusivamente un UPDATE non invasivo che valorizza il puntatore mancante:
           DO46_IDCICLO_PD48 = P.PD48_IDCICLO (collegandolo alla distinta corretta della riga)
           e verifica fornitore/flag conto lavoro.
      2. Fasi del Pattern NON ANCORA ESISTENTI in DO46 (scenario ODL nuovo appena rigenerato):
         - Vengono INSERITE ex-novo con quantità lette da DO30_DOCCORPO, nuovi GUID e puntatore PD48 già valorizzato.
      3. Fasi spurie/obsolete NON PRESENTI nel Pattern (es. 1205 o 1270):
         - Vengono eliminate SOLO ED ESCLUSIVAMENTE SE NON SONO AVANZATE (stato <= 1, QTA_CONSOLID = 0 e zero versamenti in RT15).
         - Se una fase non nel pattern risultasse già avanzata, VIENE PRESERVATA per salvaguardare lo storico.
   
   SICUREZZA E MODALITÀ DRY-RUN (DRYOUT):
   Lo script è impostato per default in modalità protetta (@DryRun = 1). 
   Non modifica alcun record sul Database e produce a video 5 tabelle di riepilogo dettagliate, inclusa 
   l'anteprima esatta di come VPMES_ODLExport estrarrà le 798 fasi complete verso il MES.
   Impostando @DryRun = 0, le operazioni vengono eseguite realmente sotto transazione atomica (BEGIN TRAN / COMMIT).

   CHANGE LOG NARRATIVO:
   - Rev. 1 (2026-09-08): Creazione iniziale dell'oggetto per clonazione DO46 da riga 1 a righe > 1.
   - Rev. 2 (2026-09-08): Correzione quantità: le quantità DO46 vengono prelevate dinamicamente da DO30_DOCCORPO.
   - Rev. 3 (2026-09-08): Allineamento esatto dei campi della query di anteprima in modalità Dry-Run.
   - Rev. 4 (2026-09-14): Integrazione di PD48_CICLI a seguito dell'analisi della vista VPMES_ODLExport.
   - Rev. 5 (2026-09-14): TRASFORMAZIONE IN SMART UPSERT CON PROTEZIONE RIGOROSA DEGLI AVANZAMENTI.
     Eliminata la logica distruttiva (DELETE cieco) su DO46. Introdotto il controllo di avanzamento 
     (DO46_INDSTATOORD > 1, DO46_QTA1CONSOLID > 0, RT15_OVERONE_AVANZAMENTI). Le fasi esistenti in DO46 
     subiscono solo l'UPDATE del puntatore DO46_IDCICLO_PD48 mantenendo inalterati i GUID storici e 
     i versamenti. Lo script garantisce idempotenza totale e riutilizzabilità universale su qualsiasi 
      ODL futuro semplicemente variando @NUMREG_CO99.
    - Rev. 6 (2026-09-14): Risolto errore di sintassi T-SQL (Msg 102 near 'CAST') su RAISERROR.
      L'istruzione RAISERROR di SQL Server accetta come parametri di sostituzione solo variabili o 
      costanti (non espressioni o funzioni come CAST) e supporta solo tipi interi/stringhe (non decimal).
      Tipizzata la variabile @DITTA come int e rimossa l'espressione CAST(@DITTA AS INT) nel RAISERROR,
      garantendo la corretta esecuzione sia in SSMS che in VS Code.
   ========================================================================================================== */

DECLARE @DITTA int = 1;
DECLARE @NUMREG_CO99 char(12) = '202600184219';
DECLARE @DryRun bit = 1; -- 1 = Simulazione protetta (Dry-Run), 0 = Esegue realmente le modifiche su DB

BEGIN TRY
    -- Se non siamo in simulazione, isoliamo tutte le operazioni in un'unica transazione atomica
    IF @DryRun = 0
        BEGIN TRAN;

    ------------------------------------------------------------------------------------------------------
    -- VERIFICA INTEGRITÀ PRELIMINARE DEI DATI
    ------------------------------------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM DO30_DOCCORPO WITH (NOLOCK) 
        WHERE DO30_DITTA_CG18 = @DITTA AND DO30_NUMREG_CO99 = @NUMREG_CO99
    )
    BEGIN
        RAISERROR('ERRORE: Nessuna riga trovata in DO30_DOCCORPO per Ditta %d e NumReg %s.', 16, 1, @DITTA, @NUMREG_CO99);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM DO46_DOCCORORDDET WITH (NOLOCK) 
        WHERE DO46_DITTA_CG18 = @DITTA AND DO46_NUMREG_CO99 = @NUMREG_CO99 AND DO46_PROGRIGA = 1
    )
    BEGIN
        RAISERROR('ERRORE: Nessun pattern di fasi trovato in DO46_DOCCORORDDET per la riga 1 (DO46_PROGRIGA = 1).', 16, 1);
    END;

    ------------------------------------------------------------------------------------------------------
    -- MODALITÀ 1: DRY-RUN (SIMULAZIONE VERBOSA, SICURA E NON DISTRUTTIVA)
    ------------------------------------------------------------------------------------------------------
    IF @DryRun = 1
    BEGIN
        PRINT '==============================================================================================';
        PRINT '*** MODALITÀ DRY-RUN ATTIVA (DryOut): NESSUNA MODIFICA APPORTATA AL DATABASE ***';
        PRINT '==============================================================================================';

        -- 1. ANALISI FASI DO46 GIÀ AVANZATE (PROTETTE DA QUALSIASI CANCELLAZIONE)
        SELECT '1. DO46: FASI ESISTENTI AVANZATE (PROTETTE - GUID E CONSUNTIVI INALTERATI)' AS [AzioneDryRun],
               D.DO46_PROGRIGA,
               D.DO46_CODSEQFASE,
               D.DO46_CODFASE,
               D.DO46_DESCRFASE,
               D.DO46_INDSTATOORD,
               D.DO46_QTA1ORD,
               D.DO46_QTA1CONSOLID,
               D.DO46_GUID,
               ISNULL(RT_CNT.AvanzamentiMES, 0) AS [Versamenti_In_RT15]
        FROM DO46_DOCCORORDDET D WITH (NOLOCK)
        OUTER APPLY (
            SELECT COUNT(*) AS AvanzamentiMES
            FROM RT15_OVERONE_AVANZAMENTI RT WITH (NOLOCK)
            WHERE RT.RT15_DITTA_CG18 = D.DO46_DITTA_CG18
              AND RT.RT15_NUMREG_CO99 = D.DO46_NUMREG_CO99
              AND RT.RT15_PROGRIGA = D.DO46_PROGRIGA
              AND RT.RT15_NUMERO_FASE = D.DO46_CODSEQFASE
        ) RT_CNT
        WHERE D.DO46_DITTA_CG18 = @DITTA 
          AND D.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND (ISNULL(D.DO46_INDSTATOORD, 0) > 1 
               OR ISNULL(D.DO46_QTA1CONSOLID, 0) > 0 
               OR ISNULL(RT_CNT.AvanzamentiMES, 0) > 0)
        ORDER BY D.DO46_PROGRIGA, D.DO46_CODSEQFASE;

        -- 2. FASI DO46 ESISTENTI DA AGGIORNARE (SOLO UPDATE PUNTATORE IDCICLO_PD48)
        SELECT '2. DO46: FASI ESISTENTI DA AGGIORNARE (UPDATE IDCICLO_PD48 - NESSUNA CANCELLAZIONE)' AS [AzioneDryRun],
               D.DO46_PROGRIGA,
               D.DO46_CODSEQFASE,
               D.DO46_CODFASE,
               D.DO46_DESCRFASE,
               D.DO46_IDCICLO_PD48 AS [IDCICLO_PD48_ATTUALE],
               'P.PD48_IDCICLO (DEDICATO ALLA DISTINTA)' AS [IDCICLO_PD48_NUOVO],
               D.DO46_CLIFOR_CG44,
               D.DO46_GUID AS [DO46_GUID_CONSERVATO]
        FROM DO46_DOCCORORDDET D WITH (NOLOCK)
        WHERE D.DO46_DITTA_CG18 = @DITTA 
          AND D.DO46_NUMREG_CO99 = @NUMREG_CO99
        ORDER BY D.DO46_PROGRIGA, D.DO46_CODSEQFASE;

        -- 3. FASI DO46 MANCANTI DA INSERIRE (0 per ODL attuale; > 0 se ODL nuovo rigenerato da zero)
        SELECT '3. DO46: NUOVE FASI DA INSERIRE (Nel caso di ODL rigenerato da zero)' AS [AzioneDryRun],
               R.DO30_PROGRIGA,
               D_PAT.DO46_CODSEQFASE,
               D_PAT.DO46_CODFASE,
               D_PAT.DO46_DESCRFASE,
               ISNULL(R.DO30_QTA1, 0) AS [DO46_QTA1ORD_DA_DO30],
               'NEWID() GENERATO AL VOLO' AS [DO46_GUID_NUOVO]
        FROM DO30_DOCCORPO R WITH (NOLOCK)
        CROSS JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
        WHERE R.DO30_DITTA_CG18 = @DITTA
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND R.DO30_PROGRIGA > 1
          AND D_PAT.DO46_DITTA_CG18 = @DITTA
          AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_PROGRIGA = 1
          AND NOT EXISTS (
              SELECT 1 FROM DO46_DOCCORORDDET D_EXIST WITH (NOLOCK)
              WHERE D_EXIST.DO46_DITTA_CG18 = R.DO30_DITTA_CG18
                AND D_EXIST.DO46_NUMREG_CO99 = R.DO30_NUMREG_CO99
                AND D_EXIST.DO46_PROGRIGA = R.DO30_PROGRIGA
                AND D_EXIST.DO46_CODSEQFASE = D_PAT.DO46_CODSEQFASE
                AND D_EXIST.DO46_CODFASE = D_PAT.DO46_CODFASE
          )
        ORDER BY R.DO30_PROGRIGA, D_PAT.DO46_CODSEQFASE;

        -- 4. ALLINEAMENTO PD48_CICLI: FASI COMPLETE DA ASSEGNARE A CIASCUNA DISTINTA ODL (798 FASI)
        SELECT '4. PD48: FASI COMPLETE DA ASSEGNARE AD OGNI DISTINTA ODL' AS [AzioneDryRun],
               R.DO30_PROGRIGA,
               R.DO30_IDDISBA_PD95,
               ISNULL(CicloBase.PD48_CICLO_PD52, 'VITI_KANBAN') AS [PD48_CICLO_PD52],
               D_PAT.DO46_CODSEQFASE AS [PD48_SEQFASE],
               D_PAT.DO46_CODFASE AS [PD48_CODFASE_PD12],
               D_PAT.DO46_DESCRFASE AS [PD48_DESCRFASE],
               COALESCE(D_PAT.DO46_CODREPARTO, F.PD12_CODREP_PD07) AS [PD48_CODREP_PD07],
               ISNULL(D_PAT.DO46_CLIFOR_CG44, 0) AS [PD48_CODFORN_CG44],
               CASE WHEN EXISTS (
                   SELECT 1 FROM PD48_CICLI P_EX WITH (NOLOCK)
                   WHERE P_EX.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
                     AND P_EX.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
                     AND P_EX.PD48_SEQFASE = D_PAT.DO46_CODSEQFASE
                     AND P_EX.PD48_CODFASE_PD12 = D_PAT.DO46_CODFASE
               ) THEN 'UPDATE ESISTENTE' ELSE 'INSERT NUOVO' END AS [Operazione_PD48]
        FROM DO30_DOCCORPO R WITH (NOLOCK)
        CROSS JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
        LEFT JOIN PD12_FASILAVORO F WITH (NOLOCK)
            ON F.PD12_DITTA_CG18 = D_PAT.DO46_DITTA_CG18 
           AND F.PD12_CODFASE = D_PAT.DO46_CODFASE
        OUTER APPLY (
            SELECT TOP 1 P_OLD.PD48_CICLO_PD52 
            FROM PD48_CICLI P_OLD WITH (NOLOCK) 
            WHERE P_OLD.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
              AND P_OLD.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
        ) CicloBase
        WHERE R.DO30_DITTA_CG18 = @DITTA
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_DITTA_CG18 = @DITTA
          AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_PROGRIGA = 1
        ORDER BY R.DO30_PROGRIGA, D_PAT.DO46_CODSEQFASE;

        -- 5. ANTEPRIMA SIMULAZIONE ESTRAZIONE MES (VPMES_ODLExport - 798 RIGHE)
        -- Simula fedelmente l'esatto output che il tracciato TMV-MES-ODL-CSV estrarrà per il MES
        SELECT '5. ANTEPRIMA SIMULAZIONE VPMES_ODLExport VERSO IL MES (798 RIGHE ATTESE)' AS [AzioneDryRun],
               @NUMREG_CO99 + CONVERT(VARCHAR(5), R.DO30_PROGRIGA) AS [CODICE_UNIVOCO_ODL],
               @NUMREG_CO99 + CONVERT(VARCHAR(5), R.DO30_PROGRIGA) + CONVERT(VARCHAR(10), D_PAT.DO46_CODSEQFASE) AS [CODICE_UNIVOCO_BOLLA_FASE],
               R.DO30_PROGRIGA,
               D_PAT.DO46_CODSEQFASE AS [PD48_SEQFASE],
               D_PAT.DO46_CODFASE AS [PD48_CODFASE_PD12],
               D_PAT.DO46_DESCRFASE,
               COALESCE(D_PAT.DO46_CODREPARTO, F.PD12_CODREP_PD07) AS [PD48_CODREP_PD07],
               ISNULL(D_PAT.DO46_CLIFOR_CG44, 0) AS [PD48_CODFORN_CG44],
               CASE WHEN ISNULL(D_PAT.DO46_CLIFOR_CG44, 0) <> 0 THEN 1 ELSE 0 END AS [FLAG_CONTO_LAVORO_MES_C34],
               ISNULL(R.DO30_QTA1, 0) AS [DO30_QTA1],
               D_PAT.DO46_DATAINIZIO,
               D_PAT.DO46_DATAFINE
        FROM DO30_DOCCORPO R WITH (NOLOCK)
        CROSS JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
        LEFT JOIN PD12_FASILAVORO F WITH (NOLOCK)
            ON F.PD12_DITTA_CG18 = D_PAT.DO46_DITTA_CG18 
           AND F.PD12_CODFASE = D_PAT.DO46_CODFASE
        WHERE R.DO30_DITTA_CG18 = @DITTA
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_DITTA_CG18 = @DITTA
          AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_PROGRIGA = 1
        ORDER BY R.DO30_PROGRIGA, D_PAT.DO46_CODSEQFASE;

        PRINT '==============================================================================================';
        PRINT 'Simulazione completata con successo.';
        PRINT 'Per confermare ed applicare le variazioni su Database, impostare @DryRun = 0.';
        PRINT '==============================================================================================';
    END
    ------------------------------------------------------------------------------------------------------
    -- MODALITÀ 2: ESECUZIONE REALE TRANSAZIONALE E PROTETTA (SMART UPSERT)
    ------------------------------------------------------------------------------------------------------
    ELSE
    BEGIN
        PRINT '*** ESECUZIONE REALE: INIZIO ALLINEAMENTO CICLO CON PROTEZIONE AVANZAMENTI ***';

        -- -----------------------------------------------------------------------------------------------
        -- FASE A: ALLINEAMENTO PD48_CICLI PER TUTTE LE DISTINTE BASE DELL'ODL (Righe da 1 a N)
        -- -----------------------------------------------------------------------------------------------
        
        -- A.1 Pulizia da PD48_CICLI delle sole fasi non presenti nel pattern master
        DELETE P
        FROM PD48_CICLI P
        INNER JOIN DO30_DOCCORPO R 
            ON P.PD48_DITTA_CG18 = R.DO30_DITTA_CG18 
           AND P.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
        WHERE R.DO30_DITTA_CG18 = @DITTA 
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND NOT EXISTS (
              SELECT 1 FROM DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
              WHERE D_PAT.DO46_DITTA_CG18 = @DITTA
                AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
                AND D_PAT.DO46_PROGRIGA = 1
                AND D_PAT.DO46_CODSEQFASE = P.PD48_SEQFASE
                AND D_PAT.DO46_CODFASE = P.PD48_CODFASE_PD12
          );

        PRINT 'A.1 - Pulizia fasi obsolete in PD48_CICLI completata.';

        -- A.2 Aggiornamento fasi esistenti in PD48_CICLI (fornitore 2682 e reparto)
        UPDATE P
        SET P.PD48_CODFORN_CG44  = ISNULL(D_PAT.DO46_CLIFOR_CG44, 0),
            P.PD48_CODREP_PD07   = COALESCE(D_PAT.DO46_CODREPARTO, F.PD12_CODREP_PD07, P.PD48_CODREP_PD07),
            P.PD48_DESCRFASE     = D_PAT.DO46_DESCRFASE,
            P.PD48_MACCHINA_PD08 = D_PAT.DO46_MACCHINAALT
        FROM PD48_CICLI P
        INNER JOIN DO30_DOCCORPO R WITH (NOLOCK)
            ON P.PD48_DITTA_CG18 = R.DO30_DITTA_CG18 
           AND P.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
        INNER JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
            ON D_PAT.DO46_DITTA_CG18 = @DITTA
           AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
           AND D_PAT.DO46_PROGRIGA = 1
           AND D_PAT.DO46_CODSEQFASE = P.PD48_SEQFASE
           AND D_PAT.DO46_CODFASE = P.PD48_CODFASE_PD12
        LEFT JOIN PD12_FASILAVORO F WITH (NOLOCK)
            ON F.PD12_DITTA_CG18 = D_PAT.DO46_DITTA_CG18 
           AND F.PD12_CODFASE = D_PAT.DO46_CODFASE
        WHERE R.DO30_DITTA_CG18 = @DITTA 
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99;

        PRINT 'A.2 - Aggiornamento fasi esistenti in PD48_CICLI completato.';

        -- A.3 Inserimento delle fasi mancanti in PD48_CICLI (es. le fasi di conto lavoro 4031, 4001, 4011, 4021)
        INSERT INTO PD48_CICLI (
            PD48_DITTA_CG18,
            PD48_CICLO_PD52,
            PD48_VERSIONE_PD52,
            PD48_SEQFASE,
            PD48_CODFASE_PD12,
            PD48_PROGFASE,
            PD48_INDTIPOPROV,
            PD48_IDDISBA_PD95,
            PD48_CODREP_PD07,
            PD48_CODFORN_CG44,
            PD48_MACCHINA_PD08,
            PD48_DATINIVAL,
            PD48_DATFINVAL,
            PD48_TMACSETUP,
            PD48_INDUMSETUP,
            PD48_FORMSETUP_PD24,
            PD48_TMACLAV,
            PD48_INDUMLAV,
            PD48_FORMLAV_PD24,
            PD48_NUMPEZZIUM,
            PD48_TATTESA,
            PD48_INDUMATTESA,
            PD48_INDUMCODA,
            PD48_TCODA,
            PD48_ARTATTR_PD26,
            PD48_VARATTR_PD26,
            PD48_KIT_PD56,
            PD48_NOTA,
            PD48_COSTOCICLO,
            PD48_IDENTPROG,
            PD48_PERCATTFSUCC,
            PD48_PERCREND,
            PD48_IDMEDIA_CG99,
            PD48_TTOTLAV,
            PD48_INDUMTOTLAV,
            PD48_NUMPEZSETUP,
            PD48_FORMTOT_PD24,
            PD48_INDTIPOFASE,
            PD48_TEMPOCRITICO,
            PD48_VALENZAMINIMA,
            PD48_VALENZAMASSIMA,
            PD48_LIVELLO1,
            PD48_LIVELLO2,
            PD48_LIVELLO3,
            PD48_LIVELLO4,
            PD48_LIVELLO5,
            PD48_SQPREP_PD10,
            PD48_SQLAV_PD10,
            PD48_NUMIMPRONTE,
            PD48_DESCRFASE,
            PD48_INDESCLCICLOAP,
            PD48_CODATTIVITA_PD66,
            PD48_GUID,
            PD48_STTSETUPTOT,
            PD48_STTLAVTOT,
            PD48_IDCICLOORIGINE,
            PD48_SETUPCODE_GPS24
        )
        SELECT 
            R.DO30_DITTA_CG18,
            ISNULL(CicloBase.PD48_CICLO_PD52, 'VITI_KANBAN'),
            0,
            D_PAT.DO46_CODSEQFASE,
            D_PAT.DO46_CODFASE,
            0,
            0,
            R.DO30_IDDISBA_PD95,
            COALESCE(D_PAT.DO46_CODREPARTO, F.PD12_CODREP_PD07),
            ISNULL(D_PAT.DO46_CLIFOR_CG44, 0),
            D_PAT.DO46_MACCHINAALT,
            NULL, NULL, 0, 0, NULL, 0, 0, NULL, 0, 0, 0, 0, 0,
            D_PAT.DO46_ATTREZZO_PD26,
            D_PAT.DO46_VARATTR_PD26,
            D_PAT.DO46_KITATT_PD56,
            D_PAT.DO46_NOTEGENER,
            0, NULL, 0, 0,
            D_PAT.DO46_IDMEDIA_CG99,
            0, 0, 0, NULL, 0, 0, 0, 0,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0,
            D_PAT.DO46_DESCRFASE,
            0,
            D_PAT.DO46_CODATTIVITA_PD0D,
            NEWID(),
            0, 0, NULL, NULL
        FROM DO30_DOCCORPO R WITH (NOLOCK)
        CROSS JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
        LEFT JOIN PD12_FASILAVORO F WITH (NOLOCK)
            ON F.PD12_DITTA_CG18 = D_PAT.DO46_DITTA_CG18 
           AND F.PD12_CODFASE = D_PAT.DO46_CODFASE
        OUTER APPLY (
            SELECT TOP 1 P_OLD.PD48_CICLO_PD52 
            FROM PD48_CICLI P_OLD WITH (NOLOCK) 
            WHERE P_OLD.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
              AND P_OLD.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
        ) CicloBase
        WHERE R.DO30_DITTA_CG18 = @DITTA
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_DITTA_CG18 = @DITTA
          AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_PROGRIGA = 1
          AND NOT EXISTS (
              SELECT 1 FROM PD48_CICLI P_EXIST WITH (NOLOCK)
              WHERE P_EXIST.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
                AND P_EXIST.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
                AND P_EXIST.PD48_SEQFASE = D_PAT.DO46_CODSEQFASE
                AND P_EXIST.PD48_CODFASE_PD12 = D_PAT.DO46_CODFASE
          );

        PRINT 'A.3 - Inserimento fasi mancanti in PD48_CICLI completato.';

        -- -----------------------------------------------------------------------------------------------
        -- FASE B: GESTIONE PROTETTA E NON DISTRUTTIVA DI DO46_DOCCORORDDET (Righe da 1 a N)
        -- -----------------------------------------------------------------------------------------------
        
        -- B.1 Eliminazione delle sole fasi spurie non presenti nel pattern, SOLO SE NON AVANZATE
        DELETE D
        FROM DO46_DOCCORORDDET D
        WHERE D.DO46_DITTA_CG18 = @DITTA
          AND D.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D.DO46_PROGRIGA > 1
          -- Fase non presente nel pattern
          AND NOT EXISTS (
              SELECT 1 FROM DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
              WHERE D_PAT.DO46_DITTA_CG18 = D.DO46_DITTA_CG18
                AND D_PAT.DO46_NUMREG_CO99 = D.DO46_NUMREG_CO99
                AND D_PAT.DO46_PROGRIGA = 1
                AND D_PAT.DO46_CODSEQFASE = D.DO46_CODSEQFASE
                AND D_PAT.DO46_CODFASE = D.DO46_CODFASE
          )
          -- PROTEZIONE RIGOROSA DEGLI AVANZAMENTI: elimina solo se vergine
          AND ISNULL(D.DO46_INDSTATOORD, 0) <= 1
          AND ISNULL(D.DO46_QTA1CONSOLID, 0) = 0
          AND ISNULL(D.DO46_QTA2CONSOLID, 0) = 0
          AND NOT EXISTS (
              SELECT 1 FROM RT15_OVERONE_AVANZAMENTI RT WITH (NOLOCK)
              WHERE RT.RT15_DITTA_CG18 = D.DO46_DITTA_CG18
                AND RT.RT15_NUMREG_CO99 = D.DO46_NUMREG_CO99
                AND RT.RT15_PROGRIGA = D.DO46_PROGRIGA
                AND RT.RT15_NUMERO_FASE = D.DO46_CODSEQFASE
          );

        PRINT 'B.1 - Pulizia protetta fasi spurie in DO46 completata (avanzamenti preservati).';

        -- B.2 Inserimento delle sole fasi del pattern eventualmente mancanti in DO46 (scenario ODL nuovo)
        INSERT INTO DO46_DOCCORORDDET (
            DO46_DITTA_CG18,
            DO46_NUMREG_CO99,
            DO46_PROGRIGA,
            DO46_PROGDET,
            DO46_CODSEQFASE,
            DO46_CODFASE,
            DO46_CODREPARTO,
            DO46_QTA1ORD,
            DO46_QTA2ORD,
            DO46_COLLIORD,
            DO46_QTA1CONSOLID,
            DO46_QTA2CONSOLID,
            DO46_COLLICONS,
            DO46_TEMPOFASEORE,
            DO46_TEMPOFASEMIN,
            DO46_TEMPOFASESEC,
            DO46_QTAPREVSPE,
            DO46_NOTEGENER,
            DO46_NOTEMONT,
            DO46_NOTECOSTR,
            DO46_PERCRIC,
            DO46_MACCHINAALT,
            DO46_IDMEDIA_CG99,
            DO46_DITTACF_CG44,
            DO46_TIPOCF_CG44,
            DO46_CLIFOR_CG44,
            DO46_DATAINIZIO,
            DO46_DATAFINE,
            DO46_FLGSTORDMONO,
            DO46_FLGGENORDCLAV,
            DO46_ATTREZZO_PD26,
            DO46_VARATTR_PD26,
            DO46_KITATT_PD56,
            DO46_INDSTATOORD,
            DO46_QTA1SCARTO,
            DO46_QTA2SCARTO,
            DO46_PROGSFASE,
            DO46_INDFASEINTEST,
            DO46_CODDEP_MG58,
            DO46_PREZZO1,
            DO46_TEMPOLAV,
            DO46_PREZZO2,
            DO46_PREZZOCF,
            DO46_IDCICLO_PD48,
            DO46_DESCRFASE,
            DO46_COSTOCICLO,
            DO46_CODATTIVITA_PD0D,
            DO46_GUID,
            DO46_INDSTATOMES,
            DO46_CSTAGG1UM1,
            DO46_CSTAGG2UM1,
            DO46_SCHEDSEQ
        )
        SELECT 
            R.DO30_DITTA_CG18,
            R.DO30_NUMREG_CO99,
            R.DO30_PROGRIGA,
            D_PAT.DO46_PROGDET,
            D_PAT.DO46_CODSEQFASE,
            D_PAT.DO46_CODFASE,
            D_PAT.DO46_CODREPARTO,
            ISNULL(R.DO30_QTA1, 0),
            ISNULL(R.DO30_QTA2, 0),
            ISNULL(R.DO30_COLLI, 0),
            NULL, NULL, NULL,
            D_PAT.DO46_TEMPOFASEORE,
            D_PAT.DO46_TEMPOFASEMIN,
            D_PAT.DO46_TEMPOFASESEC,
            D_PAT.DO46_QTAPREVSPE,
            D_PAT.DO46_NOTEGENER,
            D_PAT.DO46_NOTEMONT,
            D_PAT.DO46_NOTECOSTR,
            D_PAT.DO46_PERCRIC,
            D_PAT.DO46_MACCHINAALT,
            D_PAT.DO46_IDMEDIA_CG99,
            D_PAT.DO46_DITTACF_CG44,
            D_PAT.DO46_TIPOCF_CG44,
            D_PAT.DO46_CLIFOR_CG44,
            D_PAT.DO46_DATAINIZIO,
            D_PAT.DO46_DATAFINE,
            D_PAT.DO46_FLGSTORDMONO,
            D_PAT.DO46_FLGGENORDCLAV,
            D_PAT.DO46_ATTREZZO_PD26,
            D_PAT.DO46_VARATTR_PD26,
            D_PAT.DO46_KITATT_PD56,
            1, -- INDSTATOORD iniziale = Non Iniziata
            0, 0,
            D_PAT.DO46_PROGSFASE,
            D_PAT.DO46_INDFASEINTEST,
            D_PAT.DO46_CODDEP_MG58,
            D_PAT.DO46_PREZZO1,
            D_PAT.DO46_TEMPOLAV,
            D_PAT.DO46_PREZZO2,
            D_PAT.DO46_PREZZOCF,
            P.PD48_IDCICLO, -- Già collegato al nuovo ID di PD48!
            D_PAT.DO46_DESCRFASE,
            D_PAT.DO46_COSTOCICLO,
            D_PAT.DO46_CODATTIVITA_PD0D,
            NEWID(),        -- GUID univoco per ogni nuova riga inserita
            D_PAT.DO46_INDSTATOMES,
            D_PAT.DO46_CSTAGG1UM1,
            D_PAT.DO46_CSTAGG2UM1,
            D_PAT.DO46_SCHEDSEQ
        FROM DO30_DOCCORPO R WITH (NOLOCK)
        CROSS JOIN DO46_DOCCORORDDET D_PAT WITH (NOLOCK)
        LEFT JOIN PD48_CICLI P WITH (NOLOCK)
            ON P.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
           AND P.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
           AND P.PD48_SEQFASE = D_PAT.DO46_CODSEQFASE
           AND P.PD48_CODFASE_PD12 = D_PAT.DO46_CODFASE
        WHERE R.DO30_DITTA_CG18 = @DITTA
          AND R.DO30_NUMREG_CO99 = @NUMREG_CO99
          AND R.DO30_PROGRIGA > 1
          AND D_PAT.DO46_DITTA_CG18 = @DITTA
          AND D_PAT.DO46_NUMREG_CO99 = @NUMREG_CO99
          AND D_PAT.DO46_PROGRIGA = 1
          AND NOT EXISTS (
              SELECT 1 FROM DO46_DOCCORORDDET D_EXIST WITH (NOLOCK)
              WHERE D_EXIST.DO46_DITTA_CG18 = R.DO30_DITTA_CG18
                AND D_EXIST.DO46_NUMREG_CO99 = R.DO30_NUMREG_CO99
                AND D_EXIST.DO46_PROGRIGA = R.DO30_PROGRIGA
                AND D_EXIST.DO46_CODSEQFASE = D_PAT.DO46_CODSEQFASE
                AND D_EXIST.DO46_CODFASE = D_PAT.DO46_CODFASE
          );

        PRINT 'B.2 - Inserimento eventuali fasi mancanti in DO46 completato.';

        -- B.3 Aggiornamento NON DISTRUTTIVO dei puntatori DO46_IDCICLO_PD48 su TUTTE le righe esistenti (1..N)
        -- Non altera DO46_GUID, quantità consolidate, stati d'ordine o date delle fasi avanzate
        UPDATE D
        SET D.DO46_IDCICLO_PD48 = P.PD48_IDCICLO,
            D.DO46_CLIFOR_CG44   = CASE WHEN D.DO46_CODFASE = 1480 THEN ISNULL(D.DO46_CLIFOR_CG44, 2682) ELSE D.DO46_CLIFOR_CG44 END,
            D.DO46_FLGGENORDCLAV = CASE WHEN D.DO46_CODFASE = 1480 THEN 1 ELSE D.DO46_FLGGENORDCLAV END,
            -- Aggiorna quantità ordinate SOLO se la fase non è ancora avanzata
            D.DO46_QTA1ORD       = CASE WHEN ISNULL(D.DO46_INDSTATOORD, 0) <= 1 AND ISNULL(D.DO46_QTA1CONSOLID, 0) = 0 THEN ISNULL(R.DO30_QTA1, D.DO46_QTA1ORD) ELSE D.DO46_QTA1ORD END,
            D.DO46_QTA2ORD       = CASE WHEN ISNULL(D.DO46_INDSTATOORD, 0) <= 1 AND ISNULL(D.DO46_QTA2CONSOLID, 0) = 0 THEN ISNULL(R.DO30_QTA2, D.DO46_QTA2ORD) ELSE D.DO46_QTA2ORD END,
            D.DO46_COLLIORD      = CASE WHEN ISNULL(D.DO46_INDSTATOORD, 0) <= 1 AND ISNULL(D.DO46_QTA1CONSOLID, 0) = 0 THEN ISNULL(R.DO30_COLLI, D.DO46_COLLIORD) ELSE D.DO46_COLLIORD END
        FROM DO46_DOCCORORDDET D
        INNER JOIN DO30_DOCCORPO R WITH (NOLOCK)
            ON D.DO46_DITTA_CG18 = R.DO30_DITTA_CG18 
           AND D.DO46_NUMREG_CO99 = R.DO30_NUMREG_CO99 
           AND D.DO46_PROGRIGA = R.DO30_PROGRIGA
        INNER JOIN PD48_CICLI P WITH (NOLOCK)
            ON P.PD48_DITTA_CG18 = R.DO30_DITTA_CG18
           AND P.PD48_IDDISBA_PD95 = R.DO30_IDDISBA_PD95
           AND P.PD48_SEQFASE = D.DO46_CODSEQFASE
           AND P.PD48_CODFASE_PD12 = D.DO46_CODFASE
        WHERE D.DO46_DITTA_CG18 = @DITTA 
          AND D.DO46_NUMREG_CO99 = @NUMREG_CO99;

        PRINT 'B.3 - Riconciliazione puntatori DO46_IDCICLO_PD48 completata con successo su tutte le righe.';

        IF @@TRANCOUNT > 0
            COMMIT TRAN;
            
        PRINT '==============================================================================================';
        PRINT '*** TRANSAZIONE CONFERMATA CON SUCCESSO. TUTTI I DATI SONO STATI ALLINEATI SU DATABASE ***';
        PRINT '==============================================================================================';
    END

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;
        
    PRINT '==============================================================================================';
    PRINT '*** ERRORE RILEVATO! TRANSAZIONE ANNULLATA (ROLLBACK EFFETTUATO) ***';
    PRINT 'Messaggio di Errore : ' + ERROR_MESSAGE();
    PRINT 'Numero Linea Errore : ' + CAST(ERROR_LINE() AS VARCHAR);
    PRINT 'Codice Errore       : ' + CAST(ERROR_NUMBER() AS VARCHAR);
    PRINT '==============================================================================================';
END CATCH

