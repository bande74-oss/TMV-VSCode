USE [DBTMV]
GO

/****** Object:  View [dbo].[VPRT_PLANNING_B7_TO_L7]    Script Date: 23/09/2026 13:30:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [dbo].[VPRT_PLANNING_B7_TO_L7]
AS
/*
========================================================================================================================
1 - DATA E ORA REVISIONE: 2026-09-23 13:30:00
2 - AUTORE              : SOLVERIS - Bandera Marco
3 - OGGETTO             : Vista [dbo].[VPRT_PLANNING_B7_TO_L7] (Aggiornamento Retrocompatibile per Tracciato TMV-PLANNING-04)
4 - AMBIENTE DI TARGET  : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database DBTMV
------------------------------------------------------------------------------------------------------------------------
5 - DESCRIZIONE AD ALTISSIMO DETTAGLIO (CONTESTO AZIENDALE, LOGICO E ARCHITETTURALE):
    Questo script aggiorna la vista originaria [dbo].[VPRT_PLANNING_B7_TO_L7] garantendo la PIENA RETROCOMPATIBILITA'
    con il tracciato configurabile TeamSystem Gamma Enterprise "TMV-PLANNING-04" (struttura 4, tracciato
    "TMV - genera ordini Fittizi B7 TO L7"), il quale mappa direttamente il nome tabella "VPRT_PLANNING_B7_TO_L7".

    SCOPO AZIENDALE:
    La vista permette di considerare la disponibilità di materie prime tondo/tiranti in acciaio legato ASTM A193 B7
    (sia ordini fornitore aperti che stock a magazzino) come disponibilità equivalente per ordini in acciaio criogenico
    ASTM A320 L7 / L7M all'interno del calcolo dei fabbisogni MRP.
    
    Il tracciato TMV-PLANNING-04 legge questa vista e genera ordini fornitore ombra/fittizi DF-ORDINE-B7L7 (TipoDoc 22),
    con il codice articolo convertito in L7, permettendo all'MRP di evitare acquisti doppi o prematuri.

    CRITICITA' STORICHE RISOLTE CON QUESTO AGGIORNAMENTO:
      1) Ripristino di 15.000 pezzi persi nell'MRP: La precedente clausola UNION eliminava gli ordini di acquisto
         aventi coincidenza di fornitore, articolo, data consegna e quantità residua. Con UNION ALL ogni ordine
         distinto viene preservato integralmente.
      2) Eliminazione del collo di bottiglia CLR .NET FORMAT(): La precedente espressione FORMAT(GETDATE(), ...)
         provocava conversioni di tipo inutili (datetime -> nvarchar -> datetime). La conversione nativa T-SQL
         CAST(CAST(GETDATE() AS DATE) AS DATETIME) azzera il consumo di CPU.
      3) Garanzia di azzeramento ordine 99999 (Sentinel 99999999 deterministica): Il record fittizio con quantità 0
         viene ora generato direttamente da CG18_ANADITTABASE, garantendo al 100% che l'ordine 99999 venga azzerato/aggiornato
         anche in totale assenza di giacenze fisiche B7 a magazzino.
      4) Ottimizzazione I/O ed Indici: Introdotti i filtri DO11_DITTA_CG18 = 1 e DO11_TIPODOC = 22 per abilitare
         l'Index Seek su IDX02_DO11 e clausole WITH (NOLOCK) su tutte le tabelle per prevenire lock di lettura.

    CONFORMITA' STANDARD SOLVERIS:
    Questo script adotta integralmente gli standard di codifica SOLVERIS (cartiglio narrativo esteso, commenti
    prolissi e discorsivi, clausole WITH (NOLOCK) sistematiche e compatibilità con MSSQL 2017).

------------------------------------------------------------------------------------------------------------------------
6 - STORICO COMPLETO DELLE REVISIONI (CHANGE LOG NARRATIVO SENZA TRONCAMENTI):
    - Rev. 0 (Originale): Creazione iniziale della vista per alimentare il tracciato TMV-PLANNING-04.
    - Rev. 1 (2025-04-29 - BM): Aggiunta del Ramo 3 su MG70 con QGIACATT = 0 per avere sempre la certezza che il fornitore
      fittizio 99999999 sia presente al fine di sfruttare la cancellazione dell'ordine fittizio relativo alle giacenze B7.
    - Rev. 2 (2026-09-23 - SOLVERIS - Bandera Marco): Applicazione correzioni critiche:
      passaggio a UNION ALL (fix perdita 15.000 pz), eliminazione funzione CLR FORMAT(), generazione deterministica
      del fornitore 99999999 da CG18_ANADITTABASE, filtri sargabili (DITTA, TIPODOC 22) e letture WITH (NOLOCK).
========================================================================================================================
*/

-- =====================================================================================================================
-- RAMO 1: ORDINI A FORNITORE REALI (DF-ORDINE) B7 TRASFORMATI IN L7
-- =====================================================================================================================
SELECT		
			DO30.DO30_DITTA_CG18
		,	DO11.DO11_TIPOCF_CG44
		,	DO11.DO11_CLIFOR_CG44
		,	REPLACE(REPLACE(DO30.DO30_CODART_MG66, 'B7-', 'L7-'), 'B7M', 'L7M') AS DO30_CODART_MG66
		,	DO30.DO30_OPZIONE_MG5E
		,	DO31.DO31_DATACONS
		,	DO31.DO31_DATACONSINT
		,	DO72.DO72_QTA1RES
			
