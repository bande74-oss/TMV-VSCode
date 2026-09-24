/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 23/09/2026 17:30
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Stored Procedure dbo.SPRT_TMV_AGG_ARTICOLI_VARIE (Sorgente Produzione)
Nome File                        : SPRT_TMV_AGG_ARTICOLI_VARIE.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La Stored Procedure 'dbo.SPRT_TMV_AGG_ARTICOLI_VARIE' governa l'ultimo passaggio (Passo 3)
della pipeline batch 'TMV_AGG_DESCR_ART', eseguita come pre-elaborazione (IE25_COMANDOIMP)
del tracciato 'TMV_AGG_DESART3'.

OBIETTIVO DI BUSINESS E FUNZIONALITA':
Quando un articolo viene creato ex novo dal configuratore commerciale o da processi automatici,
la semplice generazione dell'anagrafica base e delle descrizioni (Passi 1 e 2) non è sufficiente
a renderlo operativamente utilizzabile nei moduli di produzione, logistica e magazzino.
Questa procedura ha il compito di completare e blindare le caratteristiche tecniche fondamentali:

1. ATTIVAZIONE VARIANTI DAL MODELLO:
   - Invoca 'SPRT_TMV_ATTIVA_VAR' per copiare i flag e le regole di variante dall'articolo modello.
2. GESTIONE SPECIALE BARRE TONDE SU VARIANTE 4 (A3):
   - Per gli articoli di tipologia TDP, TDR, TDL, TDF che presentano il carattere 'D' nella posizione 9
     del codice articolo (identificativo di barra con diametro tornito/pelato a disegno), la variante
     4 (codice 'A3') deve essere configurata obbligatoriamente sul raggruppamento 'TONDI-DXXX':
       * MG6B_FLGGESTVAR = 1 (Gestione attiva)
       * MG6B_CODRAGGVAR_MG5G = 'TONDI-DXXX'
       * MG6B_INDOBBLIG = 1 (Scelta obbligatoria in inserimento righe)
       * MG6B_INDDEFAULT = 1, MG6B_VARDEFAULT = '000' (Valore predefinito)
3. GESTIONE STANDARD PER ALTRI ARTICOLI SU VARIANTE 4 (A3):
   - Per tutti gli altri articoli che gestiscono la variante A3 ma non sono barre con 'D' al 9° car.:
       * MG6B_CODRAGGVAR_MG5G = 'STANDARD'
       * MG6B_INDOBBLIG = 0, MG6B_INDDEFAULT = 0, MG6B_VARDEFAULT = NULL
4. CREAZIONE RECORD LOGISTICO E IMBALLI IN MG68_CONFART (PKL):
   - Inserisce la confezione di default 'CD' (Confezione Default) per ciascun articolo/opzione presente
     in RT12_AGG_DESCR_ART che non la possiede ancora.
   - Inizializza le unità di misura: Peso in 'KG', Dimensioni in 'MM', Volume in 'CM3'.
   - Questo passaggio è propedeutico e indispensabile per consentire ai successivi batch di logistica
     (es. TMV-PKL-PESI-PEZZI-SCATOLA e packing list) di valorizzare e gestire correttamente pesi e colli.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (16/02/2023 - Bandera Marco):
  Creazione iniziale della stored procedure inserita come post-elaborazione per completare la gestione
  degli articoli creati ex novo e impostarli con le caratteristiche concordate.
- Rev. 1.1 (06/03/2024 - Bandera Marco):
  Aggiunta la sezione di popolamento automatico della tabella MG68_CONFART con i dati base di peso,
  volume e dimensioni per l'integrazione con il modulo PKL e packing list.
- Rev. 2.0 (23/09/2026 - SOLVERIS - Bandera Marco):
  Revisione secondo lo standard narrativo SOLVERIS. Inserimento di commenti dettagliati riga per riga,
  ottimizzazione con clausole WITH (NOLOCK) e formalizzazione dell'oggetto per ambiente MSSQL 14.0.
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SPRT_TMV_AGG_ARTICOLI_VARIE]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[SPRT_TMV_AGG_ARTICOLI_VARIE];
GO

