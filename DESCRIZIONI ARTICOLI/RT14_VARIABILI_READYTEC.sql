/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Tabella dbo.RT14_VARIABILI_READYTEC (DDL e Inizializzazione)
Nome File                        : RT14_VARIABILI_READYTEC.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La tabella 'RT14_VARIABILI_READYTEC' è l'infrastruttura centrale per la persistenza di variabili,
parametri di runtime e semafori temporali (watermarks) condivisi tra i vari processi batch,
Stored Procedure e viste personalizzate SOLVERIS per l'ERP Gamma Enterprise.

RUOLO NELL'INSIEME BATCH 'TMV_AGG_DESCR_ART':
All'interno del processo di aggiornamento descrizioni articoli, la variabile specifica
denominata 'SPRT_TMV_AGG_DESCR_ART' memorizza il timestamp esatto dell'ultima esecuzione batch
completata con successo:
1. La vista sorgente 'VPRT_TMV_AGG_DESCR_ART' (utilizzata dal tracciato 'TMV_AGG_DESART1')
   utilizza questo valore mediante la subquery:
     SELECT RT14_DITTA_CG18, RT14_DATE_VALUE 
     FROM dbo.RT14_VARIABILI_READYTEC WITH (NOLOCK)
     WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'
   e filtra la tabella di log anagrafico articoli:
     LOG_ARTICOLI.MO13_DATALOG >= ULTIMA_DATA_EXEC.RT14_DATE_VALUE
   In questo modo, la vista garantisce una lettura *strettamente incrementale* (delta), evitando
   di riprocessare inutilmente l'intero catalogo anagrafico composto da centinaia di migliaia di
   articoli e riducendo il tempo di elaborazione a pochi decimi di secondo.
2. Al termine dell'estrazione dei record nel tracciato 'TMV_AGG_DESART1', il comando di post-elaborazione
   (IE25_COMANDOEXP) esegue:
     UPDATE RT14_VARIABILI_READYTEC 
     SET RT14_DATE_VALUE = GETDATE() 
     WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART';
   avanzando il watermark al momento corrente.

STRUTTURA DEI CAMPI:
- RT14_DITTA_CG18    (decimal(5,0)): Codice ditta di appartenenza (fissato su 1).
- RT14_VARNAME       (varchar(50)): Nome univoco della variabile (Chiave primaria con la ditta).
- RT14_NUMBER_VALUE  (decimal(18,6)): Eventuale valore numerico o progressivo.
- RT14_DATE_VALUE    (datetime): Timestamp o data/ora di riferimento.
- RT14_STRING_VALUE  (varchar(250)): Eventuale parametro testuale.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (Origine): Tabella parametri per i moduli personalizzati Readytec / SOLVERIS.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Documentazione integrale, revisione secondo lo standard narrativo SOLVERIS e redazione
  dello script DDL protetto con clausola di seeding idempotente per 'SPRT_TMV_AGG_DESCR_ART'.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[RT14_VARIABILI_READYTEC]') AND type in (N'U'))
BEGIN
    PRINT 'Creazione della tabella dbo.RT14_VARIABILI_READYTEC in corso...';

    CREATE TABLE [dbo].[RT14_VARIABILI_READYTEC](
        [RT14_DITTA_CG18]    [decimal](5, 0) NOT NULL,
        [RT14_VARNAME]       [varchar](50)   NOT NULL,
        [RT14_NUMBER_VALUE]  [decimal](18, 6) NULL,
        [RT14_DATE_VALUE]    [datetime]       NULL,
        [RT14_STRING_VALUE]  [varchar](250)   NULL,
        CONSTRAINT [PK_RT14_VARIABILI_READYTEC] PRIMARY KEY CLUSTERED 
        (
            [RT14_DITTA_CG18] ASC,
            [RT14_VARNAME] ASC
        ) WITH (
            PAD_INDEX = OFF, 
            STATISTICS_NORECOMPUTE = OFF, 
            IGNORE_DUP_KEY = OFF, 
            ALLOW_ROW_LOCKS = ON, 
            ALLOW_PAGE_LOCKS = ON
        ) ON [PRIMARY]
    ) ON [PRIMARY];

    PRINT 'Tabella dbo.RT14_VARIABILI_READYTEC creata con successo.';
END
ELSE
BEGIN
    PRINT 'Tabella dbo.RT14_VARIABILI_READYTEC già esistente.';
END
GO

-- Seeding e controllo di integrità della variabile di timestamp per il batch descrizioni articoli
IF NOT EXISTS (
    SELECT 1 
    FROM dbo.RT14_VARIABILI_READYTEC WITH (NOLOCK) 
    WHERE RT14_DITTA_CG18 = 1 AND RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'
)
BEGIN
    PRINT 'Inizializzazione della variabile SPRT_TMV_AGG_DESCR_ART in RT14_VARIABILI_READYTEC...';
    INSERT INTO dbo.RT14_VARIABILI_READYTEC (RT14_DITTA_CG18, RT14_VARNAME, RT14_NUMBER_VALUE, RT14_DATE_VALUE, RT14_STRING_VALUE)
    VALUES (1, 'SPRT_TMV_AGG_DESCR_ART', NULL, GETDATE(), 'Watermark temporale batch descrizioni TMV');
    PRINT 'Inizializzazione completata.';
END
ELSE
BEGIN
    PRINT 'Variabile SPRT_TMV_AGG_DESCR_ART già configurata in RT14_VARIABILI_READYTEC.';
END
GO

