USE [DBTMV]
GO

/****** Object:  View [dbo].[VPRT_DIBA_LOCALIZZATA_RTP]    Script Date: 01/09/2026 16:00:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



/*
================================================================================================
1 - DATA MODIFICA: 30/06/2026 17:40
2 - AUTORE: SOLVERIS - Bandera Marco
3 - DESCRIZIONE: Vista per l'estrazione delle righe di distinte base (DIBA) rilocabili 
    (documenti di tipo 21/1) da destinare alla gestione RTP. La vista filtra le righe da evadere 
    escludendo gli articoli fittizi e seleziona gli stati di avanzamento specifici (10046, 10054, 10055).
    Verifica le politiche di approvvigionamento ('Stock') ed esclude esplicitamente 
    le righe con extralavorazioni che modificano il ciclo produttivo.
    --------------------------------------------------------------------------------------------
    INTEGRAZIONE NUOVA FUNZIONALITÀ: Include aggiuntivamente le righe che trovano corrispondenza 
    nella tabella di configurazione tecnica MINMAX INOX, a condizione che abbiano una giacenza 
    attuale positiva (> 0) nel calcolo dei progressivi di magazzino (MG70).
================================================================================================
STORICO REVISIONI:
- Rev. 1: Modifiche storiche stratificate (BM: 01/08/2024, 05/12/2024, 01/04/2025, 08/04/2025, 17/10/2025, 13/01/2026).
- Rev. 2 (GEMINI): 30/06/2026 - Revisione cosmetica. Adozione alias per leggibilità, 
  inserimento direttive WITH (NOLOCK) per letture non bloccanti, rinominazione in _GEMINI.
- Rev. 3 (GEMINI): 30/06/2026 - Integrazione logica di inclusione record da RT00_CONFTEC_MINMAX_INOX
  incrociata con progressivi di magazzino positivi su MG70_MAGPROQTA.
- Rev. 4 (GEMINI): 30/06/2026 - Modifica della JOIN su tabella INOX. Sostituito il campo di confronto 
  con RT00_OPZIONE_MG58_MP ed introdotta la decodifica dinamica della lunghezza assoluta 
  (formato L----) per includere anche i valori maggiori o uguali (>=) rispetto alla riga documento.
	Rev.5 (BANDERA) a seguito di segnalazione Beccalori del 28/08/2026 ordine n. 4822 riga 20 e similari), si aaggiunge una clausola di esclusione per eliminare le viti INOX la cui 
	DO05_DESCRIZIONE not like %lavorazion% (sostituito poi con controllo DO36_INDST1 <> 4 per performance)
================================================================================================
*/
CREATE OR ALTER    VIEW [dbo].[VPRT_DIBA_LOCALIZZATA_RTP]
AS
SELECT TOP (100) PERCENT 
			--inox.*,
			--'*******************' as SEPARA,
			--MAG.MG70_CODART_MG66,
			--MAG.MG70_OPZIONE_MG5E,
			--MAG.MG70_QGIACATT,
			--'*******************' as SEPARA2,
            -- Dati Testata
            TESTATA.DO11_DITTA_CG18,
            TESTATA.DO11_NUMREG_CO99,
            TESTATA.DO11_DOCUM_MG36,
            TESTATA.DO11_NUMDOC,
            TESTATA.DO11_GUID,
            
            -- Dati Corpo Documento
            CORPO.DO30_GUID,
            CORPO.DO30_CODART_MG66,
            CORPO.DO30_OPZIONE_MG5E,
            STATI.CO4H_IDSTATO_CO4C,
			STATI_DES.CO4C_DESCRIZIONE,
            TESTATA.DO11_DATADOC,
            CORPO.DO30_PROGRIGA,
            
            -- Classificazioni aggiuntive
            DECODE_INDST1.DO36_INDST1,
            DECODE_INDST1.DO05_DESCRIZIONE,
            ARTPROD.PD18_INDGESDISBA,
            
            -- Dati Politica
            POLITICA.RT00_POLITICA,
            POLITICA.RT00_BATCH_NUMBER,
            POLITICA_DIBA.RT00_POLITICA AS RT00_POLITICA_DIBA_CODART,           /* POLITICA DEL COMPONENTE */
            POLITICA_DIBA.RT00_BATCH_NUMBER AS RT00_BATCH_NUMBER_DIBA_CODART

