USE [DBTMV]
GO

/****** Object:  View [dbo].[VPRT_DIBA_LOCALIZZATA]    Script Date: 02/10/2026 10:40:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
================================================================================================
1 - DATA E ORA MODIFICA: 02/10/2026 10:40
2 - AUTORE: SOLVERIS - Bandera Marco
3 - DESCRIZIONE DETTAGLIATA DELL'OGGETTO (CONTESTO AZIENDALE E ARCHITETTURALE):
    La presente vista [dbo].[VPRT_DIBA_LOCALIZZATA] costituisce la vista radice ("Hub Primario") 
    dell'intero sottosistema di gestione e automazione della "Localizzazione delle Distinte Base" 
    (DIBA) sviluppato per l'ambiente ERP TeamSystem Gamma Enterprise / Alyante di TMV.

    --- CONTESTO DI BUSINESS E FLUSSO APPLICATIVO ---
    Nel processo manifatturiero e commerciale di TMV, gli ordini cliente inseriti a gestionale 
    devono essere sottoposti a verifica e valorizzazione delle relative distinte base (esplosione, 
    localizzazione dei componenti, verifica giacenze min/max inox, assegnazione cicli e fasi).
    Tale iter operativo è governato dal motore Flussi Documentali / Workflow di Gamma:
      * Flusso Documentale Target: ID 10008 ("TMV - Ordini Clienti").
      * Regola di Ingresso nel Flusso di Localizzazione: Un ordine cliente viene preso in carico 
        esclusivamente quando la Testata Documento (DO11) si trova in specifici stati di approvazione:
          - Stato 10042: "Approv.Uff.DIR" (Approvazione Ufficio Direzione / Commerciale);
          - Stato 10061: "Da Rilocalizzare" (Stato di rilavorazione per ordini già processati ma 
            per i quali è stata richiesta una nuova sincronizzazione / localizzazione).
    
    --- FUNZIONALITÀ TECNICA DELLA VISTA ---
    1. Intercetta la configurazione del workflow incrociando le tabelle di definizione filtri entità
       (CO4O_TIPOFILTROENTITAFLUSSO e CO4P_FILTROENTITAFLUSSO) specifiche per il flusso ordini 10008, 
       garantendo la corretta associazione con le tipologie documentali ammesse (DC-ORDINE, DC-ORDGAR, ecc.).
    2. Valuta lo stato corrente della Testata Documento (DO11_DOCTESTATA) tramite il relativo record di 
       stato attuale (CO4H_STATIATTUALI collegato via DO11_GUID), limitando l'output ai soli stati 10042 e 10061.
    3. Esplode le singole righe di corpo documento (DO30_DOCCORPO) appartenenti alle testate selezionate.
    4. Traccia puntualmente lo stato di avanzamento della singola riga di corpo documento interrogando 
       l'istanza di CO4H_STATIATTUALI associata al DO30_GUID e decodificandone la descrizione tramite 
       l'anagrafica stati CO4C_STATI (es. Generato, DIBA Localizzata, Mancata Localizzazione, ecc.).
    5. Applica il filtro di esclusione per gli articoli meramente fittizi o descrittivi (MG66_INDFITTIZIO = 0), 
       isolando unicamente i codici articolo fisici e producibili destinati alla movimentazione di magazzino 
       e alla distinta base di produzione.

    --- OGGETTI DERIVATI E INTERDIPENDENZE ---
    Questa vista rappresenta la sorgente fondamentale su cui si innestano tutte le logiche di controllo 
    specialistiche a valle, tra cui:
      * VPRT_DIBA_LOCALIZZATA_RTP (gestione righe rilocabili per il sistema RTP e logiche INOX)
      * VPRT_DIBA_LOCALIZZATA_MANCANTE (rilevamento anomalie, distinte mancanti o generiche)
      * VPRT_DIBA_LOCALIZZATA_CAMBIO_CODICE (rilevamento variazioni codici articolo)
      * VPRT_DIBA_LOCALIZZATA_FASE_PD12 (allineamento delle fasi cicli di produzione)
      * VPRT_DIBA_LOCALIZZATA_DO30_CO4H (mappatura stati riga)
================================================================================================
STORICO REVISIONI:
- Rev. 1: Versione originale implementata nel modulo Workflow Ordini Clienti TMV (Flusso 10008, 
  stati testata 10042 e 10061, filtro anagrafica articoli fisici).
- Rev. 2: 02/10/2026 - SOLVERIS (Bandera Marco):
  * Ristrutturazione architetturale e conformità agli standard di sviluppo SOLVERIS.
  * Inserimento del cartiglio narrativo dettagliato e commentario discorsivo esteso.
  * Introduzione della sintassi CREATE OR ALTER per piena compatibilità con SQL Server 2017+ (MSSQL 14.0.2120.1).
  * Applicazione rigorosa delle direttive WITH (NOLOCK) su ogni accesso tabellare al fine di azzerare 
    il rischio di dead-lock o blocchi concorrenti in lettura sul database transazionale.
  * Normalizzazione degli alias tabellari in forma mnemonica ed esplicita (TESTATA, CORPO, STATI_TESTATA, 
    STATI_RIGA, ANAGRART, STATI_DESCR, TIPOFILTRO, FILTROENTITA).
  * Mantenimento categorico del nome originale dell'oggetto [dbo].[VPRT_DIBA_LOCALIZZATA], in deroga 
    alla consueta convenzione di naming con suffisso _GEMINI, come espressamente richiesto per garantire 
    la piena retrocompatibilità con i componenti applicativi e le viste legacy preesistenti.
================================================================================================
*/
CREATE OR ALTER VIEW [dbo].[VPRT_DIBA_LOCALIZZATA]
AS
SELECT 
    ------------------------------------------------------------------------------------------------
    -- SEZIONE 1: IDENTIFICATIVI DI TESTATA E WORKFLOW DOCUMENTALE
    ------------------------------------------------------------------------------------------------
    -- Identificativo univoco globale (GUID) della testata ordine nel motore stati Gamma Enterprise.
    -- Corrisponde a DO11_DOCTESTATA.DO11_GUID ed è essenziale per qualsiasi join o aggiornamento di stato a monte.
    STATI_TESTATA.CO4H_GUID,

    -- Codice tipologia documento Gamma (es. DC-ORDINE, DC-ORDGAR, DC-ORDINE-PPP).
    TESTATA.DO11_DOCUM_MG36,

    -- Numero documento formale attribuito all'ordine cliente.
    TESTATA.DO11_NUMDOC,

    -- Data di registrazione del documento ordine cliente.
    TESTATA.DO11_DATADOC,

    ------------------------------------------------------------------------------------------------
    -- SEZIONE 2: STATO DI AVANZAMENTO DELLA SINGOLA RIGA D'ORDINE
    ------------------------------------------------------------------------------------------------
    -- Identificativo numerico dello stato corrente di avanzamento della singola riga di corpo ordine 
    -- (es. 10045 = Generato, 10046 = DIBA Localizzata, 10054 = Mancata Localizzazione DIBA, 10068 = Riga Annullata).
    STATI_RIGA.CO4H_IDSTATO_CO4C AS CO4H_IDSTATO_CO4C,

    -- Descrizione in chiaro dello stato della riga, estratta per consentire un monitoraggio visuale immediato.
    STATI_DESCR.CO4C_DESCRIZIONE,

    ------------------------------------------------------------------------------------------------
    -- SEZIONE 3: IDENTIFICATIVI TECNICI DELLA RIGA CORPO DOCUMENTO (DO30)
    ------------------------------------------------------------------------------------------------
    -- GUID univoco della riga documento di corpo (chiave di riferimento per CO4H e RT17).
    CORPO.DO30_GUID,

    -- Codice Ditta Gamma (es. 1 per TMV) per isolamento multi-aziendale.
    CORPO.DO30_DITTA_CG18,

    -- Numero di registrazione contabile/gestionale univoco attribuito al documento.
    CORPO.DO30_NUMREG_CO99,

    -- Numero progressivo di riga all'interno del corpo documento.
    CORPO.DO30_PROGRIGA