CREATE PROCEDURE [dbo].[SPRT_TMV_AGG_ARTICOLI_VARIE]
AS
BEGIN
    SET NOCOUNT ON;

    -- =============================================================================================
    -- PASSO 1: ESECUZIONE DELLA PROCEDURA DI ATTIVAZIONE ED EREDITARIETA' VARIANTI DAL MODELLO
    -- =============================================================================================
    EXEC dbo.SPRT_TMV_ATTIVA_VAR;

    -- =============================================================================================
    -- PASSO 2: CONFIGURAZIONE VARIANTE 4 (A3) PER BARRE TONDE TDP/TDR/TDL/TDF CON DIAMETRO 'D'
    -- =============================================================================================
    WITH CteTondiDxxx AS (
        SELECT 
            MG6B.MG6B_FLGGESTVAR,
            MG6B.MG6B_CODRAGGVAR_MG5G,
            MG6B.MG6B_INDOBBLIG,
            MG6B.MG6B_INDDEFAULT,
            MG6B.MG6B_VARDEFAULT
        FROM dbo.MG6B_GESVARART AS MG6B
        INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
            AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66
        WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) = 'D' 
          AND SUBSTRING(MG6B.MG6B_CODART_MG66, 1, 3) IN ('TDP','TDR','TDL','TDF')
          AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
          AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'TONDI-DXXX'
    )
    UPDATE CteTondiDxxx  
    SET
        MG6B_FLGGESTVAR      = 1,
        MG6B_CODRAGGVAR_MG5G = 'TONDI-DXXX',
        MG6B_INDOBBLIG       = 1,
        MG6B_INDDEFAULT      = 1,
        MG6B_VARDEFAULT      = '000';

    -- =============================================================================================
    -- PASSO 3: ASSEGNAZIONE RAGGRUPPAMENTO 'STANDARD' PER GLI ALTRI ARTICOLI SU VARIANTE 4 (A3)
    -- =============================================================================================
    WITH CteStandardA3 AS (
        SELECT 
            MG6B.MG6B_FLGGESTVAR,
            MG6B.MG6B_CODRAGGVAR_MG5G,
            MG6B.MG6B_INDOBBLIG,
            MG6B.MG6B_INDDEFAULT,
            MG6B.MG6B_VARDEFAULT
        FROM dbo.MG6B_GESVARART AS MG6B
        INNER JOIN dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
            ON  MG6B.MG6B_DITTA_CG18  = RT12.RT12_DITTA_CG18
            AND MG6B.MG6B_CODART_MG66 = RT12.RT12_CODART_MG66 
        WHERE SUBSTRING(MG6B.MG6B_CODART_MG66, 9, 1) <> 'D' 
          AND MG6B.MG6B_CODICEVAR_MG5F = 'A3' 
          AND MG6B.MG6B_FLGGESTVAR = 1 
          AND ISNULL(MG6B.MG6B_CODRAGGVAR_MG5G, '') <> 'STANDARD'
    )
    UPDATE CteStandardA3 
    SET
        MG6B_FLGGESTVAR      = 1,
        MG6B_CODRAGGVAR_MG5G = 'STANDARD',
        MG6B_INDOBBLIG       = 0,
        MG6B_INDDEFAULT      = 0,
        MG6B_VARDEFAULT      = NULL;

    -- =============================================================================================
    -- PASSO 4: INIZIALIZZAZIONE DELLA CONFEZIONE BASE IN MG68_CONFART (PESI, DIMENSIONI E VOLUMI)
    -- =============================================================================================
    INSERT INTO dbo.MG68_CONFART (
        MG68_DITTA_CG18,
        MG68_CODART_MG66,
        MG68_OPZIONE_MG5E,
        MG68_CODCONFEZ_MG96,
        MG68_FLGCONFPREF,
        MG68_PZCONF,
        MG68_UMPESO,
        MG68_PESON,
        MG68_PESOL,
        MG68_UMCAPAC,
        MG68_CAPAC,
        MG68_UMDIMEN,
        MG68_LARGH,
        MG68_ALTEZ,
        MG68_PROF,
        MG68_UMVOLUME,
        MG68_VOLUME,
        MG68_CONFXCOLLO,
        MG68_COLLIXSTRATO,
        MG68_LARGHCOLLO,
        MG68_COLLIXBANCALE,
        MG68_ALTEZCOLLO,
        MG68_PROFCOLLO,
        MG68_CLASSEMAXSTOC,
        MG68_IDMEDIA_CG99
    )
    SELECT 
        RT12.RT12_DITTA_CG18,
        RT12.RT12_CODART_MG66,
        RT12.RT12_OPZIONE_MG5E,
        'CD',                   -- Codice confezione standard: CD (Confezione Default)
        1,                      -- Confezione preferenziale = 1
        0,                      -- Pezzi per confezione
        'KG',                   -- Unità di misura peso
        0,                      -- Peso Netto
        0,                      -- Peso Lordo
        NULL,                   -- Unità di misura capacità
        0,                      -- Capacità
        'MM',                   -- Unità di misura dimensioni
        0,                      -- Larghezza
        0,                      -- Altezza
        0,                      -- Profondità
        'CM3',                  -- Unità di misura volume
        0,                      -- Volume
        1,                      -- Confezioni per collo
        0,                      -- Colli per strato
        0,                      -- Larghezza collo
        0,                      -- Colli per bancale
        0,                      -- Altezza collo
        0,                      -- Profondità collo
        0,                      -- Classe massima stoccaggio
        NULL                    -- Identificativo media
    FROM dbo.RT12_AGG_DESCR_ART AS RT12 WITH (NOLOCK)
    LEFT JOIN dbo.MG68_CONFART AS MG68 WITH (NOLOCK)
        ON  RT12.RT12_DITTA_CG18   = MG68.MG68_DITTA_CG18
        AND RT12.RT12_CODART_MG66  = MG68.MG68_CODART_MG66
        AND RT12.RT12_OPZIONE_MG5E = MG68.MG68_OPZIONE_MG5E
    WHERE MG68.MG68_CODCONFEZ_MG96 IS NULL;

END;
GO