FROM        dbo.DO11_DOCTESTATA AS TESTATA WITH (NOLOCK)
        
        -- Join con il Corpo Documento
        INNER JOIN dbo.DO30_DOCCORPO AS CORPO WITH (NOLOCK)
            ON  TESTATA.DO11_DITTA_CG18 = CORPO.DO30_DITTA_CG18 
            AND TESTATA.DO11_NUMREG_CO99 = CORPO.DO30_NUMREG_CO99 
        
        -- Determinazione dello Stato Attuale della riga
        INNER JOIN dbo.CO4H_STATIATTUALI AS STATI WITH (NOLOCK)
            ON  CORPO.DO30_GUID = STATI.CO4H_GUID 
        INNER JOIN dbo.CO4C_STATI AS STATI_DES  WITH (NOLOCK)
		    ON	STATI.CO4H_IDSTATO_CO4C = STATI_DES.CO4C_IDSTATO
        -- Anagrafica Articolo
        INNER JOIN dbo.MG66_ANAGRART AS ANAGRART WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = ANAGRART.MG66_DITTA_CG18 
            AND CORPO.DO30_CODART_MG66 = ANAGRART.MG66_CODART 
        
        -- Parametri di Produzione Articolo
        LEFT OUTER JOIN dbo.PD18_ARTPROD AS ARTPROD WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = ARTPROD.PD18_DITTA_CG18 
            AND CORPO.DO30_CODART_MG66 = ARTPROD.PD18_CODART_MG66 
        
        -- Dettaglio Stato del Corpo Documento
        INNER JOIN dbo.DO72_DOCCORPOSTATO AS CORPOSTATO WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = CORPOSTATO.DO72_DITTA_CG18 
            AND CORPO.DO30_NUMREG_CO99 = CORPOSTATO.DO72_NUMREG_CO99 
            AND CORPO.DO30_PROGRIGA = CORPOSTATO.DO72_PROGRIGA 
        
        -- Decodifiche Indici
        LEFT OUTER JOIN dbo.VPRT_DECODE_DO36_INDST1 AS DECODE_INDST1 WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = DECODE_INDST1.DO36_DITTA_CG18 
            AND CORPO.DO30_NUMREG_CO99 = DECODE_INDST1.DO36_NUMREG_CO99 
            AND CORPO.DO30_PROGRIGA = DECODE_INDST1.DO36_PROGRIGA 
                         
        -- Politica sulla riga
        LEFT OUTER JOIN dbo.RT00_TEMP_DADI_POLITICA AS POLITICA WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = POLITICA.RT00_DITTA_CG18 
            AND CORPO.DO30_CODART_MG66 = POLITICA.RT00_CODART_MG66 
            AND CORPO.DO30_OPZIONE_MG5E = POLITICA.RT00_OPZIONE_MG58
        
        -- Politica a livello di componente DIBA
        LEFT OUTER JOIN dbo.RT00_TEMP_DADI_POLITICA AS POLITICA_DIBA WITH (NOLOCK)
            ON  POLITICA.RT00_DITTA_CG18 = POLITICA_DIBA.RT00_DITTA_CG18 
            AND POLITICA.RT00_DIBA_CODART = POLITICA_DIBA.RT00_CODART_MG66 
            AND POLITICA.RT00_OPZIONE = POLITICA_DIBA.RT00_OPZIONE_MG58

        -- Rev.4: Aggancio configurazione tecnica MINMAX INOX basata sulla lunghezza assoluta delle opzioni.
        -- [PROPOSTA DI OTTIMIZZAZIONE]: Esecuzione di CROSS APPLY per precalcolare TRY_CAST e rimuoverlo dalla LEFT JOIN successiva
        CROSS APPLY (
            SELECT ValoreNumericoOpzione = TRY_CAST(SUBSTRING(CORPO.DO30_OPZIONE_MG5E, 2, CHARINDEX('-', CORPO.DO30_OPZIONE_MG5E + '-') - 2) AS INT)
        ) AS ExtrOpzione

        LEFT OUTER JOIN dbo.RT00_CONFTEC_MINMAX_INOX AS INOX WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = INOX.RT00_DITTA_CG18
            AND CORPO.DO30_CODART_MG66 = INOX.RT00_CODART_MG66_PF
            -- L'indice sulla colonna calcolata migliora nettamente le performance
            AND TRY_CAST(SUBSTRING(INOX.RT00_OPZIONE_MG58_MP, 2, CHARINDEX('-', INOX.RT00_OPZIONE_MG58_MP + '-') - 2) AS INT) >= ExtrOpzione.ValoreNumericoOpzione

        -- Progressivi di magazzino filtrati per l'anno corrente (0), tipo progressivo (1), tipo quantità (1) e giacenza attuale positiva (> 0)
        LEFT OUTER JOIN dbo.MG70_MAGPROQTA AS MAG WITH (NOLOCK)
            ON  CORPO.DO30_DITTA_CG18 = MAG.MG70_DITTA_CG18
            AND CORPO.DO30_CODART_MG66 = MAG.MG70_CODART_MG66
            AND CORPO.DO30_OPZIONE_MG5E = MAG.MG70_OPZIONE_MG5E
            AND MAG.MG70_ANNO = 0
            AND MAG.MG70_TIPOPROG = 1
            AND MAG.MG70_TIPOQTA = 1
            AND MAG.MG70_QGIACATT > 0
			
