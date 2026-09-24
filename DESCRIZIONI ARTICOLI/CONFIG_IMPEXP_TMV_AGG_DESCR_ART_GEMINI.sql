/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Script di Configurazione e Audit Batch ImpExp (Tabelle IE...)
Nome File                        : CONFIG_IMPEXP_TMV_AGG_DESCR_ART_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Questo script costituisce la guida tecnica e lo strumento di verifica, allineamento e audit trail
per l'intera architettura dell'Insieme batch 'TMV_AGG_DESCR_ART' e dei tre tracciati collegati:
  - Passaggio 1: 'TMV_AGG_DESART1' (Estrazione incrementale delta articoli da VPRT_TMV_AGG_DESCR_ART)
  - Passaggio 2: 'TMV_AGG_DESART2' (Generazione e aggiornamento descrizioni via SPRT_TMV_AGG_DESCR_ART)
  - Passaggio 3: 'TMV_AGG_DESART3' (Configurazione varianti e logistica via SPRT_TMV_AGG_ARTICOLI_VARIE)

ORGANIZZAZIONE DELLO SCRIPT:
1. SEZIONE 1 - AUDIT STRUTTURALE DELL'INSIEME (IE33 / IE34):
   Interrogazione dei metadati dell'Insieme e della sequenza temporale di esecuzione dei passaggi.
2. SEZIONE 2 - AUDIT DEI TRACCIATI E DEI COMANDI PRE/POST (IE25):
   Verifica delle tabelle sorgente (IE25_TABELLAFILE), destinazione (IE25_TABELLA), e dei comandi SQL
   eseguiti prima e dopo il tracciato.
3. SEZIONE 3 - AUDIT MAPPING CAMPI (IE26 / IE27):
   Verifica delle sezioni di record e della mappatura campo a campo per il passaggio di transito in RT12.
4. SEZIONE 4 - DIAGNOSTICA STORICO ESECUZIONI E RECORD TRATTATI (IE4C / IE4D):
   Query diagnostica per monitorare l'andamento delle esecuzioni schedulate automatiche (TeamSa).
5. SEZIONE 5 - SCRIPT DML IDEMPOTENTE DI RIPRISTINO E ALLINEAMENTO PARAMETRI:
   Istruzioni protette (TRY...CATCH e transazione) per verificare e ripristinare la corretta configurazione
   dei tracciati in caso di migrazioni o ripristini da ambienti di collaudo.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Configurazione tracciati ImpExp a cura del team tecnico Gamma.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Documentazione completa dell'infrastruttura ImpExp, redazione dello script di audit e diagnostica
  conforme alle regole di codifica SOLVERIS e tracciamento storico in IE4C/IE4D.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '====================================================================================';
PRINT 'INIZIO AUDIT CONFIGURAZIONE BATCH IMPEXP: TMV_AGG_DESCR_ART';
PRINT '====================================================================================';

-- =================================================================================================
-- SEZIONE 1: VERIFICA TESTATA E DETTAGLIO INSIEME BATCH (IE33 & IE34)
-- =================================================================================================
PRINT '--- SEZIONE 1: Testata Insieme (IE33) e Sequenza Passaggi (IE34) ---';

SELECT 
    I.IE33_INSIEME           AS CodiceInsieme,
    I.IE33_FLGZIP            AS FlagZip,
    D.IE34_PROG              AS Passo,
    D.IE34_DESCRIZIONE       AS DescrizionePasso,
    D.IE34_STRUTTURA_IE21    AS Struttura,
    D.IE34_TRACCIATO_IE25    AS CodiceTracciato,
    D.IE34_INDIMPEXP         AS TipoOperazione, -- 1 = Import
    D.IE34_FLGATTIVO         AS Attivo
FROM dbo.IE33_INSIEMI AS I WITH (NOLOCK)
INNER JOIN dbo.IE34_INSIEMIDETT AS D WITH (NOLOCK)
    ON I.IE33_INSIEME = D.IE34_INSIEME_IE33
WHERE I.IE33_INSIEME = 'TMV_AGG_DESCR_ART'
ORDER BY D.IE34_PROG;

