USE [DBTMV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ========================================================================================
-- OGGETTO:             [dbo].[SPRT_LTT_FAKE_OLD]
-- TIPO OGGETTO:        FUNZIONE SCALARE (UDF - USER DEFINED FUNCTION)
-- AMBIENTE/DATABASE:   MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
-- AUTORE:              SOLVERIS - Bandera Marco
-- DATA MODIFICA:       2026-09-23 10:35
--
-- ----------------------------------------------------------------------------------------
-- DESCRIZIONE FUNZIONALE E NARRATIVA (BUSINESS CONTEXT AD ALTISSIMO DETTAGLIO)
-- ----------------------------------------------------------------------------------------
-- La presente funzione [dbo].[SPRT_LTT_FAKE_OLD] rappresenta la prima implementazione operativa
-- e funzionante ideata per risolvere il problema dell'attribuzione preventiva del lotto di materia
-- prima e della relativa colata metallurgica nei cartellini di produzione (ODL) di TMV.
--
-- CHIARIMENTO SUL SUFFISSO "_OLD" (VERSIONE FUNZIONANTE MA NON DOTATA DI RISALITA SCARICO):
-- Il suffisso "_OLD" non deve essere inteso come codice deprecato o non valido: si tratta di una
-- logica pienamente funzionante e collaudata che implementa un MODELLO DEDUTTIVO / PREDITTIVO A PRIORI.
-- Tale modello operava prima dell'introduzione della risalita documentale allo scarico effettivo
-- (avvenuta successivamente nella versione SPRT_LTT_FAKE).
--
-- PRINCIPIO DI FUNZIONAMENTO (IL MODELLO PREDITTIVO DA DISTINTA E MAGAZZINO):
-- Quando un Ordine di Lavoro (ODL) viene pianificato e stampato in officina, l'operatore necessita
-- di conoscere con quale barra o tondo dovrà alimentare le macchine utensili (seghetti, torni, rullatrici).
-- Non esistendo ancora un prelievo fisico registrato a magazzino, la funzione procede per deduzione logica:
-- 1. Esplora la distinta base master dell'ODL (PD95_DISBA) e i suoi legami (PD96_LEGAMIDISBA) per
--    identificare la materia prima teorica necessaria (codice articolo e opzione/variante).
-- 2. Interroga l'anagrafica dei lotti (MG4G_ANAGRLOTTI) filtrando esclusivamente i lotti registrati
--    per quella specifica materia prima.
-- 3. Verifica l'effettiva movimentazione nei progressivi e carichi di magazzino (tabelle di raccordo
--    MG7G_PROGQTAVARIREF e MG7I_PROGQTAVARI, anno 0, tipo quantità 1, tipo progressivo 1).
-- 4. Esclude tassativamente i record privi di data attributo (CO5L_DATA1 IS NOT NULL) e il lotto
--    fittizio di apertura inventariale 'LT-2403-999'.
-- 5. Ordina i record in modo deterministico per data di creazione decrescente ([MG4G_DATACRE] DESC,
--    MG4G_CODLOTTO DESC) ed estrae il primo record utile (TOP 1).
--
-- In questo modo, l'ODL riceve a priori l'indicazione del lotto "ragionevolmente corretto"
-- (ovvero l'ultimo arrivato in azienda e disponibile per la lavorazione).
--
-- LIMITI RISOLTI NELLA VERSIONE SUCCESSIVA (MOTIVAZIONE DEL CONFRONTO):
-- Il limite intrinseco di questa logica è che, se l'operatore di officina preleva fisicamente una
-- barra appartenente a una colata differente rispetto all'ultima registrata, il cartellino ODL
-- rimarrebbe disallineato rispetto alla realtà. Per tale motivo, la successiva evoluzione SPRT_LTT_FAKE
-- ha anteposto a questa logica lo STEP 1 di controllo consuntivo del movimento INT-SCARPROD.
--
-- ----------------------------------------------------------------------------------------
-- STORICO REVISIONI (CHANGE LOG NARRATIVO COMPLETO E INTOCCABILE)
-- ----------------------------------------------------------------------------------------
-- Rev. 1
-- Data/Ora Modifica: 17/03/2024
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Creazione iniziale della funzione per il recupero del lotto in funzione dei carichi
-- Dettaglio:         Implementazione dell'algoritmo deduttivo originario basato su distinta ODL (PD95/PD96),
--                    anagrafica lotti (MG4G) e progressivi di magazzino (MG7G/MG7I). La funzione consentiva
--                    di emettere i documenti di fabbricazione con la proposta del lotto più recente.
--
-- Rev. 2
-- Data/Ora Modifica: 2026-09-23 10:35
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Standardizzazione cartiglio narrativo e commenti discorsivi (Standard SOLVERIS)
-- Dettaglio:         1. Mantenimento integrale della sintassi e dell'algoritmo originario senza alterazioni.
--                    2. Inserimento del cartiglio narrativo approfondito con spiegazione del contesto storico
--                       e chiarimento sul valore del suffisso "_OLD".
--                    3. Integrazione di commenti estesi nel corpo della query per facilitare il confronto
--                       architetturale con la versione evoluta SPRT_LTT_FAKE.
-- ======================================================================================== */

CREATE OR ALTER FUNCTION [dbo].[SPRT_LTT_FAKE_OLD]
(
	@IdDisba DECIMAL(18,0),
	@SEZIONE VARCHAR(10) = 'CODLOTTO'
)
RETURNS CHAR(50)
AS
BEGIN
	-- ----------------------------------------------------------------------------------
	-- DICHIARAZIONE DELLE VARIABILI INTERNE PER L'ESTRAZIONE DEI DATI
	-- ----------------------------------------------------------------------------------
	DECLARE @Risultato    CHAR(50);
	DECLARE @Colata       CHAR(25);
	DECLARE @PD96_COMPON  CHAR(25);
	DECLARE @PD96_OPZIONE CHAR(20);

	-- ----------------------------------------------------------------------------------
	-- ESECUZIONE QUERY DEDUTTIVA DA DISTINTA BASE E PROGRESSIVI DI CARICO MAGAZZINO
	-- ----------------------------------------------------------------------------------
	-- La sottoquery interna unisce la distinta base dell'ODL (PD95/PD96) con l'anagrafica lotti (MG4G)
	-- e con i progressivi annuali/totali di magazzino (MG7G/MG7I) per individuare il lotto
	-- più recente avente disponibilità fisica registrata.
	-- ----------------------------------------------------------------------------------
	SELECT TOP 1 
		@Risultato    = TRIM(PD96_COMPON) + '.' + TRIM(PD96_OPZIONE) + '_' + [MG4G_CODLOTTO],
		@Colata       = MG4G_DESCLOTTO,
		@PD96_COMPON  = PD96_COMPON,
		@PD96_OPZIONE = PD96_OPZIONE
	FROM 
	(
		SELECT 
			[MG4G_CODLOTTO],
			[MG4G_DATACRE],
			MG7I_QGIACATT,
			PD96_COMPON,
			PD96_OPZIONE,
			MG4G_ANAGRLOTTI.MG4G_DESCLOTTO
		FROM dbo.PD95_DISBA WITH (NOLOCK)
		INNER JOIN dbo.PD96_LEGAMIDISBA WITH (NOLOCK)
			ON PD95_IDDISBA = PD96_IDDISBA_PD95
		INNER JOIN dbo.MG4G_ANAGRLOTTI WITH (NOLOCK)
			ON  PD95_DITTA_CG18   = MG4G_DITTA_CG18
			AND PD96_COMPON      = MG4G_CODART_MG66
			AND PD96_OPZIONE     = MG4G_OPZIONE_MG5E
		INNER JOIN dbo.MG7G_PROGQTAVARIREF WITH (NOLOCK)
			ON  MG4G_DITTA_CG18   = MG7G_DITTA_CG18 
			AND MG4G_CODART_MG66 = MG7G_CODART_MG66 
			AND MG4G_OPZIONE_MG5E = MG7G_OPZIONE_MG5E
			AND MG4G_CODLOTTO    = MG7G_CODLOTTO_MG4G
			AND 0 = MG7G_ANNO       -- Anno 0: Progressivo totale di magazzino
			AND 1 = MG7G_TIPOQTA    -- Tipo Quantità 1
			AND 1 = MG7G_TIPOPROG   -- Tipo Progressivo 1: Carico/Giacenza
		INNER JOIN dbo.MG7I_PROGQTAVARI WITH (NOLOCK)
			ON MG7G_ID_MG7I = MG7I_ID
		LEFT JOIN dbo.CO5L_ATTRIBUTIDEN WITH (NOLOCK)
			ON MG4G_GUID = CO5L_GUID
		WHERE PD95_IDDISBA = @IdDisba
		  AND [MG4G_CODLOTTO] <> 'LT-2403-999              ' -- Esclusione del lotto fittizio di collaudo
		  AND CO5L_DATA1 IS NOT NULL                        -- Verifica obbligatorietà data attributo esteso
	) AS LTT_FAKE
	ORDER BY 
		[MG4G_DATACRE] DESC, 
		MG4G_CODLOTTO DESC;

	-- ----------------------------------------------------------------------------------
	-- ASSEGNAZIONE DEL RISULTATO IN BASE ALLA SEZIONE RICHIESTA
	-- ----------------------------------------------------------------------------------
	-- Gestione delle sezioni supportate nella versione originaria (COLATA, COMPON, OPZIONE).
	-- Se non specificato, restituisce la stringa composita di identificazione lotto.
	-- ----------------------------------------------------------------------------------
	IF @SEZIONE = 'COLATA'
	BEGIN
		SET @Risultato = @Colata;
	END;

	IF @SEZIONE = 'COMPON'
	BEGIN
		SET @Risultato = @PD96_COMPON;
	END;

	IF @SEZIONE = 'OPZIONE'
	BEGIN
		SET @Risultato = @PD96_OPZIONE;
	END;

	RETURN @Risultato;
END;
GO

