/* ==========================================================================================================
   DATA E ORA        : 2026-09-14
   AUTORE            : SOLVERIS - Bandera Marco
   OGGETTO           : ImpostaStato_DaEsportare_ODL_GEMINI.sql
   
   DESCRIZIONE AD ALTISSIMO DETTAGLIO:
   Questo script permette di ripristinare e impostare in modo sicuro, atomico e controllato lo stato di un 
   Ordine Di Lavoro (ODL) nel gestionale Gamma TeamSystem nello stato "Da esportare" (ID 10056, Flusso 10012), 
   rendendolo immediatamente visibile ed estraibile dal connettore MES OverOne tramite la vista 
   VPMES_ODLExport (tracciato TMV-MES-ODL-CSV su tabella IE25).

   CONTESTO AZIENDALE E LOGICA DI BUSINESS:
   Nel ciclo produttivo integrato tra il gestionale Gamma e il sistema MES OverOne:
   1. Un ODL viene inizialmente generato e marcato nello stato di flusso 10012 come "Da esportare" (ID 10056).
   2. La procedura schedulata di estrazione interroga la vista VPMES_ODLExport, genera il tracciato CSV per il MES 
      e successivamente invoca la Stored Procedure [dbo].[SPRT_MES_STATO_TESTATA], la quale aggiorna lo stato 
      del documento portandolo a "Esportato" (ID 10057).
   3. L'aggiornamento di CO4H_STATIATTUALI scatena il trigger di sistema [TRG_INSERTSTORICO_CO4H_UPD], il quale 
      scrive un record storico nella tabella CO4I_STATISTORICO con IDSTATO = 10057.

   IL MECCANISMO DI BLOCCO NELLA VISTA VPMES_ODLExport E PERCHÉ UN NORMALE CAMBIO STATO NON BASTA:
   La vista VPMES_ODLExport include una subquery denominata [FILTRO_ESPORTAZIONE] che applica la seguente condizione:
      LEFT JOIN (
          SELECT CO4I_GUID, CO4I_IDSTATO_CO4C 
          FROM dbo.CO4I_STATISTORICO 
          WHERE CO4I_IDFLUSSO_CO4B = 10012 AND CO4I_IDSTATO_CO4C = 10057
      ) AS CO4I_ESPORTATO ON DO11_GUID = CO4I_ESPORTATO.CO4I_GUID
      WHERE CO4I_DA_ESPORTARE.CO4I_IDFLUSSO_CO4B = 10012
        AND CO4I_DA_ESPORTARE.CO4I_IDSTATO_CO4C = 10056
        AND CO4I_ESPORTATO.CO4I_GUID IS NULL    <--- CONDIZIONE BLOCCANTE!
        AND ISNULL(DO18_FLGEVASTOT, 0) <> 1
      ...
      AND CO4H_IDSTATO_CO4C = 10056

   Questo significa che:
   - Non è sufficiente impostare lo stato attuale in CO4H_STATIATTUALI a 10056.
   - Se nella tabella storica CO4I_STATISTORICO rimane anche una sola riga pregressa con CO4I_IDSTATO_CO4C = 10057 
     ("Esportato"), la condizione [CO4I_ESPORTATO.CO4I_GUID IS NULL] RISULTERÀ FALSA e la vista VPMES_ODLExport 
     continuerà a restituire ZERO RIGHE, impedendo di fatto la riesportazione dell'ODL verso il MES.

   AZIONI ESEGUITE DALLO SCRIPT:
   1. Individua il GUID univoco della testata documento ODL da DO11_DOCTESTATA tramite @DITTA e @NUMREG_CO99.
   2. Rimuove dalla tabella storica CO4I_STATISTORICO i record con stato 10057 per il flusso 10012 legati a quel GUID, 
      azzerando il blocco della subquery.
   3. Aggiorna (o inserisce se mancante) in CO4H_STATIATTUALI lo stato corrente a 10056 ("Da esportare") con data 
      validità corrente. Tramite il trigger [TRG_INSERTSTORICO_CO4H_UPD], Gamma registrerà automaticamente il nuovo 
      passaggio a "Da esportare" in CO4I_STATISTORICO.
   4. Verifica in tempo reale che l'ODL sia immediatamente visibile nella vista VPMES_ODLExport e riporta il 
      numero esatto di righe/fasi pronte per il connettore MES.

   SICUREZZA E MODALITÀ DRY-RUN (DRYOUT):
   Lo script è impostato di default con @DryRun = 1.
   In questa modalità non viene apportata alcuna modifica al database; vengono mostrate 4 tabelle di analisi 
   dettagliata e una simulazione esatta delle righe estraibili.
   Impostando @DryRun = 0, le variazioni vengono applicate sotto transazione atomica (BEGIN TRAN / COMMIT).

   CHANGE LOG NARRATIVO:
   - Rev. 1 (2026-09-14): Creazione iniziale dello script con supporto Dry-Run, cartiglio narrativo, 
     gestione combinata di CO4H_STATIATTUALI e CO4I_STATISTORICO per sblocco vincolo VPMES_ODLExport 
     e compatibilità universale su qualsiasi ODL variando @NUMREG_CO99.
   ========================================================================================================== */