WHERE       (TESTATA.DO11_TIPODOC = 21) 
        AND (TESTATA.DO11_STIPODOC = 1) 
		AND (TESTATA.DO11_DOCUM_MG36 <> 'DC-ORDINE-PPP')
        AND (CORPO.DO30_INDTIPORIGA = 0) 
        AND (CORPO.DO30_INDTIPODATI = 0) 
        AND (ANAGRART.MG66_INDFITTIZIO = 0) 
        AND (CORPOSTATO.DO72_FLGDAEVADERE = 1) 
        AND (STATI.CO4H_IDSTATO_CO4C IN (10046, 10054, 10055))
        -- Filtro estrazione basato su Politiche Standard OPPURE su presenza regole MINMAX INOX con Giacenza
        AND (
                -- Condizione Stock 1: Articolo principale gestito a Stock con batch number valorizzato
                ((ISNULL(POLITICA.RT00_POLITICA, '') = 'Stock') AND (ISNULL(POLITICA.RT00_BATCH_NUMBER, '') <> ''))
                OR
                -- Condizione Stock 2: Componente DIBA gestito a Stock con batch, e articolo a Stock
                (       
                        (ISNULL(POLITICA_DIBA.RT00_POLITICA, '') = 'Stock')             
                    AND (ISNULL(POLITICA_DIBA.RT00_BATCH_NUMBER, '') <> '')         
                    AND (ISNULL(POLITICA.RT00_POLITICA, '') = 'Stock')              
                )
                OR
                -- Nuova Funzionalità (Rev.3 / Rev.4 / Rev.5): Match su Configurazione Tecnica Inox E contemporanea giacenza reale a magazzino
                (
                        INOX.RT00_CODART_MG66_PF IS NOT NULL
                    AND MAG.MG70_CODART_MG66 IS NOT NULL
                    -- [PROPOSTA DI OTTIMIZZAZIONE]: Sostituita la ricerca text-based e l'ISNULL con un costrutto interamente SARGable.
                    -- Usa il codice (4) garantendo la massima velocità di Index Seek.
                    AND (DECODE_INDST1.DO36_INDST1 <> 4 )
                )
            )

        -- Esclusione righe con extralavorazioni che modificano il ciclo (Modifiche BM: 17/10/2025 e 13/01/2026)
        AND dbo.SPRT_EXTRALAV_SINO(CORPO.DO30_DITTA_CG18, CORPO.DO30_NUMREG_CO99, CORPO.DO30_PROGRIGA) = 0

ORDER BY corpo.do30_progriga, CORPO.DO30_CODART_MG66, CORPO.DO30_OPZIONE_MG5E
GO

