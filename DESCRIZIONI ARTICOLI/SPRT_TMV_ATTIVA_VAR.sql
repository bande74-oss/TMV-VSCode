/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPRT_TMV_ATTIVA_VAR (Allineamento e Bugfix Produzione)
Nome File                        : SPRT_TMV_ATTIVA_VAR.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPRT_TMV_ATTIVA_VAR' è preposta alla configurazione e abilitazione delle
varianti anagrafiche nella tabella 'MG6B_GESVARART' per tutti i nuovi codici articolo TMV
transitati nella tabella di lavoro 'RT12_AGG_DESCR_ART'.

CONTESTO DI ESECUZIONE NELLA PIPELINE BATCH:
All'interno dell'insieme ImpExp 'TMV_AGG_DESCR_ART', questa procedura viene invocata come primo
passaggio dalla Stored Procedure 'SPRT_TMV_AGG_ARTICOLI_VARIE' (tracciato 3 'TMV_AGG_DESART3').

LOGICA DI EREDITARIETA' DAL MODELLO (CLONAZIONE VARIANTI):
In Gamma Enterprise, gli articoli operativi (es. barre filettate, prigionieri, dadi con lega e
trattamenti specifici) derivano da un articolo "Modello" teorico (censito nella prima categoria
del configuratore commerciale CM01=1 / CM02_VALORESTR).
La procedura ha l'obiettivo di clonare sull'articolo operativo tutti gli attributi di gestione
delle varianti impostati sull'articolo modello omologo, ovvero:
  - MG6B_FLGGESTVAR     : Flag gestione variante attiva (0/1).
  - MG6B_CODRAGGVAR_MG5G: Codice raggruppamento varianti ammesso.
  - MG6B_INDOBBLIG      : Obbligatorietà di selezione.
  - MG6B_INDDEFAULT     : Presenza di un valore predefinito.
  - MG6B_VARDEFAULT     : Codice della variante predefinita.
  - MG6B_INDEREDIBA     : Ereditarietà in distinta base.
  - MG6B_INDPREZZO      : Modalità di impatto sul prezzo.
  - MG6B_INDQTA         : Modalità di calcolo della quantità.
  - MG6B_PREZZO, PERCMAGG, QTA, FLGSINGOLA, FLGOBBLIG.

ANALISI E RISOLUZIONE BUG CRITICO (Rev. 3.0):
Nel rilascio del 06/12/2023, durante il passaggio dalla vecchia gestione basata sulla tabella
personalizzata RT02 al recupero diretto dall'articolo modello in MG6B, era stata definita la nuova
istruzione SELECT ma era stata inavvertitamente omessa la dichiarazione del cursore:
  "DECLARE MyCursor CURSOR LOCAL FAST_FORWARD FOR"
Di conseguenza, al momento dell'istruzione "OPEN MyCursor", SQL Server sollevava l'errore:
  Msg 16916, Level 16, State 1: "A cursor with the name 'MyCursor' does not exist."
bloccando l'ereditarietà automatica delle varianti.
La presente revisione ripristina formalmente la dichiarazione del cursore garantendo la piena
operatività e stabilità dell'oggetto in produzione.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (16/01/2023 - Bandera Marco):
  Procedura iniziale eseguita in coda ai tracciati TMV-ANAGART per popolare le colonne decodificate
  con i subcodici articolo e gestire l'attivazione varianti tramite la tabella RT02_IMPORT_ART_ATTIVAVAR.
- Rev. 2.0 (06/12/2023 - Bandera Marco):
  Revisionata completamente la procedura introducendo il recupero informazioni non più da RT02 ma
  direttamente dalla MG6B dell'articolo modello di riferimento (omologo alla prima categoria di CM02).