FROM 
    ------------------------------------------------------------------------------------------------
    -- SORGENTE 1: Configurazione Filtro Entità e Flussi Workflow Gamma (CO4O)
    -- Definisce l'associazione tra il codice tipo documento (MG36) e la configurazione del filtro flusso.
    ------------------------------------------------------------------------------------------------
    dbo.CO4O_TIPOFILTROENTITAFLUSSO AS TIPOFILTRO WITH (NOLOCK)

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 2: Dettaglio Associazione Workflow (CO4P)
    -- Relaziona la definizione del filtro di tipo entità con lo specifico Flusso Documentale attivo (CO4B).
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.CO4P_FILTROENTITAFLUSSO AS FILTROENTITA WITH (NOLOCK)
        ON TIPOFILTRO.CO4O_ID = FILTROENTITA.CO4P_ID_CO4O

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 3: Stato Attuale di Testata del Documento (CO4H)
    -- Mantiene lo stato di avanzamento in tempo reale dell'entità Testata d'Ordine nel Workflow 10008.
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.CO4H_STATIATTUALI AS STATI_TESTATA WITH (NOLOCK)
        ON FILTROENTITA.CO4P_IDFLUSSO_CO4B = STATI_TESTATA.CO4H_IDFLUSSO_CO4B

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 4: Testata Documento Gamma Enterprise (DO11)
    -- Tabella master delle testate ordini clienti. L'aggancio avviene sia per corrispondenza del tipo 
    -- documento configurato nel flusso, sia mediante la chiave primaria surrogata DO11_GUID = CO4H_GUID.
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.DO11_DOCTESTATA AS TESTATA WITH (NOLOCK)
        ON  TESTATA.DO11_DOCUM_MG36 = TIPOFILTRO.CO4O_CODDOCUM_MG36
        AND TESTATA.DO11_GUID       = STATI_TESTATA.CO4H_GUID

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 5: Righe Corpo Documento Gamma Enterprise (DO30)
    -- Tabella di dettaglio contenente gli articoli ordinati, agganciata alla testata tramite la 
    -- chiave composita Ditta (CG18) e Numero di Registrazione (CO99).
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.DO30_DOCCORPO AS CORPO WITH (NOLOCK)
        ON  TESTATA.DO11_DITTA_CG18   = CORPO.DO30_DITTA_CG18
        AND TESTATA.DO11_NUMREG_CO99 = CORPO.DO30_NUMREG_CO99

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 6: Stato Attuale della Singola Riga d'Ordine (CO4H)
    -- La gestione a workflow estende il controllo di avanzamento al livello atomico di riga, 
    -- collegandosi tramite DO30_GUID all'entità di stato corrispondente.
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.CO4H_STATIATTUALI AS STATI_RIGA WITH (NOLOCK)
        ON CORPO.DO30_GUID = STATI_RIGA.CO4H_GUID

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 7: Anagrafica Articoli Gestionale (MG66)
    -- Consultata per validare la natura dell'articolo ordinato (escludere codici fittizi / descrittivi).
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.MG66_ANAGRART AS ANAGRART WITH (NOLOCK)
        ON  CORPO.DO30_DITTA_CG18   = ANAGRART.MG66_DITTA_CG18
        AND CORPO.DO30_CODART_MG66  = ANAGRART.MG66_CODART

    ------------------------------------------------------------------------------------------------
    -- SORGENTE 8: Tabella Decodifica Stati Workflow (CO4C)
    -- Permette di decodificare l'ID numerico di stato della riga esponendo la relativa descrizione.
    ------------------------------------------------------------------------------------------------
    INNER JOIN dbo.CO4C_STATI AS STATI_DESCR WITH (NOLOCK)
        ON STATI_RIGA.CO4H_IDSTATO_CO4C = STATI_DESCR.CO4C_IDSTATO

