/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Vista dbo.VPRT_TMV_AGG_DESCR_ART (Sorgente Tracciato TMV_AGG_DESART1)
Nome File                        : VPRT_TMV_AGG_DESCR_ART.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La vista 'VPRT_TMV_AGG_DESCR_ART' costituisce la sorgente dati primaria (IE25_TABELLAFILE)
per il primo tracciato ('TMV_AGG_DESART1') dell'insieme batch 'TMV_AGG_DESCR_ART'.

OBIETTIVO DI PROCESSO:
Individuare in modo rapido, incrementale (delta) ed esaustivo tutti i codici articolo e le relative
varianti che necessitano della generazione, rigenerazione o normalizzazione della descrizione
tecnica in Gamma Enterprise, caricandoli nella tabella di lavoro 'RT12_AGG_DESCR_ART'.

ARCHITETTURA LOGICA E SOTTO-QUERY:
La vista si compone di due rami logici uniti tramite 'UNION':

RAMO 1 (ESTRAZIONE INCREMENTALE DELTA):
- Legge da 'MG66_ANAGRART' (anagrafica articoli) e 'MG87_ARTDESC' (descrizioni esistenti per lingua standard '').
- Recupera il timestamp dell'ultima esecuzione batch tramite subquery su 'RT14_VARIABILI_READYTEC'
  (RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART').
- Incrocia la tabella di audit anagrafico 'MO13_LOGARTICOLI' (popolata dai trigger standard di Gamma
  ad ogni inserimento o modifica di anagrafica articoli), filtrando:
    * Eventi di creazione ('MG66_DTCREAZ') o variazione descrizione ('MG87_DESCART').
    * Tipo operazione = 0 (Inserimento/Variazione).
    * Data evento MO13_DATALOG >= RT14_DATE_VALUE (solo modifiche avvenute dopo l'ultimo run).
- Esegue un INNER JOIN con 'CM15_CONFGCOMM' per assicurare che vengano trattati unicamente articoli
  configurati e validati all'interno del configuratore commerciale.

RAMO 2 (BONIFICA RESIDUI ARTICOLO MODELLO):
- Individua eventuali articoli la cui descrizione contiene la stringa 'ARTICOLO MODELLO', ma che non
  sono effettivamente catalogati come modelli nella vista 'VPRT_ARTICOLI_MODELLO' (LEFT JOIN con esito NULL).
- Questa sezione garantisce che refusi o diciture fittizie generate da duplicazioni manuali non passino
  ai sistemi a valle (come il MES o l'integrazione con Overone), sanandoli automaticamente ad ogni ciclo batch.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (13/12/2021 - Coria Francesco):
  Versione iniziale della vista di frontiera per l'estrazione degli articoli da aggiornare.
- Rev. 1.1 (04/02/2026 - SOLVERIS - Bandera Marco):
  Aggiunto il secondo ramo di UNION per sanare eventuali residui sfuggiti alla procedura che riportano
  nella descrizione un riferimento all'articolo modello, evitando anomalie nel passaggio verso Overone.
  Valutato e scartato il recupero da DB di backup dei log MO13 in quanto la generazione descrizioni
  deve avvenire contestualmente al ciclo di vita attivo.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Revisione strutturale secondo lo standard narrativo SOLVERIS. Applicazione sistematica della clausola
  WITH (NOLOCK) su tutte le tabelle per prevenire lock concorrenti con le sessioni utente di Gamma,
  rimozione di frammenti di codice commentato obsoleto e formalizzazione dell'estrazione dei campi.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[VPRT_TMV_AGG_DESCR_ART]', 'V') IS NOT NULL
    DROP VIEW [dbo].[VPRT_TMV_AGG_DESCR_ART];
GO

CREATE VIEW [dbo].[VPRT_TMV_AGG_DESCR_ART]
AS
(
    -- =============================================================================================
    -- RAMO 1: ESTRAZIONE INCREMENTALE DEGLI ARTICOLI CREATI O MODIFICATI DALL'ULTIMA ESECUZIONE
    -- =============================================================================================
    SELECT 
        MG87.MG87_DITTA_CG18,
        MG87.MG87_CODART_MG66,
        MG87.MG87_OPZIONE_MG5E,
        MG87.MG87_DESCART,
        MG87.MG87_DESCARTEST
    FROM dbo.MG66_ANAGRART AS MG66 WITH (NOLOCK)
    INNER JOIN dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
        ON  MG66.MG66_DITTA_CG18 = MG87.MG87_DITTA_CG18 
        AND MG66.MG66_CODART     = MG87.MG87_CODART_MG66 
    INNER JOIN (
        -- Recupero del timestamp dell'ultimo passaggio batch completato con successo
        SELECT 
            RT14_DITTA_CG18, 
            RT14_DATE_VALUE
        FROM dbo.RT14_VARIABILI_READYTEC WITH (NOLOCK)
        WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'
    ) AS ULTIMA_DATA_EXEC 
        ON MG66.MG66_DITTA_CG18 = ULTIMA_DATA_EXEC.RT14_DITTA_CG18 
    INNER JOIN (
        -- Aggregazione per articolo/opzione dell'ultimo evento di log registrato da Gamma
        SELECT 
            MO13_DITTA_CG18,
            MO13_CODART_MG66,
            ISNULL(MO13_OPZIONE_MG5E, '') AS MO13_OPZIONE_MG5E,
            MAX(MO13_DATALOG)             AS MO13_DATALOG
        FROM dbo.MO13_LOGARTICOLI WITH (NOLOCK)
        WHERE (MO13_FIELDNAME = 'MG87_DESCART' OR MO13_FIELDNAME = 'MG66_DTCREAZ') 
          AND (MO13_INDTIPOOP = 0)
        GROUP BY 
            MO13_DITTA_CG18,
            MO13_CODART_MG66,
            ISNULL(MO13_OPZIONE_MG5E, '')
    ) AS LOG_ARTICOLI 
        ON  MG87.MG87_DITTA_CG18   = LOG_ARTICOLI.MO13_DITTA_CG18 
        AND MG87.MG87_CODART_MG66  = LOG_ARTICOLI.MO13_CODART_MG66 
        AND MG87.MG87_OPZIONE_MG5E = LOG_ARTICOLI.MO13_OPZIONE_MG5E 
        AND LOG_ARTICOLI.MO13_DATALOG >= ULTIMA_DATA_EXEC.RT14_DATE_VALUE 
    INNER JOIN dbo.CM15_CONFGCOMM AS CM15 WITH (NOLOCK)
        ON  MG87.MG87_DITTA_CG18  = CM15.CM15_DITTA_CG18 
        AND MG87.MG87_CODART_MG66 = CM15.CM15_CODART_MG66
    WHERE (MG66.MG66_DITTA_CG18 = 1) 
      AND (MG87.MG87_LINGUA_MG52 = '')

    -- =============================================================================================
    -- RAMO 2: BONIFICA ARTICOLI CON DESCRIZIONE 'ARTICOLO MODELLO' ORFANI DI CONFIGURAZIONE MODELLO
    -- =============================================================================================
    UNION 

    SELECT 
        MG87.MG87_DITTA_CG18,
        MG87.MG87_CODART_MG66,
        MG87.MG87_OPZIONE_MG5E,
        MG87.MG87_DESCART,
        MG87.MG87_DESCARTEST
    FROM dbo.MG87_ARTDESC AS MG87 WITH (NOLOCK)
    INNER JOIN dbo.MG66_ANAGRART AS MG66 WITH (NOLOCK)
        ON  MG87.MG87_DITTA_CG18 = MG66.MG66_DITTA_CG18
        AND MG87.MG87_CODART_MG66 = MG66.MG66_CODART
    LEFT JOIN dbo.VPRT_ARTICOLI_MODELLO AS MODELLO WITH (NOLOCK)
        ON  MG87.MG87_DITTA_CG18  = MODELLO.CM15_DITTA_CG18
        AND MG87.MG87_CODART_MG66 = MODELLO.CM15_CODARTMOD_MG66
    WHERE MG87.MG87_DESCART LIKE '%ARTICOLO MODELLO%' 
      AND MODELLO.CM15_CODARTMOD_MG66 IS NULL
      AND MG87.MG87_DITTA_CG18 = 1
      AND MG87.MG87_LINGUA_MG52 = ''
);
GO

