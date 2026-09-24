/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 12:35
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Funzione Table-Valued dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI
Nome File                        : SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
La funzione 'dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI' è il componente algoritmico centrale preposto alla
formattazione, normalizzazione e suddivisione protetta delle descrizioni tecniche per gli articoli di TMV
all'interno di TeamSystem Gamma Enterprise, nel rispetto assoluto dei vincoli di colonna di 'MG87_ARTDESC':
- 'MG87_DESCART'    : VARCHAR(72)  (Descrizione breve / primaria: massimo 70 caratteri utili + CR+LF)
- 'MG87_DESCARTEST' : VARCHAR(1672) (Descrizione estesa / residua: testo eccedente + CR+LF)

REGOLE FONDAMENTALI DI FORMATTAZIONE E BUSINESS:
1. PRESIDIO UNITA' DI MISURA (INTEGRITA' DIMENSIONALE 'mm', 'mt', 'in'):
   Una misura tecnica (es. 'L:88 mm', '125 mm', 'Ø 120 mm', 'L:50 mm') costituisce un'entità logica
   e semantica inscindibile. La funzione impedisce tassativamente di spezzare tra il valore numerico
   e l'unità di misura (evitando l'errore sistemico del passato in cui il valore restava in MG87_DESCART
   e la sola dicitura 'mm' veniva relegata all'inizio di MG87_DESCARTEST).
   Se la specifica dimensionale non entra per intero nei 70 caratteri utili, l'intero blocco di misura
   viene preservato integro e spostato all'inizio della descrizione estesa.

2. PRESIDIO TERMINAZIONE RIGHE (ZERO SPAZI DI CODA, CR+LF OBBLIGATORIO):
   Le descrizioni generate non devono MAI contenere spazi vuoti di coda (trailing spaces).
   In conformità agli standard di visualizzazione e stampa dei documenti Gamma Enterprise (DDT, Fatture,
   Certificati di Collaudo 3.1), ogni campo ('Descr' e 'DescrEst') DEVE terminare con un ritorno a capo
   completo CR+LF (CHAR(13) + CHAR(10)).
   Questa indicazione (CR+LF) si applica unicamente se il campo assume un valore diverso da spazi vuoti
   o da NULL (se il testo è vuoto, il campo viene valorizzato a NULL).

PARAMETRI DI INPUT:
- @RawText : NVARCHAR(MAX) - Stringa grezza della descrizione tecnica calcolata da decodifica configuratore.

OUTPUT:
- Descr    : NVARCHAR(72)  - Testo primario normalizzato (max 70 car. + CR+LF, zero spazi di coda).
- DescrEst : NVARCHAR(1672) - Testo esteso normalizzato (zero spazi di coda + CR+LF, oppure NULL se vuoto).
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Rilascio iniziale della funzione per la gestione intelligente dello spezzamento e della terminazione CR+LF,
  eliminando alla radice la separazione indebita di 'mm' dalla quota e garantendo l'assenza di spazi di coda.
- Rev. 2.0 (24/09/2026 - SOLVERIS - Bandera Marco):
  Affinamento della soglia dimensionale per evitare spezzamenti fittizi:
  1. Se la stringa pulita ha una lunghezza tra 71 e 72 caratteri (occupando per intero la colonna VARCHAR(72)
     senza richiedere descrizione estesa), viene preservata integra in 'Descr' senza spezzarla e senza
     accodare CR+LF, evitando la generazione spuria di descrizioni estese composte da una sola parola.
  2. Protezione avanzata delle quote in frazioni di pollice (es. '1 1/2"', '1 1/4"', '2 1/4"'): impedisce
     tassativamente di spezzare tra l'intero e la frazione numerica ('[0-9]/%').
- Rev. 2.1 (24/09/2026 - SOLVERIS - Bandera Marco):
  1. Preservazione tassativa dei ritorni a capo interni (CHAR(13)+CHAR(10)) generati dalla funzione decodifica
     tra Tipologia, Materiale e Diametro/Passo: la pulizia preliminare opera SOLO ai bordi della stringa
     (TRIM(' \t\r\n' FROM @RawText)) evitando di comprimere le righe su una stringa unica senza spazi.
  2. Protezione del simbolo diametro 'Ø': impedisce tassativamente di spezzare subito dopo 'Ø' preservando
     l'integrità del blocco dimensionale (es. 'Ø 125 mm' o 'Ø 14,65mm').
  3. DROP incondizionato dell'oggetto per evitare conflitti di tipo oggetto tra Inline (IF) e Multi-statement (TF).
====================================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'[dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI]') IS NOT NULL
    DROP FUNCTION [dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI];
GO