WHERE
    ------------------------------------------------------------------------------------------------
    -- FILTRO 1: Selezione del Flusso Workflow di Competenza
    -- Isola unicamente le entità appartenenti al Workflow ID 10008 ("TMV - Ordini Clienti").
    ------------------------------------------------------------------------------------------------
    FILTROENTITA.CO4P_IDFLUSSO_CO4B = 10008

    ------------------------------------------------------------------------------------------------
    -- FILTRO 2: Condizione di Stato Attivo della Testata Ordine
    -- Intercetta gli ordini pronti per la lavorazione di distinta base:
    --   * 10042 = "Approv.Uff.DIR": Ordine approvato e validato dalla Direzione Commerciale;
    --   * 10061 = "Da Rilocalizzare": Ordine per cui è stato esplicitamente riaperto il ciclo di localizzazione.
    ------------------------------------------------------------------------------------------------
    AND STATI_TESTATA.CO4H_IDSTATO_CO4C IN (10042, 10061)

    ------------------------------------------------------------------------------------------------
    -- FILTRO 3: Esclusione Articoli Fittizi
    -- Seleziona solo gli articoli fisici di magazzino/produzione (MG66_INDFITTIZIO = 0), escludendo 
    -- righe meramente descrittive, note o spese accessorie prive di gestione a distinta base.
    ------------------------------------------------------------------------------------------------
    AND ANAGRART.MG66_INDFITTIZIO = 0
GO
