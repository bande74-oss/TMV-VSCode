/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 09:45
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Tabella dbo.SO_DIFF_DESCRIZIONI_GEMINI
Nome File                        : SO_DIFF_DESCRIZIONI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La tabella 'dbo.SO_DIFF_DESCRIZIONI_GEMINI' è la struttura globale e definitiva di audit, staging e
tracciamento anomalie descrittive per l'INTERA anagrafica articoli di TMV all'interno di TeamSystem
Gamma Enterprise (oltre 391.000 articoli anagrafici e 652.000 combinazioni articolo/opzione in MG87).

ESTENSIONE DEL CONTROLLO SENZA FILTRI RESTRITTIVI:
Mentre la precedente struttura era circoscritta alla famiglia 'TD%', l'analisi sui dati ha confermato
che refusi storici nei codici internazionali (es. 'UNS S020910' al posto di 'UNS S20910'), assenza
della traduzione estera 'LNG', spezzamenti anomali di parole sui 70 caratteri e residui di codici
modello affliggono trasversalmente molteplici famiglie di prodotto:
- Tiranti e prigionieri metrici e in pollici (famiglie T-, TS, DT, DN, DP, DM, TT, TO)
- Viteria speciale, bulloneria e viti a disegno (famiglie VE, VP, VT, VD, V1, V2, V4, TDC)
- Dadi speciali e unificati (famiglie D-, DB, DD, D3, DC, D2, D5)
- Barre e tondi speciali (famiglie TD, PD, RD, UB)
- Componenti a disegno cliente (serie numeriche 93..., 91..., 90..., 50...)

STRUTTURA DEI CAMPI:
- Ditta                : DECIMAL(5,0) - Ditta Gamma Enterprise (default 1).
- CodiceArticolo       : CHAR(25) - Codice identificativo articolo.
- Opzione              : CHAR(20) - Codice variante/opzione (o spazio per articolo base).
- Prefisso             : VARCHAR(10) - Prime 2 o 3 lettere per raggruppamento famigliare.
- DiffShort            : BIT - 1 se ShortAttuale <> ShortNuovo o residuo esteso differente.
- DiffLong             : BIT - 1 se LongAttuale <> LongNuovo o se record LNG è assente.
- TipoAzioneShort      : VARCHAR(15) - 'UPDATE' o 'INVARIATO'.
- TipoAzioneLong       : VARCHAR(15) - 'UPDATE', 'INSERT' (se record LNG assente) o 'INVARIATO'.
- ShortAttuale         : NVARCHAR(72) - Testo attuale MG87_DESCART per lingua predefinita.
- ShortNuovo           : NVARCHAR(72) - Testo ricalcolato (entro 70 car., parole integre).
- ShortEstesaAttuale   : NVARCHAR(1672) - Testo attuale MG87_DESCARTEST per lingua predefinita.
- ShortEstesaNuova     : NVARCHAR(1672) - Testo eccedente ricalcolato.
- LongAttuale          : NVARCHAR(72) - Testo attuale MG87_DESCART per lingua 'LNG'.
- LongNuovo            : NVARCHAR(72) - Testo ricalcolato per lingua 'LNG'.
- LongEstesaAttuale    : NVARCHAR(1672) - Testo attuale MG87_DESCARTEST per lingua 'LNG'.
- LongEstesaNuova      : NVARCHAR(1672) - Testo eccedente lingua 'LNG'.
- MotivoDifferenza     : NVARCHAR(250) - Classificazione causale dell'anomalia.
- DataRilevamento      : DATETIME - Timestamp di rilevamento dell'anomalia.
- DataAdeguamento      : DATETIME - Timestamp dell'avvenuta bonifica (NULL se pendente).

CRITERI DI PERFORMANCE:
Clustered Primary Key su (Ditta, CodiceArticolo, Opzione) e indici non clusterizzati mirati su
Prefisso e MotivoDifferenza per garantire scansioni, reportistica e aggiornamenti istantanei.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio della tabella globale di audit per l'intera base dati Gamma Enterprise.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SO_DIFF_DESCRIZIONI_GEMINI]', 'U') IS NOT NULL
    DROP TABLE [dbo].[SO_DIFF_DESCRIZIONI_GEMINI];
GO

CREATE TABLE [dbo].[SO_DIFF_DESCRIZIONI_GEMINI]
(
    Ditta                   DECIMAL(5, 0)   NOT NULL,
    CodiceArticolo          CHAR(25)        NOT NULL,
    Opzione                 CHAR(20)        NOT NULL,
    Prefisso                VARCHAR(10)     NOT NULL,
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

    CONSTRAINT [PK_SO_DIFF_DESCRIZIONI_GEMINI] PRIMARY KEY CLUSTERED 
    (
        Ditta ASC,
        CodiceArticolo ASC,
        Opzione ASC
    )
);
GO

CREATE NONCLUSTERED INDEX [IX_SO_DIFF_DESCRIZIONI_GEMINI_PREF]
ON [dbo].[SO_DIFF_DESCRIZIONI_GEMINI] ([Prefisso], [DiffShort], [DiffLong])
INCLUDE ([CodiceArticolo], [Opzione], [MotivoDifferenza], [DataAdeguamento]);
GO

CREATE NONCLUSTERED INDEX [IX_SO_DIFF_DESCRIZIONI_GEMINI_MOTIVO]
ON [dbo].[SO_DIFF_DESCRIZIONI_GEMINI] ([MotivoDifferenza], [DataAdeguamento])
INCLUDE ([CodiceArticolo], [Opzione], [Prefisso]);
GO