CREATE FUNCTION [dbo].[SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI]
(
    @RawText NVARCHAR(MAX)
)
RETURNS @Result TABLE
(
    DescrizionePrimaria  VARCHAR(72)    NULL,
    DescrizioneEstesa    VARCHAR(1672)  NULL,
    Descr                VARCHAR(72)    NULL,
    DescrEst             VARCHAR(1672)  NULL
)
AS
BEGIN
    IF @RawText IS NULL
    BEGIN
        INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
        VALUES (NULL, NULL, NULL, NULL);
        RETURN;
    END;

    -- Pulizia preliminare: eliminazione di spazi, tabulazioni e ritorni a capo iniziali/finali
    DECLARE @Clean NVARCHAR(MAX) = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM @RawText);

    IF @Clean = ''
    BEGIN
        INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst) 
        VALUES (NULL, NULL, NULL, NULL);
        RETURN;
    END;

    -- 1. Se la stringa pulita entra interamente nei 72 caratteri fisici di MG87_DESCART:
    --    non richiede alcuno spezzamento e viene allocata interamente nella descrizione primaria.
    IF LEN(@Clean) <= 72
    BEGIN
        -- Se la lunghezza è <= 70 caratteri, possiamo accodare il terminatore CR+LF rimanendo entro i 72 caratteri massimi
        IF LEN(@Clean) <= 70
        BEGIN
            DECLARE @val70 NVARCHAR(72) = @Clean + CHAR(13) + CHAR(10);
            INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
            VALUES (@val70, NULL, @val70, NULL);
            RETURN;
        END
        ELSE
        BEGIN
            -- Se la lunghezza è esattamente 71 o 72 caratteri, occupa per intero la larghezza fisica del campo:
            -- salvaguardiamo la stringa intera senza spezzarla (evitando descrizioni estese fittizie di una sola parola)
            -- e senza aggiungere CR+LF per non eccedere il limite fisico di 72 byte della colonna.
            INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
            VALUES (@Clean, NULL, @Clean, NULL);
            RETURN;
        END;
    END;

    -- 2. Se la stringa supera i 72 caratteri, ricerchiamo il punto di spezzamento a ritroso da posizione 71
    DECLARE @cut INT = 0;
    DECLARE @pos INT = 71;

    WHILE @pos > 1
    BEGIN
        IF SUBSTRING(@Clean, @pos, 1) IN (' ', CHAR(13), CHAR(10))
        BEGIN
            -- Isola la porzione testuale successiva allo spazio/separatore (eliminando spazi iniziali)
            DECLARE @after NVARCHAR(20) = LTRIM(SUBSTRING(@Clean, @pos + 1, 10));

            -- REGOLA FONDAMENTALE DI BUSINESS:
            -- Non spezzare mai se lo spazio precede direttamente:
            -- a) Un'unità di misura ('mm', 'mt', 'in')
            -- b) Una virgola decimale (',')
            -- c) Una frazione numerica di pollice (es. '1/2', '1/4', '3/8')
            -- d) Subito dopo il simbolo diametro 'Ø' (preserva integro il blocco 'Ø 125 mm' o 'Ø 14,65mm')
            IF @after NOT LIKE 'mm%' 
               AND @after NOT LIKE 'mt%' 
               AND @after NOT LIKE 'in%' 
               AND @after NOT LIKE ',%'
               AND @after NOT LIKE '[0-9]/%'
               AND SUBSTRING(@Clean, @pos - 1, 1) <> CHAR(216)
               AND SUBSTRING(@Clean, @pos - 1, 1) <> 'Ø'
            BEGIN
                SET @cut = @pos;
                BREAK;
            END;
        END;
        SET @pos = @pos - 1;
    END;

    -- Fallback di sicurezza: se non viene trovato alcuno spazio utile, spezza forzatamente al 70° carattere
    IF @cut = 0 
        SET @cut = 70;

    -- Estrazione e pulizia delle due porzioni risultanti
    DECLARE @p1 NVARCHAR(72)   = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM LEFT(@Clean, @cut));
    DECLARE @p2 NVARCHAR(MAX)  = TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM SUBSTRING(@Clean, @cut + 1, LEN(@Clean)));

    -- Applicazione della regola: zero spazi di coda, aggiunta del terminatore CR+LF nel rispetto dei limiti di colonna
    DECLARE @descr NVARCHAR(72) = CASE 
                                      WHEN @p1 = '' THEN NULL 
                                      WHEN LEN(@p1) <= 70 THEN @p1 + CHAR(13) + CHAR(10)
                                      ELSE @p1 
                                  END;
    DECLARE @descrEst NVARCHAR(1672) = CASE WHEN @p2 <> '' THEN @p2 + CHAR(13) + CHAR(10) ELSE NULL END;

    INSERT INTO @Result (DescrizionePrimaria, DescrizioneEstesa, Descr, DescrEst)
    VALUES (@descr, @descrEst, @descr, @descrEst);

    RETURN;
END;
GO