-- =================================================================================================
-- SEZIONE 2: VERIFICA DETTAGLIO TRACCIATI E COMANDI PRE/POST ELABORAZIONE (IE25)
-- =================================================================================================
PRINT '--- SEZIONE 2: Definizione Tracciati, File e Comandi SQL Pre/Post (IE25) ---';

SELECT 
    T.IE25_TRACCIATO         AS CodiceTracciato,
    T.IE25_DESCRIZIONE       AS Descrizione,
    T.IE25_STRUTTURA_IE21    AS Struttura,
    T.IE25_TABELLAFILE       AS TabellaSorgente,
    T.IE25_TABELLA           AS TabellaDestinazione,
    T.IE25_INDCOMPRE         AS FlagComandoPre,
    T.IE25_COMANDOIMP        AS ComandoPreElaborazione,
    T.IE25_INDCOMPOST        AS FlagComandoPost,
    T.IE25_COMANDOEXP        AS ComandoPostElaborazione
FROM dbo.IE25_TRACCIATI AS T WITH (NOLOCK)
WHERE T.IE25_TRACCIATO IN ('TMV_AGG_DESART1', 'TMV_AGG_DESART2', 'TMV_AGG_DESART3')
ORDER BY T.IE25_TRACCIATO;

-- =================================================================================================
-- SEZIONE 3: VERIFICA RECORD E MAPPING CAMPI (IE26 & IE27)
-- =================================================================================================
PRINT '--- SEZIONE 3: Mappatura Campi Sorgente -> Destinazione (IE27) ---';

SELECT 
    C.IE27_TRACCIATO_IE25    AS CodiceTracciato,
    R.IE26_DESCRIZIONE       AS SezioneRecord,
    C.IE27_PROGCAMPO         AS ProgressivoCampo,
    C.IE27_NOMECAMPO         AS CampoDestinazione,
    C.IE27_CAMPOASSOCIATO    AS ColonnaSorgente,
    C.IE27_ESPRESSIONE       AS FormulaEspressione
FROM dbo.IE27_TRACCIATICAMPI AS C WITH (NOLOCK)
INNER JOIN dbo.IE26_TRACCIATIRIGHE AS R WITH (NOLOCK)
    ON  C.IE27_TRACCIATO_IE25    = R.IE26_TRACCIATO_IE25
    AND C.IE27_INDTIPOREC_IE26   = R.IE26_INDTIPOREC
WHERE C.IE27_TRACCIATO_IE25 IN ('TMV_AGG_DESART1', 'TMV_AGG_DESART2', 'TMV_AGG_DESART3')
ORDER BY C.IE27_TRACCIATO_IE25, C.IE27_PROGCAMPO;

-- =================================================================================================
-- SEZIONE 4: DIAGNOSTICA ULTIME ESECUZIONI DA SCHEDULATORE (IE4C & IE4D)
-- =================================================================================================
PRINT '--- SEZIONE 4: Ultime 10 Esecuzioni e Record Trattati (IE4C / IE4D) ---';

SELECT TOP 10 
    C.IE4C_IDIMPEXP          AS IdEsecuzione,
    C.IE4C_INSIEME_IE33      AS Insieme,
    C.IE4C_PROG_IE34         AS Passo,
    C.IE4C_TRACCIATO_IE25    AS Tracciato,
    C.IE4C_UTENTE            AS Utente,
    C.IE4C_MOMENTO           AS DataOraEsecuzione,
    C.IE4C_FLGSCHEDULATO     AS Schedulato,
    D.IE4D_RISULTATO         AS Esito, -- 1 = Info/Init, 0 = OK, >1 = Errore/Warning
    D.IE4D_NOTE              AS DettaglioRecord
FROM dbo.IE4C_LOGIMPEXP AS C WITH (NOLOCK)
LEFT JOIN dbo.IE4D_RECORDS AS D WITH (NOLOCK)
    ON C.IE4C_IDIMPEXP = D.IE4D_ID_IE4C
WHERE C.IE4C_INSIEME_IE33 = 'TMV_AGG_DESCR_ART'
ORDER BY C.IE4C_MOMENTO DESC;