- Rev. 3.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Rilevamento e risoluzione del bug fatale di mancata dichiarazione del cursore MyCursor (errore 16916).
  Ripristino di 'DECLARE MyCursor CURSOR LOCAL FAST_FORWARD FOR', normalizzazione del cartiglio
  e inserimento di 'WITH (NOLOCK)' sulle tabelle interrogate in sola lettura.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPRT_TMV_ATTIVA_VAR]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPRT_TMV_ATTIVA_VAR];
GO

CREATE PROCEDURE [dbo].[SPRT_TMV_ATTIVA_VAR]
AS
BEGIN
    SET NOCOUNT ON;

    -- Dichiarazione delle variabili di iterazione
    DECLARE @Ditta                  AS DECIMAL(5, 0);
    DECLARE @CodiceArticolo         AS CHAR(25);
    DECLARE @CodiceVariante         AS CHAR(20);

    DECLARE @MG6B_FLGGESTVAR        AS DECIMAL(1, 0);
    DECLARE @MG6B_CODRAGGVAR_MG5G   AS CHAR(25);
    DECLARE @MG6B_INDOBBLIG         AS DECIMAL(2, 0);
    DECLARE @MG6B_INDDEFAULT        AS DECIMAL(2, 0);
    DECLARE @MG6B_VARDEFAULT        AS CHAR(25);
    DECLARE @MG6B_INDEREDIBA        AS TINYINT;
    DECLARE @MG6B_INDPREZZO         AS TINYINT;
    DECLARE @MG6B_INDQTA            AS TINYINT;
    DECLARE @MG6B_PREZZO            AS DECIMAL(17, 6);
    DECLARE @MG6B_PERCMAGG          AS DECIMAL(6, 3);
    DECLARE @MG6B_QTA               AS DECIMAL(14, 6);
    DECLARE @MG6B_FLGSINGOLA        AS TINYINT;
    DECLARE @MG6B_FLGOBBLIG         AS TINYINT;

    -- =============================================================================================
    -- APERTURA CURSORE: RECUPERO DELLE VARIANTI DA CLONARE DALL'ARTICOLO MODELLO OMOLOGO
    -- =============================================================================================
    DECLARE MyCursor CURSOR LOCAL FAST_FORWARD FOR 
        SELECT 
            MG6B_OPERATIVO.MG6B_DITTA_CG18,
            MG6B_OPERATIVO.MG6B_CODART_MG66,
            MG6B_OPERATIVO.MG6B_CODICEVAR_MG5F,
            ATTIVAVAR.MG6B_FLGGESTVAR,
            ATTIVAVAR.MG6B_CODRAGGVAR_MG5G,
            ATTIVAVAR.MG6B_INDOBBLIG,
            ATTIVAVAR.MG6B_INDDEFAULT,
            ATTIVAVAR.MG6B_VARDEFAULT,
            ATTIVAVAR.MG6B_INDEREDIBA,
            ATTIVAVAR.MG6B_INDPREZZO,
            ATTIVAVAR.MG6B_INDQTA,
            ATTIVAVAR.MG6B_PREZZO,
            ATTIVAVAR.MG6B_PERCMAGG,
            ATTIVAVAR.MG6B_QTA,
            ATTIVAVAR.MG6B_FLGSINGOLA,
            ATTIVAVAR.MG6B_FLGOBBLIG
        FROM dbo.MG66_ANAGRART AS MG66 WITH (NOLOCK)
        INNER JOIN dbo.MG6B_GESVARART AS MG6B_OPERATIVO WITH (NOLOCK)
            ON  MG66.MG66_DITTA_CG18 = MG6B_OPERATIVO.MG6B_DITTA_CG18 
            AND MG66.MG66_CODART     = MG6B_OPERATIVO.MG6B_CODART_MG66
        INNER JOIN (
            -- Sottoquery che estrae le impostazioni varianti dagli articoli modello (CM01 = 1)
            SELECT MG6B_MODELLO.*
            FROM dbo.MG6B_GESVARART AS MG6B_MODELLO WITH (NOLOCK)
            INNER JOIN (
                SELECT CM02_VALORESTR 
                FROM dbo.CM02_VALORICATCOMM WITH (NOLOCK) 
                WHERE CM02_IDCATEGORIA_CM01 = 1
            ) AS ARTICOLI_MODELLO
                ON MG6B_MODELLO.MG6B_CODART_MG66 = ARTICOLI_MODELLO.CM02_VALORESTR
        ) AS ATTIVAVAR 
            ON  MG6B_OPERATIVO.MG6B_DITTA_CG18       = ATTIVAVAR.MG6B_DITTA_CG18
            AND MG6B_OPERATIVO.MG6B_CODICEVAR_MG5F   = ATTIVAVAR.MG6B_CODICEVAR_MG5F
            AND SUBSTRING(MG6B_OPERATIVO.MG6B_CODART_MG66, 1, 3) = ATTIVAVAR.MG6B_CODART_MG66
        INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            ON  MG66.MG66_DITTA_CG18 = RT12.RT12_DITTA_CG18
            AND MG66.MG66_CODART     = RT12.RT12_CODART_MG66;

    OPEN MyCursor;

    FETCH NEXT FROM MyCursor INTO 
        @Ditta,                 
        @CodiceArticolo,            
        @CodiceVariante,        
        @MG6B_FLGGESTVAR,       
        @MG6B_CODRAGGVAR_MG5G,  
        @MG6B_INDOBBLIG,        
        @MG6B_INDDEFAULT,   
        @MG6B_VARDEFAULT,       
        @MG6B_INDEREDIBA,   
        @MG6B_INDPREZZO,        
        @MG6B_INDQTA,       
        @MG6B_PREZZO,       
        @MG6B_PERCMAGG,     
        @MG6B_QTA,          
        @MG6B_FLGSINGOLA,       
        @MG6B_FLGOBBLIG;

    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        UPDATE dbo.MG6B_GESVARART 
        SET 
            MG6B_FLGGESTVAR      = @MG6B_FLGGESTVAR,     
            MG6B_CODRAGGVAR_MG5G = @MG6B_CODRAGGVAR_MG5G,   
            MG6B_INDOBBLIG       = @MG6B_INDOBBLIG,      
            MG6B_INDDEFAULT      = @MG6B_INDDEFAULT,     
            MG6B_VARDEFAULT      = @MG6B_VARDEFAULT,     
            MG6B_INDEREDIBA      = @MG6B_INDEREDIBA,     
            MG6B_INDPREZZO       = @MG6B_INDPREZZO,      
            MG6B_INDQTA          = @MG6B_INDQTA,     
            MG6B_PREZZO          = @MG6B_PREZZO,     
            MG6B_PERCMAGG        = @MG6B_PERCMAGG,       
            MG6B_QTA             = @MG6B_QTA,            
            MG6B_FLGSINGOLA      = @MG6B_FLGSINGOLA,     
            MG6B_FLGOBBLIG       = @MG6B_FLGOBBLIG   
        WHERE MG6B_DITTA_CG18     = @Ditta 
          AND MG6B_CODART_MG66    = @CodiceArticolo 
          AND MG6B_CODICEVAR_MG5F = @CodiceVariante;

        FETCH NEXT FROM MyCursor INTO 
            @Ditta,                 
            @CodiceArticolo,            
            @CodiceVariante,        
            @MG6B_FLGGESTVAR,       
            @MG6B_CODRAGGVAR_MG5G,  
            @MG6B_INDOBBLIG,        
            @MG6B_INDDEFAULT,   
            @MG6B_VARDEFAULT,       
            @MG6B_INDEREDIBA,   
            @MG6B_INDPREZZO,        
            @MG6B_INDQTA,       
            @MG6B_PREZZO,       
            @MG6B_PERCMAGG,     
            @MG6B_QTA,          
            @MG6B_FLGSINGOLA,       
            @MG6B_FLGOBBLIG;
    END;

    CLOSE MyCursor;
    DEALLOCATE MyCursor;
END;
GO

