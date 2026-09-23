USE [DBTMV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ========================================================================================
-- OGGETTO:             [dbo].[SPRT_LTT_FAKE]
-- TIPO OGGETTO:        FUNZIONE SCALARE (UDF - USER DEFINED FUNCTION)
-- AMBIENTE/DATABASE:   MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
-- AUTORE:              SOLVERIS - Bandera Marco
-- DATA MODIFICA:       2026-09-23 10:35
--
-- ----------------------------------------------------------------------------------------
-- DESCRIZIONE FUNZIONALE E NARRATIVA (BUSINESS CONTEXT AD ALTISSIMO DETTAGLIO)
-- ----------------------------------------------------------------------------------------
-- La presente funzione [dbo].[SPRT_LTT_FAKE] costituisce il componente logico centrale per la
-- determinazione e la tracciabilità dei dati metallurgici di materia prima (Colata dell'acciaieria,
-- Codice Lotto fornitore/interno, Codice Articolo e Opzione componente) all'interno del flusso
-- di fabbricazione e reportistica operativa di Torneria Molinari Vincenzo (TMV).
--
-- CONTESTO INDUSTRIALE, METALLURGICO E DI REPARTO:
-- Negli stabilimenti TMV, la produzione di tiranti, prigionieri e componenti flangiati destinati
-- al settore Oil&Gas, petrolchimico e nucleare richiede il rispetto inderogabile della tracciabilità
-- 3.1 / 3.2 (EN 10204). Ciascun pezzo deve essere punzonato/marcato con la corretta sigla di colata
-- dell'acciaio e accompagnato da un cartellino viaggiatore (ODL) che rifletta fedelmente la materia
-- prima utilizzata nelle lavorazioni meccaniche (taglio, tornitura, rullatura dei filetti).
--
-- ARCHITETTURA DI RISOLUZIONE A DUE STADI (CONSUNTIVO EFFETTIVO VS PREVENTIVO DEDUTTIVO):
-- Nel ciclo di vita gestionale di un Ordine di Lavoro (ODL), il report di officina (generato dalla
-- vista master dbo.VPRT_ODL_REPORT) può essere emesso in due momenti temporali differenti:
--
-- 1. STADIO 1: A PRODUZIONE IN CORSO O COMPLETATA (Consuntivo Reale da Scarico):
--    Se l'officina ha già proceduto al prelievo della barra o del semilavorato da magazzino, il
--    sistema genera un documento di scarico produzione (INT-SCARPROD, DO11_TIPODOC = 24, STIPODOC = 5).
--    In questa circostanza, la funzione risale mediante la tabella dei collegamenti documentali
--    dbo.DO33_DOCCORPORIF direttamente alle righe del movimento di scarico e alla tabella lotti
--    dbo.DO52_DOCCORPOLOT. Tale risalita garantisce l'estrazione della "verità consuntiva": il lotto
--    e la colata restituiti coincidono al 100% con il materiale fisicamente prelevato e registrato
--    dall'operatore di magazzino.
--
-- 2. STADIO 2: A LANCIO ODL / ORDINE APERTO (Preventivo Deduttivo da Distinta e Magazzino):
--    Qualora il cartellino ODL venga stampato anticipatamente (prima che sia avvenuto lo scarico
--    fisico dei materiali a sistema), non esiste alcun record collegato in DO33 verso INT-SCARPROD.
--    In questo scenario, la funzione attiva il percorso di fallback: esplora la distinta base di
--    produzione dell'ODL (PD95/PD96), individua la materia prima (barra o semilavorato) e interroga
--    l'anagrafica lotti (MG4G_ANAGRLOTTI) incrociata con le giacenze e i progressivi di carico
--    (MG7G_PROGQTAVARIREF / MG7I_PROGQTAVARI). Preleva deterministamente il lotto più recente
--    (ordinato per MG4G_DATACRE DESC, MG4G_CODLOTTO DESC) escludendo lotti fittizi di collaudo.
--
-- POLIMORFISMO DEL PARAMETRO @SEZIONE:
-- La funzione è progettata per soddisfare molteplici fabbisogni informativi richiamando una sola logica:
-- - 'COLATA'  : Restituisce la descrizione del lotto (MG4G_DESCLOTTO), contenente la sigla della colata.
-- - 'LOTTO'   : Restituisce il codice identificativo del lotto (MG4G_CODLOTTO).
-- - 'COMPON'  : Restituisce il codice articolo della materia prima o componente di distinta (PD96_COMPON).
-- - 'OPZIONE' : Restituisce la variante dimensionale/tecnica del componente (PD96_OPZIONE).
-- - Default   : Stringa composita formattata per etichettatura (CodArt.Opzione_CodLotto).
--
-- ----------------------------------------------------------------------------------------
-- STORICO REVISIONI (CHANGE LOG NARRATIVO COMPLETO E INTOCCABILE)
-- ----------------------------------------------------------------------------------------
-- Rev. 1
-- Data/Ora Modifica: 17/03/2024
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Creazione iniziale della funzione di recupero lotti
-- Dettaglio:         Implementazione dell'algoritmo originario deduttivo basato sulla distinta base 
--                    (PD95/PD96), anagrafica lotti (MG4G) e carichi/giacenze (MG7G/MG7I). La logica 
--                    rispondeva all'esigenza di reperire un lotto "ragionevolmente corretto" al momento 
--                    della stampa del cartellino ODL prima delle registrazioni di magazzino.
--
-- Rev. 2
-- Data/Ora Modifica: 2025-06-10 11:20
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Filtro multi-ditta e integrazione attributi estesi
-- Dettaglio:         Introduzione della gestione esplicita della Ditta (CG18) e collegamento della tabella 
--                    estesa CO5L_ATTRIBUTIDEN tramite MG4G_GUID, con esclusione dei record privi di CO5L_DATA1 
--                    e del lotto fittizio di apertura inventario 'LT-2403-999'.
--
-- Rev. 3
-- Data/Ora Modifica: 2026-03-04 15:35
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Introduzione ricerca preferenziale da scarico effettivo e ottimizzazione chiavi di ricerca
-- Dettaglio:         1. Ristrutturazione architetturale: inserimento dello STEP 1 preferenziale per risalire 
--                       dalla riga ODL (DO30) al documento effettivo di scarico produzione (DO11 TIPODOC=24, 
--                       STIPODOC=5) tramite DO33 e lettura del lotto realmente impiegato (DO52/MG4G).
--                    2. Isolamento preliminare delle chiavi della riga ODL (DO30_DITTA, DO30_NUMREG, DO30_PROGRIGA) 
--                       in variabili dedicate per impedire table scan e timeout su join complesse.
--                    3. Relegazione dell'algoritmo di distinta e disponibilità a STEP 2 di fallback.
--
-- Rev. 4
-- Data/Ora Modifica: 2026-09-23 10:35
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Standardizzazione cartiglio narrativo e commenti discorsivi di codice (Standard SOLVERIS)
-- Dettaglio:         1. Redazione del cartiglio narrativo approfondito con spiegazione del contesto aziendale,
--                       metallurgico e dei due stadi operativi della funzione.
--                    2. Inserimento di commenti prolissi e discorsivi inline nel corpo del codice SQL per 
--                       illustrare il razionale di business di ogni costrutto relazionale.
--                    3. Conservazione al 100% della logica e sintassi operativa T-SQL in produzione.
-- ======================================================================================== */

CREATE OR ALTER FUNCTION [dbo].[SPRT_LTT_FAKE]
(
	@IdDisba DECIMAL(18,0),
	@SEZIONE VARCHAR(10)
)
RETURNS CHAR(50)
AS
BEGIN
	-- ----------------------------------------------------------------------------------
	-- DICHIARAZIONE DELLE VARIABILI INTERNE DI COSTRUZIONE DEL RISULTATO
	-- ----------------------------------------------------------------------------------
	-- @Risultato   : Stringa composita predefinita (CodArt.Opzione_CodLotto) restituita di default.
	-- @Colata      : Sigla della colata dell'acciaieria estratta dalla descrizione anagrafica lotto.
	-- @PD96_COMPON : Codice articolo della materia prima (barra trafilata o semilavorato).
	-- @PD96_OPZIONE: Variante tecnica/dimensionale associata alla materia prima.
	-- @Lotto       : Codice identificativo univoco del lotto registrato a magazzino.
	-- @LottoTrovato: Flag sentinella a 1 se lo Step 1 (scarico reale) ha avuto esito positivo.
	-- ----------------------------------------------------------------------------------
	DECLARE @Risultato    CHAR(50) = NULL;
	DECLARE @Colata       CHAR(25) = NULL;
	DECLARE @PD96_COMPON  CHAR(25) = NULL;
	DECLARE @PD96_OPZIONE CHAR(20) = NULL;
	DECLARE @Lotto        CHAR(25) = NULL;
	DECLARE @LottoTrovato BIT      = 0;

	-- ==================================================================================
	-- STEP 1: RICERCA PREFERENZIALE DA MOVIMENTO DI SCARICO DI PRODUZIONE EFFETTIVO
	-- ==================================================================================
	-- Razionale di Business:
	-- Se il lotto di materiale è già stato fisicamente prelevato e registrato a magazzino per
	-- questo ODL, il sistema deve riportare la verità storica certificata (consuntivo di scarico)
	-- anziché una previsione teorica. Si risale dalla riga ODL (DO30) al documento di scarico
	-- (INT-SCARPROD, TipoDoc 24, STipoDoc 5) attraverso la tabella di raccordo relazionale DO33.
	-- ==================================================================================
	DECLARE @DO30_DITTA    DECIMAL(5,0);
	DECLARE @DO30_NUMREG   CHAR(12)      = NULL;
	DECLARE @DO30_PROGRIGA DECIMAL(6,0);

	-- Fase 1: Identificazione puntuale delle chiavi primarie della riga ODL di origine.
	-- Questa query mirata estrae Ditta, NumReg e ProgRiga per evitare scansioni massive nelle join successive.
	SELECT TOP 1 
		@DO30_DITTA    = DO30_DITTA_CG18, 
		@DO30_NUMREG   = DO30_NUMREG_CO99, 
		@DO30_PROGRIGA = DO30_PROGRIGA
	FROM dbo.DO30_DOCCORPO WITH (NOLOCK)
	WHERE DO30_IDDISBA_PD95 = @IdDisba;

	-- Fase 2: Risalita documentale allo scarico di produzione collegato
	IF @DO30_NUMREG IS NOT NULL
	BEGIN
		SELECT TOP 1 
			@Risultato    = TRIM(DO52.DO52_CODART_MG66) + '.' + TRIM(DO52.DO52_OPZIONE_MG5E) + '_' + DO52.DO52_CODLOTTO_MG4G,
			@Colata       = MG4G.MG4G_DESCLOTTO,
			@Lotto        = MG4G.MG4G_CODLOTTO,
			@PD96_COMPON  = DO52.DO52_CODART_MG66,
			@PD96_OPZIONE = DO52.DO52_OPZIONE_MG5E,
			@LottoTrovato = 1
		FROM dbo.DO33_DOCCORPORIF AS DO33 WITH (NOLOCK) 
		INNER JOIN dbo.DO11_DOCTESTATA AS DO11 WITH (NOLOCK) 
			ON DO11.DO11_DITTA_CG18  = DO33.DO33_DITTA_CG18
			AND DO11.DO11_NUMREG_CO99 = DO33.DO33_NUMREG_CO99
		INNER JOIN dbo.DO52_DOCCORPOLOT AS DO52 WITH (NOLOCK) 
			ON DO52.DO52_DITTA_CG18   = DO33.DO33_DITTA_CG18
			AND DO52.DO52_NUMREG_CO99 = DO33.DO33_NUMREG_CO99
			AND DO52.DO52_PROGRIGA    = DO33.DO33_PROGRIGA
		LEFT JOIN dbo.MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK) 
			ON MG4G.MG4G_DITTA_CG18   = DO52.DO52_DITTA_CG18
			AND MG4G.MG4G_CODART_MG66 = DO52.DO52_CODART_MG66
			AND MG4G.MG4G_OPZIONE_MG5E = DO52.DO52_OPZIONE_MG5E
			AND MG4G.MG4G_CODLOTTO    = DO52.DO52_CODLOTTO_MG4G
		WHERE DO33.DO33_DITTA_CG18         = @DO30_DITTA
		  AND DO33.DO33_NUMREGRIF_CO99     = @DO30_NUMREG
		  AND DO33.DO33_PROGRIGARIF_DO30   = @DO30_PROGRIGA
		  AND DO11.DO11_TIPODOC            = 24  -- Documento di produzione
		  AND DO11.DO11_STIPODOC           = 5;  -- Sotto-tipo 5: Scarico componenti/materia prima
	END;

	-- ==================================================================================
	-- STEP 2: FALLBACK DEDUTTIVO DA DISTINTA BASE E PROGRESSIVI DI MAGAZZINO
	-- ==================================================================================
	-- Razionale di Business:
	-- Se l'ODL è in fase di lancio iniziale o non ha ancora subito registrazioni di scarico,
	-- lo Step 1 restituisce zero record (@LottoTrovato = 0). Si attiva quindi la logica
	-- storica di fallback: si interroga la distinta master dell'ODL (PD95/PD96) per trovare
	-- la barra componente, quindi si individua tra i lotti registrati in anagrafica (MG4G)
	-- aventi movimenti di magazzino (MG7G/MG7I) quello creato più recentemente.
	-- Viene escluso tassativamente il lotto fittizio di apertura 'LT-2403-999'.
	-- ==================================================================================
	IF @LottoTrovato = 0
	BEGIN
		SELECT TOP 1 
			@Risultato    = TRIM(PD96_COMPON) + '.' + TRIM(PD96_OPZIONE) + '_' + [MG4G_CODLOTTO],
			@Colata       = MG4G_DESCLOTTO,
			@Lotto        = MG4G_CODLOTTO,
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
	-- STEP 3: ASSEGNAZIONE DETERMINISTICA DEL VALORE DI RITORNO IN BASE A @SEZIONE
	-- ==================================================================================
	-- Smistamento del risultato richiesto dal chiamante (es. vista VPRT_ODL_REPORT):
	-- Permette al report di invocare la funzione per estrarre selettivamente Colata,
	-- Lotto, Codice Componente o Variante d'officina.
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
	END		
	ELSE IF @SEZIONE = 'LOTTO'
	BEGIN
		SET @Risultato = @Lotto;
	END;

	RETURN @Risultato;
END;
GO