-- =================================================================================================
-- SEZIONE 5: SCRIPT DML IDEMPOTENTE PER ALLINEAMENTO/RIPRISTINO CONFIGURAZIONE
-- =================================================================================================
/*
NOTA PER L'OPERATORE:
La sezione seguente è commentata per sicurezza e può essere utilizzata in ambienti di test/collaudo
per ripristinare la corretta configurazione dell'Insieme e dei tracciati qualora risultassero corrotti.
*/

/*
BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Testata Insieme
    IF NOT EXISTS (SELECT 1 FROM dbo.IE33_INSIEMI WHERE IE33_INSIEME = 'TMV_AGG_DESCR_ART')
    BEGIN
        INSERT INTO dbo.IE33_INSIEMI (IE33_INSIEME, IE33_FLGZIP, IE33_FLGEMAIL)
        VALUES ('TMV_AGG_DESCR_ART', 0, 0);
    END;

    -- 2. Dettaglio Insieme
    DELETE FROM dbo.IE34_INSIEMIDETT WHERE IE34_INSIEME_IE33 = 'TMV_AGG_DESCR_ART';
    INSERT INTO dbo.IE34_INSIEMIDETT (IE34_INSIEME_IE33, IE34_PROG, IE34_DESCRIZIONE, IE34_STRUTTURA_IE21, IE34_TRACCIATO_IE25, IE34_INDIMPEXP, IE34_FLGATTIVO)
    VALUES 
        ('TMV_AGG_DESCR_ART', 1, 'TMV - Agg.Des.Art. Elenco Articoli', 99, 'TMV_AGG_DESART1', 1, 1),
        ('TMV_AGG_DESCR_ART', 2, 'TMV - Agg.Des.Art. via Stored Procedure', 99, 'TMV_AGG_DESART2', 1, 1),
        ('TMV_AGG_DESCR_ART', 3, 'TMV - Congif.Varianti Stored Procedure', 99, 'TMV_AGG_DESART3', 1, 1);

    -- 3. Allineamento Tracciati
    UPDATE dbo.IE25_TRACCIATI
    SET 
        IE25_TABELLAFILE = 'VPRT_TMV_AGG_DESCR_ART',
        IE25_TABELLA     = 'RT12_AGG_DESCR_ART',
        IE25_INDCOMPRE   = 2,
        IE25_COMANDOIMP  = 'DELETE FROM RT12_AGG_DESCR_ART',
        IE25_INDCOMPOST  = 2,
        IE25_COMANDOEXP  = 'UPDATE RT14_VARIABILI_READYTEC SET RT14_DATE_VALUE = GETDATE() WHERE RT14_VARNAME = ''SPRT_TMV_AGG_DESCR_ART'''
    WHERE IE25_TRACCIATO = 'TMV_AGG_DESART1';

    UPDATE dbo.IE25_TRACCIATI
    SET 
        IE25_TABELLAFILE = 'CG18_ANADITTABASE',
        IE25_TABELLA     = 'CG18_ANADITTABASE',
        IE25_INDCOMPRE   = 2,
        IE25_COMANDOIMP  = 'EXEC SPRT_TMV_AGG_DESCR_ART',
        IE25_INDCOMPOST  = 0,
        IE25_COMANDOEXP  = NULL
    WHERE IE25_TRACCIATO = 'TMV_AGG_DESART2';

    UPDATE dbo.IE25_TRACCIATI
    SET 
        IE25_TABELLAFILE = 'CG18_ANADITTABASE',
        IE25_TABELLA     = 'CG18_ANADITTABASE',
        IE25_INDCOMPRE   = 2,
        IE25_COMANDOIMP  = 'EXEC SPRT_TMV_AGG_ARTICOLI_VARIE',
        IE25_INDCOMPOST  = 0,
        IE25_COMANDOEXP  = NULL
    WHERE IE25_TRACCIATO = 'TMV_AGG_DESART3';

    COMMIT TRANSACTION;
    PRINT 'Configurazione ripristinata con successo.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@Err, 16, 1);
END CATCH;
*/
GO

