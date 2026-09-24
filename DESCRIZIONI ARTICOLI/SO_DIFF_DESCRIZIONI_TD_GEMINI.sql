/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 09:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Tabella dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI
Nome File                        : SO_DIFF_DESCRIZIONI_TD_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La tabella 'dbo.SO_DIFF_DESCRIZIONI_TD_GEMINI' è una struttura di appoggio e audit persistente creata
allo scopo di isolare, tracciare e classificare tutte le discrepanze riscontrate tra le descrizioni
articoli attualmente memorizzate nella tabella anagrafica di Gamma Enterprise ('dbo.MG87_ARTDESC')
e le descrizioni ricalcolate tramite la funzione algoritmica aggiornata 'dbo.SFSO_TMV_DESCRIZIONE_GEMINI'
per tutti gli articoli della famiglia barre, tondi e tiranti (prefisso codice 'TD%').

CONTESTO AZIENDALE E NECESSITÀ DI AUDIT:
A seguito dell'introduzione dei nuovi diametri metrici in 'dbo.RT05_DESCR_DIAM_PASSO' (es. M110, M120,
M125, M130, M155, M160, M180) e della correzione delle logiche di spezzamento a 70 caratteri, si rende
necessario verificare in modo esaustivo l'intero patrimonio articoli 'TD%' (oltre 43.000 codici),
evidenziando:
1. Articoli con descrizione Short o Long differente.
2. Articoli che beneficiano della nuova gestione del diametro in millimetri ('Ø ...mm' anziché 'Mxxx passo').
3. Articoli privi della traduzione tecnica internazionale in lingua inglese ('LNG').
4. Articoli che presentavano diciture anomale storiche (es. residui di testo 'modello' o 'Min.0').

La tabella permette all'Ufficio Tecnico e ai programmatori di analizzare i dati prima dell'allineamento
e costituisce la sorgente dati per la Stored Procedure di bonifica 'dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI'.

STRUTTURA DEI CAMPI:
- Ditta                : Identificativo ditta Gamma (default 1).
- CodiceArticolo       : Codice articolo Gamma Enterprise (es. TDP04B7-M1254-).
- Opzione              : Eventuale codice opzione/variante associato (es. L100-, o spazio per articolo base).
- TipologiaTD          : Sotto-famiglia estratta dai primi 3 caratteri (TDP, TDL, TDN, TDM, TDR, TDC, TDF).
- DiffShort            : Flag booleano (1 se ShortAttuale <> ShortNuovo).
- DiffLong             : Flag booleano (1 se LongAttuale <> LongNuovo o assente).
- TipoAzioneShort      : Azione richiesta per lingua default ('UPDATE', 'INVARIATO').
- TipoAzioneLong       : Azione richiesta per lingua 'LNG' ('UPDATE', 'INSERT', 'INVARIATO').
- ShortAttuale         : Valore attuale del campo MG87_DESCART per lingua default.
- ShortNuovo           : Valore ricalcolato (entro 70 car., senza spezzare parole).
- ShortEstesaAttuale   : Valore attuale del campo MG87_DESCARTEST per lingua default.
- ShortEstesaNuova     : Residuo eccedente i 70 car. per lingua default.
- LongAttuale          : Valore attuale del campo MG87_DESCART per lingua 'LNG'.
- LongNuovo            : Valore ricalcolato per lingua 'LNG' (entro 70 car.).
- LongEstesaAttuale    : Valore attuale del campo MG87_DESCARTEST per lingua 'LNG'.
- LongEstesaNuova      : Residuo eccedente per lingua 'LNG'.
- MotivoDifferenza     : Classificazione discorsiva del motivo di disallineamento.
- DataRilevamento      : Timestamp dell'avvenuta rilevazione.
- DataAdeguamento      : Timestamp dell'avvenuto aggiornamento (NULL se in attesa).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Creazione iniziale della tabella di audit e differenze descrizioni TD.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SO_DIFF_DESCRIZIONI_TD_GEMINI]', 'U') IS NOT NULL
    DROP TABLE [dbo].[SO_DIFF_DESCRIZIONI_TD_GEMINI];
GO

CREATE TABLE [dbo].[SO_DIFF_DESCRIZIONI_TD_GEMINI]
(
    Ditta                   DECIMAL(5, 0)   NOT NULL,
    CodiceArticolo          CHAR(25)        NOT NULL,
    Opzione                 CHAR(20)        NOT NULL,
    TipologiaTD             CHAR(3)         NOT NULL,
    DiffShort               BIT             NOT NULL DEFAULT 0,
    DiffLong                BIT             NOT NULL DEFAULT 0,
    TipoAzioneShort         VARCHAR(15)     NOT NULL DEFAULT 'INVARIATO',
    TipoAzioneLong          VARCHAR(15)     NOT NULL DEFAULT 'INVARIATO',
    ShortAttuale            NVARCHAR(72)    NULL,
    ShortNuovo              NVARCHAR(72)    NULL,
    ShortEstesaAttuale      NVARCHAR(1672)  NULL,
    ShortEstesaNuova        NVARCHAR(1672)  NULL,
    LongAttuale             NVARCHAR(72)    NULL,
    LongNuovo               NVARCHAR(72)    NULL,
    LongEstesaAttuale       NVARCHAR(1672)  NULL,
    LongEstesaNuova         NVARCHAR(1672)  NULL,
    MotivoDifferenza        NVARCHAR(250)   NULL,
    DataRilevamento         DATETIME        NOT NULL DEFAULT GETDATE(),
    DataAdeguamento         DATETIME        NULL,

    CONSTRAINT [PK_SO_DIFF_DESCRIZIONI_TD_GEMINI] PRIMARY KEY CLUSTERED 
    (
        Ditta ASC,
        CodiceArticolo ASC,
        Opzione ASC
    )
);
GO

-- Indici secondari per reportistica veloce e filtraggi operativi
CREATE NONCLUSTERED INDEX [IX_SO_DIFF_DESCRIZIONI_TD_GEMINI_TIPO]
ON [dbo].[SO_DIFF_DESCRIZIONI_TD_GEMINI] ([TipologiaTD], [DiffShort], [DiffLong])
INCLUDE ([CodiceArticolo], [Opzione], [MotivoDifferenza]);
GO

