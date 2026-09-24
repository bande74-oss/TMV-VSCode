/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Vista dbo.VPRT_ARTICOLI_MODELLO
Nome File                        : VPRT_ARTICOLI_MODELLO.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La vista 'VPRT_ARTICOLI_MODELLO' è un oggetto di supporto ad altissima efficienza il cui scopo
è isolare l'elenco distinto degli articoli contrassegnati come "Modello" all'interno della
tabella delle configurazioni commerciali (CM15_CONFGCOMM) dell'ERP Gamma Enterprise.

RUOLO NEL PROCESSO DI AGGIORNAMENTO DESCRIZIONI:
All'interno della vista di frontiera 'VPRT_TMV_AGG_DESCR_ART', la vista 'VPRT_ARTICOLI_MODELLO'
viene utilizzata in LEFT JOIN per individuare e bonificare eventuali record di anagrafica articoli
(MG87_ARTDESC) che presentano nella descrizione il testo 'ARTICOLO MODELLO', ma che NON risultano
censiti formalmente come modelli in CM15.
Tale disallineamento storico o transitorio rischiava di bloccare l'interfaccia verso sistemi esterni
(in particolare l'avanzamento verso il gestionale Overone). La vista consente quindi di intercettare
queste anomalie e forzarne la riscrittura e la normalizzazione automatica da parte del batch.

STRUTTURA:
- CM15_DITTA_CG18       (decimal(5,0)): Identificativo della ditta.
- CM15_CODARTMOD_MG66   (char(25)): Codice dell'articolo modello di riferimento.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Creazione della vista per isolamento degli articoli modello di configuratore.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Adozione dello standard narrativo SOLVERIS e ottimizzazione con clausola WITH (NOLOCK).
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[VPRT_ARTICOLI_MODELLO]', 'V') IS NOT NULL
    DROP VIEW [dbo].[VPRT_ARTICOLI_MODELLO];
GO

CREATE VIEW [dbo].[VPRT_ARTICOLI_MODELLO]
AS
SELECT DISTINCT 
    CM15_DITTA_CG18, 
    CM15_CODARTMOD_MG66
FROM dbo.CM15_CONFGCOMM WITH (NOLOCK);
GO

