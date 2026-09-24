/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Tabella dbo.RT12_AGG_DESCR_ART (DDL e Struttura Dati)
Nome File                        : RT12_AGG_DESCR_ART.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La tabella 'RT12_AGG_DESCR_ART' svolge il ruolo fondamentale di tabella di transito, semaforo
e contenitore temporaneo per l'insieme di elaborazione batch ImpExp 'TMV_AGG_DESCR_ART'.

CONTESTO OPERATIVO E PIPELINE BATCH:
All'interno dell'ERP TeamSystem Gamma Enterprise, l'insieme batch 'TMV_AGG_DESCR_ART' si articola
in tre tracciati sequenziali (struttura 99):
1. 'TMV_AGG_DESART1':
   - In fase di pre-elaborazione (IE25_COMANDOIMP) esegue 'DELETE FROM RT12_AGG_DESCR_ART', svuotando
     completamente la tabella per preparare il buffer di lavoro.
   - Legge dalla vista di frontiera 'VPRT_TMV_AGG_DESCR_ART' gli articoli creati o variati di recente
     (tramite i log di anagrafica MO13 con data >= ultimo run memorizzato in RT14_VARIABILI_READYTEC)
     e popola la presente tabella RT12_AGG_DESCR_ART.
   - In fase di post-elaborazione (IE25_COMANDOEXP) aggiorna il timestamp in RT14_VARIABILI_READYTEC.
2. 'TMV_AGG_DESART2':
   - In fase di pre-elaborazione esegue la Stored Procedure 'SPRT_TMV_AGG_DESCR_ART', la quale itera
     esclusivamente sui codici articolo e opzione presenti in questa tabella RT12 per assemblare
     e aggiornare le descrizioni SHORT e LONG (lingua '' e 'LNG') in MG87_ARTDESC.
3. 'TMV_AGG_DESART3':
   - In fase di pre-elaborazione esegue la Stored Procedure 'SPRT_TMV_AGG_ARTICOLI_VARIE', la quale
     legge nuovamente i codici presenti in RT12 per abilitare le varianti in MG6B_GESVARART,
     assegnare i raggruppamenti su A3 (TONDI-DXXX o STANDARD) e creare i record di confezionamento
     e pesi in MG68_CONFART.

STRUTTURA E SCELTE TECNICHE:
- RT12_DITTA_CG18  (decimal(5,0)): Identificativo ditta Gamma (fissato su 1 per TMV).
- RT12_CODART_MG66 (char(25)): Codice articolo anagrafico primario (es. TDP..., TDR..., DADI..., ecc.).
- RT12_OPZIONE_MG5E (char(20)): Codice variante / opzione legata all'articolo (es. L100-, ecc.).
- Primary Key Clustered composta dalla tripletta (DITTA, CODART, OPZIONE) per garantire l'univocità
  dei record estratti dalla vista ed evitare elaborazioni duplicate o lock concorrenti.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (13/12/2021 - Coria F. / Bandera M.):
  Creazione iniziale della tabella per il transito e l'elaborazione selettiva degli articoli
  da aggiornare nell'ambito del batch di allineamento descrizioni.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Documentazione integrale, revisione secondo lo standard narrativo SOLVERIS e redazione
  dello script DDL protetto per verifica di esistenza e indicizzazione ottimale.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[RT12_AGG_DESCR_ART]') AND type in (N'U'))
BEGIN
    PRINT 'Creazione della tabella dbo.RT12_AGG_DESCR_ART in corso...';

    CREATE TABLE [dbo].[RT12_AGG_DESCR_ART](
        [RT12_DITTA_CG18]   [decimal](5, 0) NOT NULL,
        [RT12_CODART_MG66]  [char](25)      NOT NULL,
        [RT12_OPZIONE_MG5E] [char](20)      NOT NULL,
        CONSTRAINT [PK_RT12_AGG_DESCR_ART] PRIMARY KEY CLUSTERED 
        (
            [RT12_DITTA_CG18] ASC,
            [RT12_CODART_MG66] ASC,
            [RT12_OPZIONE_MG5E] ASC
        ) WITH (
            PAD_INDEX = OFF, 
            STATISTICS_NORECOMPUTE = OFF, 
            IGNORE_DUP_KEY = OFF, 
            ALLOW_ROW_LOCKS = ON, 
            ALLOW_PAGE_LOCKS = ON
        ) ON [PRIMARY]
    ) ON [PRIMARY];

    PRINT 'Tabella dbo.RT12_AGG_DESCR_ART creata con successo.';
END
ELSE
BEGIN
    PRINT 'Tabella dbo.RT12_AGG_DESCR_ART già esistente nel database.';
END
GO

