USE [DBTMV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ========================================================================================
-- OGGETTO:             [dbo].[SPRT_LTT_FAKE_OLD_2026_03_04]
-- TIPO OGGETTO:        FUNZIONE SCALARE (UDF - USER DEFINED FUNCTION)
-- AMBIENTE/DATABASE:   MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
-- AUTORE:              SOLVERIS - Bandera Marco
-- DATA MODIFICA:       2026-09-23 10:45
--
-- ----------------------------------------------------------------------------------------
-- DESCRIZIONE FUNZIONALE E NARRATIVA (BUSINESS CONTEXT AD ALTISSIMO DETTAGLIO)
-- ----------------------------------------------------------------------------------------
-- La presente funzione [dbo].[SPRT_LTT_FAKE_OLD_2026_03_04] costituisce la versione di snapshot
-- architetturale intermedia salvata il 04/03/2026 durante il processo di refactoring delle
-- logiche di tracciabilità dei lotti e delle colate di Torneria Molinari Vincenzo (TMV).
--
-- IL CONTESTO STORICO E LA GENESI DEL REFACTORING DEL 04/03/2026:
-- Fino a marzo 2026, la funzione originaria (SPRT_LTT_FAKE_OLD) operava con un modello puramente
-- preventivo (deduzione del lotto più recente dalla distinta base PD95/PD96 e dai carichi MG7G/MG7I).
-- In data 04/03/2026, si rese necessario far evolvere la funzione affinché potesse risalire al
-- materiale REALE già scaricato in officina tramite il documento INT-SCARPROD (TipoDoc 24, STipoDoc 5).
--
-- IL PRIMO TENTATIVO DI IMPLEMENTAZIONE (QUESTO SCRIPT):
-- Questa versione rappresenta la PRIMA STESURA del nuovo STEP 1.
-- In questa implementazione, la risalita documentale venne formulata come una singola query monolitica
-- a 5 tabelle in JOIN diretta:
--    DO30_DOCCORPO (riga ODL) 
--    INNER JOIN DO33_DOCCORPORIF (collegamenti documentali)
--    INNER JOIN DO11_DOCTESTATA (testata scarico produzione)
--    INNER JOIN DO52_DOCCORPOLOT (lotti scaricati)
--    LEFT JOIN MG4G_ANAGRLOTTI (anagrafica lotti e colata)
-- con condizione di filtro: WHERE DO30.DO30_IDDISBA_PD95 = @IdDisba.
--
-- PERCHÉ QUESTA VERSIONE HA MANIFESTATO CRITICITÀ (TABLE SCAN E LENTEZZA):
-- L'esecuzione di una query multi-tabella con JOIN complesse all'interno di una Scalar User-Defined
-- Function (UDF) su SQL Server 2017 comporta gravi limiti prestazionali:
-- 1. Mancanza di Parallelismo: le UDF scalari forzano l'esecuzione su un singolo thread.
-- 2. Stime di Cardinalità Errate: il Query Optimizer non conosce a priori il numero di righe che
--    corrisponderanno a DO30_IDDISBA_PD95 = @IdDisba. Poiché DO30 non ha indice clustered su IDDISBA,
--    la combinazione con DO33_DOCCORPORIF (tabella da centinaia di migliaia di righe) induceva
--    il motore ad effettuare pesanti Nested Loop con Table Scan / Index Scan incrociati.
-- 3. Impatto Moltiplicativo: invocata per ogni singola riga della vista master VPRT_ODL_REPORT,
--    questa query provocava tempi di risposta inaccettabili e rischio di timeout.
--
-- LA RISOLUZIONE DEFINITIVA (MIGRAZIONE A SPRT_LTT_FAKE):
-- Per superare questo collo di bottiglia, Marco Bandera ha preservato questa versione come storico
-- di sicurezza (SPRT_LTT_FAKE_OLD_2026_03_04) e ha riscritto lo STEP 1 nella versione definitiva
-- SPRT_LTT_FAKE isolando preventivamente le chiavi primarie in variabili scalari (@DO30_DITTA,
-- @DO30_NUMREG, @DO30_PROGRIGA), trasformando la successiva scansione su DO33 in un Index Seek
-- istantaneo ad altissime prestazioni.
--
-- ----------------------------------------------------------------------------------------
-- STORICO REVISIONI (CHANGE LOG NARRATIVO COMPLETO E INTOCCABILE)
-- ----------------------------------------------------------------------------------------
-- Rev. 1
-- Data/Ora Modifica: 17/03/2024
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Creazione iniziale della logica deduttiva
-- Dettaglio:         Algoritmo originario di risalita da distinta base e disponibilità magazzino.
--
-- Rev. 2
-- Data/Ora Modifica: 2025-06-10 11:20
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Introduzione Ditta e attributi estesi CO5L
-- Dettaglio:         Aggiunta del filtro multi-ditta e del controllo di integrità su CO5L_DATA1.
--
-- Rev. 3 (Snapshot Storico Intermedio)
-- Data/Ora Modifica: 04/03/2026 15:35
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Prima stesura dello Step 1 con JOIN diretta a 5 tabelle per risalita scarico produzione
-- Dettaglio:         Inserimento della query di ricerca preferenziale da DO30 verso DO33/DO11/DO52.
--                    La query, pur concettualmente corretta nel risultato, generava elevato costo computazionale
--                    e table scan incrociati nella Scalar UDF, motivando la successiva riscrittura a due fasi.
--
-- Rev. 4
-- Data/Ora Modifica: 2026-09-23 10:45
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Standardizzazione cartiglio narrativo e commenti di analisi (Standard SOLVERIS)
-- Dettaglio:         1. Mantenimento del codice originario al 100% per finalità di confronto e audit storico.
--                    2. Redazione del cartiglio narrativo che documenta chiaramente le ragioni tecniche
--                       per cui questa implementazione monolitica è stata superata dalla versione definitiva.
-- ======================================================================================== */

CREATE OR ALTER FUNCTION [dbo].[SPRT_LTT_FAKE_OLD_2026_03_04]
(
	@IdDisba DECIMAL(18,0),
	@SEZIONE VARCHAR(10)
)
RETURNS CHAR(50)
AS
BEGIN
	-- ----------------------------------------------------------------------------------
	-- DICHIARAZIONE DELLE VARIABILI INTERNE
	-- ----------------------------------------------------------------------------------
	DECLARE @Risultato    CHAR(50) = NULL;
	DECLARE @Colata       CHAR(25) = NULL;
	DECLARE @PD96_COMPON  CHAR(25) = NULL;
	DECLARE @PD96_OPZIONE CHAR(20) = NULL;
	
	-- Variabile di controllo per determinare se il lotto è stato trovato nel percorso preferenziale
	DECLARE @LottoTrovato BIT      = 0;

	-- ==================================================================================
	-- STEP 1: RICERCA PREFERENZIALE ORIGINARIA (Join Diretta Multi-Tabella)
	-- ==================================================================================
	-- Questa formulazione esegue una join diretta tra DO30 e DO33 filtrando su DO30_IDDISBA_PD95.
	-- NOTA TECNICA DI AUDIT:
	-- Poiché DO30 non possiede un indice clustered su IDDISBA e DO33 è una tabella di transito
	-- voluminosa, questa query provocava table scan incrociati all'interno della Scalar UDF.
	-- Nella versione successiva definitiva, questo blocco è stato sostituito dalla logica
	-- a due fasi (Fase 1: estrazione chiavi in variabili; Fase 2: Index Seek puntuale su DO33).
	-- ==================================================================================
	SELECT TOP 1 
		@Risultato    = TRIM(DO52.DO52_CODART_MG66) + '.' + TRIM(DO52.DO52_OPZIONE_MG5E) + '_' + DO52.DO52_CODLOTTO_MG4G,
		@Colata       = MG4G.MG4G_DESCLOTTO,
		@PD96_COMPON  = DO52.DO52_CODART_MG66,
		@PD96_OPZIONE = DO52.DO52_OPZIONE_MG5E,
		@LottoTrovato = 1
	FROM dbo.DO30_DOCCORPO AS DO30 WITH (NOLOCK)
	-- Join con DO33 che mappa la riga vecchia (RIF) alla riga nuova dello scarico
	INNER JOIN dbo.DO33_DOCCORPORIF AS DO33 WITH (NOLOCK) 
		ON DO33.DO33_DITTA_CG18       = DO30.DO30_DITTA_CG18
		AND DO33.DO33_NUMREGRIF_CO99   = DO30.DO30_NUMREG_CO99
		AND DO33.DO33_PROGRIGARIF_DO30 = DO30.DO30_PROGRIGA
	-- Join con la testata del documento di destinazione (lo scarico produzione)
	INNER JOIN dbo.DO11_DOCTESTATA AS DO11 WITH (NOLOCK) 
		ON DO11.DO11_DITTA_CG18  = DO33.DO33_DITTA_CG18
		AND DO11.DO11_NUMREG_CO99 = DO33.DO33_NUMREG_CO99
	-- Join con i lotti movimentati sul documento di destinazione
	INNER JOIN dbo.DO52_DOCCORPOLOT AS DO52 WITH (NOLOCK) 
		ON DO52.DO52_DITTA_CG18   = DO33.DO33_DITTA_CG18
		AND DO52.DO52_NUMREG_CO99 = DO33.DO33_NUMREG_CO99
		AND DO52.DO52_PROGRIGA    = DO33.DO33_PROGRIGA
	-- Join sull'anagrafica lotti per recuperare la descrizione (Colata)
	LEFT JOIN dbo.MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK) 
		ON MG4G.MG4G_DITTA_CG18   = DO52.DO52_DITTA_CG18
		AND MG4G.MG4G_CODART_MG66 = DO52.DO52_CODART_MG66
		AND MG4G.MG4G_OPZIONE_MG5E = DO52.DO52_OPZIONE_MG5E
		AND MG4G.MG4G_CODLOTTO    = DO52.DO52_CODLOTTO_MG4G
	WHERE DO30.DO30_IDDISBA_PD95 = @IdDisba
	  AND DO11.DO11_TIPODOC       = 24  -- Documento di produzione
	  AND DO11.DO11_STIPODOC      = 5;  -- Sotto-tipo 5: Scarico componenti/materia prima

	-- ==================================================================================
	-- STEP 2: FALLBACK (Logica Originale Deduttiva da Distinta e Magazzino)
	-- ==================================================================================
	-- Se la query precedente non ha trovato alcuno scarico registrato (@LottoTrovato = 0),
	-- si attiva il fallback deduttivo: estrae l'ultimo lotto caricato della barra in distinta.
	-- ==================================================================================
	IF @LottoTrovato = 0
	BEGIN
		SELECT TOP 1 
			@Risultato    = TRIM(PD96_COMPON) + '.' + TRIM(PD96_OPZIONE) + '_' + [MG4G_CODLOTTO],
			@Colata       = MG4G_DESCLOTTO,
			@PD96_COMPON  = PD96_COMPON,
			@PD96_OPZIONE = PD96_OPZIONE
		FROM dbo.PD95_DISBA WITH (NOLOCK)
		INNER JOIN dbo.PD96_LEGAMIDISBA WITH (NOLOCK) 
			ON PD95_IDDISBA = PD96_IDDISBA_PD95
		INNER JOIN dbo.MG4G_ANAGRLOTTI WITH (NOLOCK) 
			ON PD95_DITTA_CG18   = MG4G_DITTA_CG18
			AND PD96_COMPON      = MG4G_CODART_MG66
			AND PD96_OPZIONE     = MG4G_OPZIONE_MG5E
		INNER JOIN dbo.MG7G_PROGQTAVARIREF WITH (NOLOCK) 
			ON MG4G_DITTA_CG18   = MG7G_DITTA_CG18 
			AND MG4G_CODART_MG66 = MG7G_CODART_MG66 
			AND MG4G_OPZIONE_MG5E = MG7G_OPZIONE_MG5E
			AND MG4G_CODLOTTO    = MG7G_CODLOTTO_MG4G
			AND MG7G_ANNO        = 0 
			AND MG7G_TIPOQTA     = 1 
			AND MG7G_TIPOPROG    = 1
		INNER JOIN dbo.MG7I_PROGQTAVARI WITH (NOLOCK) 
			ON MG7G_ID_MG7I      = MG7I_ID
		LEFT JOIN dbo.CO5L_ATTRIBUTIDEN WITH (NOLOCK) 
			ON MG4G_GUID         = CO5L_GUID
		WHERE PD95_IDDISBA = @IdDisba
		  AND [MG4G_CODLOTTO] <> 'LT-2403-999              '
		  AND CO5L_DATA1 IS NOT NULL
		ORDER BY 
			[MG4G_DATACRE] DESC, 
			MG4G_CODLOTTO DESC;
	END;

	-- ==================================================================================
	-- STEP 3: ASSEGNAZIONE DEL RISULTATO FINALE IN BASE A @SEZIONE
	-- ==================================================================================
	IF @SEZIONE = 'COLATA'
	BEGIN
		SET @Risultato = @Colata;
	END
	ELSE IF @SEZIONE = 'COMPON'
	BEGIN
		SET @Risultato = @PD96_COMPON;
	END		
	ELSE IF @SEZIONE = 'OPZIONE'
	BEGIN
		SET @Risultato = @PD96_OPZIONE;
	END;

	RETURN @Risultato;
END;
GO