FROM        dbo.DO11_DOCTESTATA DO11 WITH (NOLOCK)
			INNER JOIN dbo.DO30_DOCCORPO DO30 WITH (NOLOCK) 
				ON  DO11.DO11_DITTA_CG18  = DO30.DO30_DITTA_CG18 
				AND DO11.DO11_NUMREG_CO99 = DO30.DO30_NUMREG_CO99 
			INNER JOIN dbo.DO72_DOCCORPOSTATO DO72 WITH (NOLOCK) 
				ON  DO30.DO30_DITTA_CG18  = DO72.DO72_DITTA_CG18 
				AND DO30.DO30_NUMREG_CO99 = DO72.DO72_NUMREG_CO99 
				AND DO30.DO30_PROGRIGA    = DO72.DO72_PROGRIGA 
			INNER JOIN dbo.DO31_DOCCORPOORD DO31 WITH (NOLOCK) 
				ON  DO30.DO30_DITTA_CG18  = DO31.DO31_DITTA_CG18 
				AND DO30.DO30_NUMREG_CO99 = DO31.DO31_NUMREG_CO99 
				AND DO30.DO30_PROGRIGA    = DO31.DO31_PROGRIGA

			INNER JOIN dbo.MG87_ARTDESC MG87 WITH (NOLOCK)
				ON  DO30.DO30_DITTA_CG18 = MG87.MG87_DITTA_CG18
				AND REPLACE(REPLACE(DO30.DO30_CODART_MG66, 'B7-', 'L7-'), 'B7M', 'L7M') = MG87.MG87_CODART_MG66
				AND DO30.DO30_OPZIONE_MG5E = MG87.MG87_OPZIONE_MG5E
				AND MG87.MG87_LINGUA_MG52  = ''

WHERE       DO11.DO11_DITTA_CG18 = 1
		AND DO11.DO11_TIPODOC    = 22
		AND DO11.DO11_DOCUM_MG36 = 'DF-ORDINE' 
		AND DO72.DO72_FLGDAEVADERE = 1 
		AND DO72.DO72_QTA1RES > 0
		AND DO30.DO30_CODART_MG66 LIKE '%B7%' 
		AND SUBSTRING(DO30.DO30_CODART_MG66, 1, 3) IN ('TDP','TDL','TDR','TDF')

UNION ALL

-- =====================================================================================================================
-- RAMO 2: GIACENZE FISICHE DI MAGAZZINO (MG70) B7 CONVERTITE IN L7 (FORNITORE FITTIZIO 99999999)
-- =====================================================================================================================
SELECT		
			MG70.MG70_DITTA_CG18 
		,	CAST(1 AS DECIMAL(1,0)) AS DO11_TIPOCF_CG44
		,	CAST(99999999 AS DECIMAL(8,0)) AS DO11_CLIFOR_CG44
		,	REPLACE(REPLACE(MG70.MG70_CODART_MG66, 'B7-', 'L7-'), 'B7M', 'L7M') AS DO30_CODART_MG66
		,	MG70.MG70_OPZIONE_MG5E
		,	CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONS
		,	CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONSINT
		,	MG70.MG70_QGIACATT AS DO72_QTA1RES

FROM        dbo.MG70_MAGPROQTA MG70 WITH (NOLOCK)
			INNER JOIN dbo.MG87_ARTDESC MG87 WITH (NOLOCK)
				ON  MG70.MG70_DITTA_CG18 = MG87.MG87_DITTA_CG18
				AND REPLACE(REPLACE(MG70.MG70_CODART_MG66, 'B7-', 'L7-'), 'B7M', 'L7M') = MG87.MG87_CODART_MG66
				AND MG70.MG70_OPZIONE_MG5E = MG87.MG87_OPZIONE_MG5E
				AND MG87.MG87_LINGUA_MG52  = ''

WHERE       MG70.MG70_DITTA_CG18 = 1
		AND MG70.MG70_TIPOPROG   = 1
		AND MG70.MG70_ANNO       = 0
		AND MG70.MG70_TIPOQTA    = 1
		AND MG70.MG70_QGIACATT   > 0
		AND MG70.MG70_CODART_MG66 LIKE '%B7%' 
		AND SUBSTRING(MG70.MG70_CODART_MG66, 1, 3) IN ('TDP','TDL','TDR','TDF')

UNION ALL

-- =====================================================================================================================
-- RAMO 3: RECORD SENTINELLA FORNITORE 99999999 (RESET/SOVRASCRITTURA ORDINE FITTIZIO 99999)
-- =====================================================================================================================
SELECT	
			CG18.CG18_DITTA AS DO30_DITTA_CG18
		,	CAST(1 AS DECIMAL(1,0)) AS DO11_TIPOCF_CG44
		,	CAST(99999999 AS DECIMAL(8,0)) AS DO11_CLIFOR_CG44
		,	'TDP' AS DO30_CODART_MG66
		,	CAST('' AS VARCHAR(20)) AS DO30_OPZIONE_MG5E
		,	CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONS
		,	CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONSINT
		,	CAST(0 AS DECIMAL(14,3)) AS DO72_QTA1RES

FROM        dbo.CG18_ANADITTABASE CG18 WITH (NOLOCK)
WHERE       CG18.CG18_DITTA = 1
GO

