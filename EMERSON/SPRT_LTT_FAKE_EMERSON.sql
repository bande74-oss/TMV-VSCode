USE [DBTMV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ========================================================================================
-- OGGETTO:             [dbo].[SPRT_LTT_FAKE_EMERSON]
-- TIPO OGGETTO:        FUNZIONE SCALARE (UDF - USER DEFINED FUNCTION)
-- AMBIENTE/DATABASE:   MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
-- AUTORE:              SOLVERIS - Bandera Marco
-- DATA MODIFICA:       2026-09-23 10:35
--
-- ----------------------------------------------------------------------------------------
-- DESCRIZIONE FUNZIONALE E NARRATIVA (BUSINESS CONTEXT AD ALTISSIMO DETTAGLIO)
-- ----------------------------------------------------------------------------------------
-- La presente funzione [dbo].[SPRT_LTT_FAKE_EMERSON] è stata specificamente concepita e sviluppata
-- per governare le logiche speciali di marcatura e tracciabilità imposte dalle commesse del
-- cliente EMERSON PROCESS MANAGEMENT (e da committenti affini del settore Energy & Process).
--
-- IL REQUISITO DI BUSINESS EMERSON (COLATA FORZATA DA ORDINE CLIENTE / COLOR CODE):
-- A differenza dei clienti standard (per i quali il lotto e la colata vengono determinati
-- a valle dall'avanzamento fisico del reparto di taglio o magazzino), il cliente Emerson
-- concorda frequentemente all'atto dell'Ordine Commerciale (OC) l'utilizzo di una determinata
-- colata di acciaio già omologata e certificata (spesso identificata anche tramite "Color Corde"
-- o contrassegno a vernice sul fascio di barre).
--
-- Tale colata contrattuale viene inserita manualmente dall'Ufficio Vendite/Tecnico TMV
-- sulla riga dell'Ordine Cliente, precisamente nel campo esteso dbo.DO36_DOCCORPOEST.DO36_ALFST1
-- (esposto nella vista master dbo.VPRT_ODL_REPORT come COLATA_TIMBRARE).
--
-- RUOLO E FUNZIONAMENTO DELLA PROCEDURA:
-- La funzione agisce da "ponte risolutore inverso":
-- Riceve in ingresso:
-- 1. @DITTA     : Codice aziendale TMV (CG18, default 1).
-- 2. @CODART_MP : Il codice della materia prima (barra o semilavorato componente, estratto da PD96_COMPON).
-- 3. @OPZIONE_MP: La variante dimensionale/metallurgica della materia prima (estratta da PD96_OPZIONE).
-- 4. @COLATA    : La specifica sigla di colata forzata sulla riga dell'Ordine Cliente.
--
-- La funzione esegue una scansione mirata sull'anagrafica lotti aziendale (dbo.MG4G_ANAGRLOTTI):
-- cerca tutti i lotti registrati per quella precisa materia prima in cui la descrizione del lotto
-- corrisponde esattamente alla colata richiesta (MG4G_DESCLOTTO = @COLATA).
-- In presenza di più entrate o carichi storici aventi la medesima colata, ordina per data di creazione
-- decrescente ([MG4G_DATACRE] DESC, MG4G_CODLOTTO DESC) ed estrae con TOP 1 il lotto più recente.
--
-- Il valore restituito è la stringa univoca formattata:
--    [CodiceArticoloMP].[OpzioneMP]_[CodiceLottoMG4G]
-- Tale identificativo viene utilizzato dalla vista VPRT_ODL_REPORT (campo LOTTO_FAKE_EMERSON)
-- e dai layout di stampa Crystal Report per compilare i campi del cartellino viaggiatore.
--
-- ----------------------------------------------------------------------------------------
-- STORICO REVISIONI (CHANGE LOG NARRATIVO COMPLETO E INTOCCABILE)
-- ----------------------------------------------------------------------------------------
-- Rev. 1
-- Data/Ora Modifica: 28/11/2024
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Creazione iniziale della procedura per commesse Emerson
-- Dettaglio:         Implementazione della funzione di risalita lotto basata sulla corrispondenza 
--                    biunivoca tra l'anagrafica lotti (MG4G) e la colata forzata nel campo esteso 
--                    della riga Ordine Cliente (Color Code / DO36_ALFST1).
--
-- Rev. 2
-- Data/Ora Modifica: 2026-09-23 10:35
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Standardizzazione cartiglio narrativo e commenti discorsivi (Standard SOLVERIS)
-- Dettaglio:         1. Redazione del cartiglio narrativo esteso per illustrare il contesto commerciale 
--                       e metallurgico degli ordini Emerson e il raccordo con DO36_ALFST1.
--                    2. Inserimento di commenti esplicativi nel corpo del codice SQL.
--                    3. Inclusione sistematica dell'hint WITH (NOLOCK) sulle letture anagrafiche.
--                    4. Conservazione al 100% della logica e sintassi operativa T-SQL in produzione.
-- ======================================================================================== */

CREATE OR ALTER FUNCTION [dbo].[SPRT_LTT_FAKE_EMERSON]
(
	@DITTA      DECIMAL(5,0),
	@CODART_MP  CHAR(25),
	@OPZIONE_MP CHAR(20),
	@COLATA     VARCHAR(72)
)
RETURNS CHAR(70)
AS
BEGIN
	-- ----------------------------------------------------------------------------------
	-- DICHIARAZIONE DELLA VARIABILE DI RITORNO
	-- ----------------------------------------------------------------------------------
	-- @LOTTO_FAKE: Conterrà la stringa composita [CodArt].[Opzione]_[CodLotto]
	-- Inizializzata a stringa vuota per garantire un ritorno coerente in caso di mancata corrispondenza.
	-- ----------------------------------------------------------------------------------
	DECLARE @LOTTO_FAKE AS CHAR(70) = '';

	-- ----------------------------------------------------------------------------------
	-- ESTRAZIONE DETERMINISTICA DELL'ULTIMO LOTTO CORRISPONDENTE ALLA COLATA FORZATA
	-- ----------------------------------------------------------------------------------
	-- Ricerca in anagrafica lotti MG4G_ANAGRLOTTI per la specifica materia prima (barra).
	-- Il filtro vincola la selezione ai soli lotti la cui descrizione coincide esattamente
	-- con la colata richiesta contrattualmente da Emerson (@COLATA).
	-- L'ordinamento per data di creazione e codice decrescente assicura determinismo puro
	-- nell'estrazione del record TOP 1.
	-- L'utilizzo di WITH (NOLOCK) azzera qualsiasi contesa di lock in lettura concorrente.
	-- ----------------------------------------------------------------------------------
	SELECT TOP 1 
		@LOTTO_FAKE = TRIM([MG4G_CODART_MG66]) + '.' + TRIM([MG4G_OPZIONE_MG5E]) + '_' + MG4G_CODLOTTO
	FROM dbo.MG4G_ANAGRLOTTI WITH (NOLOCK)
	WHERE MG4G_DITTA_CG18   = @DITTA
	  AND MG4G_CODART_MG66  = @CODART_MP 
	  AND MG4G_OPZIONE_MG5E = @OPZIONE_MP
	  AND MG4G_DESCLOTTO    = @COLATA
	ORDER BY 
		MG4G_DATACRE DESC,
		MG4G_CODLOTTO DESC;

	-- ----------------------------------------------------------------------------------
	-- RESTITUZIONE DEL RISULTATO AL CHIAMANTE
	-- ----------------------------------------------------------------------------------
	RETURN @LOTTO_FAKE;
END;
GO