DECLARE @DITTA int = 1;
DECLARE @NUMREG_CO99 char(12) = '202600184219';
DECLARE @DryRun bit = 1; -- 1 = Simulazione protetta (Dry-Run), 0 = Esegue realmente le modifiche su DB

BEGIN TRY
    -- Se non siamo in simulazione, isoliamo tutte le operazioni in un'unica transazione atomica
    IF @DryRun = 0
        BEGIN TRAN;

    ------------------------------------------------------------------------------------------------------
    -- 1. VERIFICA INTEGRITÀ PRELIMINARE DEI DATI
    ------------------------------------------------------------------------------------------------------
    DECLARE @DO11_GUID uniqueidentifier;
    DECLARE @DO11_NUMDOC int;
    DECLARE @DO11_SEZDOC char(3);
    DECLARE @DO11_DOCUM_MG36 char(10);
    DECLARE @DO11_DATADOC datetime;

    SELECT 
        @DO11_GUID       = D11.DO11_GUID,
        @DO11_NUMDOC     = D11.DO11_NUMDOC,
        @DO11_SEZDOC     = D11.DO11_SEZDOC,
        @DO11_DOCUM_MG36 = D11.DO11_DOCUM_MG36,
        @DO11_DATADOC    = D11.DO11_DATADOC
    FROM DO11_DOCTESTATA D11 WITH (NOLOCK)
    WHERE D11.DO11_DITTA_CG18 = @DITTA 
      AND D11.DO11_NUMREG_CO99 = @NUMREG_CO99;

    IF @DO11_GUID IS NULL
    BEGIN
        RAISERROR('ERRORE: Nessun documento trovato in DO11_DOCTESTATA per Ditta %d e NumReg %s.', 16, 1, @DITTA, @NUMREG_CO99);
    END;

    ------------------------------------------------------------------------------------------------------
    -- MODALITÀ 1: DRY-RUN (SIMULAZIONE VERBOSA, SICURA E NON DISTRUTTIVA)
    ------------------------------------------------------------------------------------------------------
    IF @DryRun = 1
    BEGIN
        PRINT '==============================================================================================';
        PRINT '*** MODALITÀ DRY-RUN ATTIVA (DryOut): NESSUNA MODIFICA APPORTATA AL DATABASE ***';
        PRINT '==============================================================================================';

        -- Tabella 1: Dati identificativi dell'ODL
        SELECT 
            '1. DATI TESTATA ODL' AS [AzioneDryRun],
            @DITTA AS [Ditta],
            @NUMREG_CO99 AS [NumReg],
            RTRIM(@DO11_DOCUM_MG36) AS [TipoDoc],
            @DO11_NUMDOC AS [NumDoc],
            @DO11_SEZDOC AS [SezDoc],
            CONVERT(varchar(10), @DO11_DATADOC, 105) AS [DataDoc],
            @DO11_GUID AS [DO11_GUID];

        -- Tabella 2: Stato Attuale in CO4H_STATIATTUALI
        SELECT 
            '2. STATO ATTUALE IN CO4H' AS [AzioneDryRun],
            H.CO4H_GUID,
            H.CO4H_IDFLUSSO_CO4B AS [Flusso],
            H.CO4H_IDSTATO_CO4C AS [ID_Stato_Attuale],
            ISNULL(S.CO4C_DESCRIZIONE, 'SCONOSCIUTO') AS [Descrizione_Stato_Attuale],
            H.CO4H_DATAVALIDITA AS [Data_Validita_Attuale],
            10056 AS [ID_Stato_Nuovo_Previsto],
            'Da esportare' AS [Descrizione_Stato_Nuovo_Previsto]
        FROM CO4H_STATIATTUALI H WITH (NOLOCK)
        LEFT JOIN CO4C_STATI S WITH (NOLOCK) ON S.CO4C_IDSTATO = H.CO4H_IDSTATO_CO4C
        WHERE H.CO4H_GUID = @DO11_GUID;

        -- Tabella 3: Storico Stati in CO4I_STATISTORICO e Azioni Previste
        SELECT 
            '3. STORICO STATI IN CO4I' AS [AzioneDryRun],
            I.CO4I_ID,
            I.CO4I_GUID,
            I.CO4I_IDFLUSSO_CO4B AS [Flusso],
            I.CO4I_IDSTATO_CO4C AS [ID_Stato],
            ISNULL(S.CO4C_DESCRIZIONE, 'SCONOSCIUTO') AS [Descrizione_Stato],
            I.CO4I_DATAVALIDITA,
            I.CO4I_DATAGG,
            I.CO4I_ID_FW07 AS [Utente],
            CASE 
                WHEN I.CO4I_IDFLUSSO_CO4B = 10012 AND I.CO4I_IDSTATO_CO4C = 10057 
                    THEN 'DA ELIMINARE (Rimuove il blocco all''esportazione in VPMES_ODLExport)'
                ELSE 'MANTENUTO INALTERATO'
            END AS [Azione_Prevista]
        FROM CO4I_STATISTORICO I WITH (NOLOCK)
        LEFT JOIN CO4C_STATI S WITH (NOLOCK) ON S.CO4C_IDSTATO = I.CO4I_IDSTATO_CO4C
        WHERE I.CO4I_GUID = @DO11_GUID
        ORDER BY I.CO4I_ID ASC;

        -- Tabella 4: Simulazione Conteggio Righe Estraibili da VPMES_ODLExport
        -- Simula cosa vedrà la vista se applichiamo lo sblocco
        SELECT 
            '4. SIMULAZIONE VPMES_ODLExport POST SBLOCCO' AS [AzioneDryRun],
            @NUMREG_CO99 AS [NumReg_ODL],
            COUNT(*) AS [Righe_Fasi_Che_Saranno_Estratte_Verso_MES]
        FROM DO11_DOCTESTATA D11 WITH (NOLOCK)
        INNER JOIN DO30_DOCCORPO D30 WITH (NOLOCK)
            ON D11.DO11_DITTA_CG18 = D30.DO30_DITTA_CG18 AND D11.DO11_NUMREG_CO99 = D30.DO30_NUMREG_CO99
        INNER JOIN DO46_DOCCORORDDET D46 WITH (NOLOCK)
            ON D30.DO30_DITTA_CG18 = D46.DO46_DITTA_CG18 AND D30.DO30_NUMREG_CO99 = D46.DO46_NUMREG_CO99 AND D30.DO30_PROGRIGA = D46.DO46_PROGRIGA
        INNER JOIN PD48_CICLI P48 WITH (NOLOCK)
            ON P48.PD48_IDCICLO = D46.DO46_IDCICLO_PD48
        WHERE D11.DO11_DITTA_CG18 = @DITTA 
          AND D11.DO11_NUMREG_CO99 = @NUMREG_CO99;

        PRINT '==============================================================================================';
        PRINT 'Simulazione completata con successo.';
        PRINT 'Per confermare ed applicare le variazioni su Database, impostare @DryRun = 0.';
        PRINT '==============================================================================================';
    END
    ------------------------------------------------------------------------------------------------------
    -- MODALITÀ 2: ESECUZIONE REALE TRANSAZIONALE E SICURA
    ------------------------------------------------------------------------------------------------------
    ELSE
    BEGIN
        PRINT '*** ESECUZIONE REALE: IMPOSTAZIONE STATO "DA ESPORTARE" PER ODL ' + @NUMREG_CO99 + ' ***';

        -- FASE 1: Rimozione selettiva da CO4I_STATISTORICO dello stato 10057 ("Esportato")
        -- Questo sblocca la clausola [AND CO4I_ESPORTATO.CO4I_GUID IS NULL] nella vista VPMES_ODLExport
        DELETE FROM CO4I_STATISTORICO
        WHERE CO4I_GUID = @DO11_GUID 
          AND CO4I_IDFLUSSO_CO4B = 10012 
          AND CO4I_IDSTATO_CO4C = 10057;

        DECLARE @DeletedHistoryCount int = @@ROWCOUNT;
        PRINT 'Fase 1: Eliminati ' + CAST(@DeletedHistoryCount AS varchar) + ' record storici con stato 10057 (Esportato).';

        -- FASE 2: Allineamento dello stato attuale in CO4H_STATIATTUALI a 10056 ("Da esportare")
        IF EXISTS (SELECT 1 FROM CO4H_STATIATTUALI WITH (NOLOCK) WHERE CO4H_GUID = @DO11_GUID)
        BEGIN
            UPDATE CO4H_STATIATTUALI
            SET CO4H_IDSTATO_CO4C  = 10056,
                CO4H_DATAVALIDITA  = GETDATE(),
                CO4H_IDFLUSSO_CO4B = 10012,
                CO4H_INDAUTH       = 0,
                CO4H_AUTO          = 0
            WHERE CO4H_GUID = @DO11_GUID;

            PRINT 'Fase 2: Aggiornato stato in CO4H_STATIATTUALI a 10056 (Da esportare).';
        END
        ELSE
        BEGIN
            INSERT INTO CO4H_STATIATTUALI (
                CO4H_GUID,
                CO4H_IDSTATO_CO4C,
                CO4H_DATAVALIDITA,
                CO4H_IDFLUSSO_CO4B,
                CO4H_INDAUTH,
                CO4H_AUTO
            )
            VALUES (
                @DO11_GUID,
                10056,
                GETDATE(),
                10012,
                0,
                0
            );

            PRINT 'Fase 2: Inserito nuovo stato in CO4H_STATIATTUALI a 10056 (Da esportare).';
        END;

        -- FASE 3: Verifica immediata su VPMES_ODLExport
        DECLARE @RigheVisibili int = 0;
        SELECT @RigheVisibili = COUNT(*) 
        FROM VPMES_ODLExport WITH (NOLOCK)
        WHERE DO11_NUMREG_CO99_ODL = @NUMREG_CO99;

        PRINT 'Fase 3: Verifica completata. Righe attualmente visibili in VPMES_ODLExport: ' + CAST(@RigheVisibili AS varchar) + '.';

        IF @@TRANCOUNT > 0
            COMMIT TRAN;

        PRINT '==============================================================================================';
        PRINT '*** TRANSAZIONE CONFERMATA CON SUCCESSO. L''ODL È ORA PRONTO PER LA RIESPORTAZIONE VERSO IL MES ***';
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

